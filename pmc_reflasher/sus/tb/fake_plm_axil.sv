// AXI4-Lite slave model of the Versal IPI block plus a toy PLM, for simulating
// pmc_pdi_loader / AIEPdiLoader without hardware.
//
// Models, at their real LPD addresses:
//   IPI<n> TRIG (base+0, write-only: setting bit 1 raises OBS bit 1)
//   IPI<n> OBS  (base+4, read-only)
//   message RAM 0xFF3F0000 .. 0xFF3F0FFF (4 KiB, RW)
// Everything else answers DECERR (2'b11), like an unmapped LPD address would.
//
// "PLM": PLM_DELAY cycles after TRIG it writes {plm_status, plm_loader_status} into the
// PMC->IPI<n> response buffer and clears OBS. With plm_never_ack=1 it stays silent, to
// exercise the loader's timeout path.

module fake_plm_axil #(
    parameter int PLM_DELAY   = 200
)(
    input  logic        aclk,
    input  logic        aresetn,
    // AXI4 slave (single-beat only: awlen/arlen must be 0, checked at runtime)
    input  logic [63:0] awaddr,
    input  logic [7:0]  awlen,
    input  logic [2:0]  awsize,
    input  logic [1:0]  awburst,
    input  logic        awvalid,
    output logic        awready,
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    input  logic        wlast,
    input  logic        wvalid,
    output logic        wready,
    output logic [1:0]  bresp,
    output logic        bvalid,
    input  logic        bready,
    input  logic [63:0] araddr,
    input  logic [7:0]  arlen,
    input  logic [2:0]  arsize,
    input  logic [1:0]  arburst,
    input  logic        arvalid,
    output logic        arready,
    output logic [31:0] rdata,
    output logic [1:0]  rresp,
    output logic        rlast,
    output logic        rvalid,
    input  logic        rready,
    // test knobs
    input  logic [31:0] plm_status,
    input  logic [31:0] plm_loader_status,
    input  logic        plm_never_ack,
    input  logic        decerr_all,     // 1: answer DECERR to everything (unreachable LPD)
    input  logic        obs_preset,     // 1: OBS PMC bit stuck high (stale request)
    input  logic [2:0]  ipi_channel     // which IPI<n> block (0..5) the model implements
);
    localparam logic [31:0] MSG_RAM  = 32'hFF3F0000;
    logic [31:0] IPI_BASE, RESP_BUF;
    assign IPI_BASE = 32'hFF330000 + ipi_channel * 32'h10000;
    assign RESP_BUF = MSG_RAM + (2 + ipi_channel) * 32'h200 + 32'h40 + 32'h20;  // requester's slot + 0x20 (xipipsu_buf.c)

    logic [31:0] ram [0:1023];   // 4 KiB message RAM, word addressed
    logic        obs_pmc;        // OBS bit 1 of our channel
    int          plm_timer;

    function automatic bit in_ram(input logic [63:0] a);
        return (a >= MSG_RAM) && (a < MSG_RAM + 32'h1000);
    endfunction

    // ---- write channel: accept address and data, then respond ----
    logic        aw_got, w_got;
    logic [63:0] aw_q;
    logic [31:0] w_q;
    logic [3:0]  wstrb_q;
    assign awready = !aw_got;
    assign wready  = !w_got;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            aw_got <= 0; w_got <= 0; bvalid <= 0; bresp <= 0;
            obs_pmc <= 0; plm_timer <= -1;
        end else begin
            if (awvalid && awready) begin
                aw_got <= 1; aw_q <= awaddr;
                if (awlen != 0 || awsize != 2 || awburst != 2'b01) $error("fake_plm: unsupported AW len=%0d size=%0d burst=%0d", awlen, awsize, awburst);
            end
            if (wvalid  && wready)  begin
                w_got  <= 1; w_q <= wdata; wstrb_q <= wstrb;
                if (!wlast) $error("fake_plm: wlast not set on single-beat write");
            end
            if (bvalid && bready) bvalid <= 0;
            if (aw_got && w_got && !bvalid) begin
                aw_got <= 0; w_got <= 0; bvalid <= 1;
                $display("[%0t] WRITE addr=%h data=%h strb=%b -> %s", $time, aw_q, w_q, wstrb_q,
                         in_ram(aw_q) ? "ram" : (aw_q == IPI_BASE ? "TRIG" : "DECERR"));
                if (decerr_all) begin
                    bresp <= 2'b11;
                end else if (in_ram(aw_q)) begin
                    for (int b = 0; b < 4; b++) if (wstrb_q[b]) ram[(aw_q - MSG_RAM) >> 2][8*b +: 8] <= w_q[8*b +: 8];
                    bresp <= 2'b00;
                end else if (aw_q == IPI_BASE) begin        // TRIG
                    if (w_q[1]) begin obs_pmc <= 1; plm_timer <= PLM_DELAY; end
                    bresp <= 2'b00;
                end else begin
                    bresp <= 2'b11;                          // DECERR
                end
            end
            // toy PLM
            if (plm_timer > 0) plm_timer <= plm_timer - 1;
            if (plm_timer == 0) begin
                plm_timer <= -1;
                if (!plm_never_ack) begin
                    ram[(RESP_BUF - MSG_RAM) >> 2]     <= plm_status;
                    ram[(RESP_BUF - MSG_RAM) >> 2 + 1] <= plm_loader_status;
                    obs_pmc <= 0;
                end
            end
        end
    end

    // ---- read channel ----
    assign arready = !rvalid;
    assign rlast = 1'b1;
    always_ff @(posedge aclk) begin
        if (!aresetn) begin rvalid <= 0; rdata <= 0; rresp <= 0; end
        else begin
            if (rvalid && rready) rvalid <= 0;
            if (arvalid && arready) begin
                rvalid <= 1;
                if (arlen != 0 || arsize != 2 || arburst != 2'b01) $error("fake_plm: unsupported AR len=%0d size=%0d burst=%0d", arlen, arsize, arburst);
                $display("[%0t] READ  addr=%h -> %s", $time, araddr,
                         in_ram(araddr) ? "ram" : (araddr == IPI_BASE+4 ? "OBS" : "DECERR"));
                if (decerr_all)                begin rdata <= 32'hDEADDEAD; rresp <= 2'b11; end
                else if (in_ram(araddr))       begin rdata <= ram[(araddr - MSG_RAM) >> 2]; rresp <= 2'b00; end
                else if (araddr == IPI_BASE+4) begin rdata <= {30'b0, obs_pmc | obs_preset, 1'b0};      rresp <= 2'b00; end
                else                           begin rdata <= 32'hDEADDEAD;                 rresp <= 2'b11; end
            end
        end
    end
endmodule
