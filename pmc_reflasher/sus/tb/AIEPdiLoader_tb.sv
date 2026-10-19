// Testbench: AIEPdiLoader against fake_plm_axil. Drives the Tapasco control slave the way
// tlkm does (write args, write CTRL bit 0, wait for intr, read result at 0x10).
`timescale 1ns/1ps
module AIEPdiLoader_tb;
    logic aclk = 0; always #2 aclk = !aclk;   // 250 MHz
    logic aresetn = 0;

    // control slave
    logic [11:0] s_awaddr; logic s_awvalid; logic s_awready;
    logic [63:0] s_wdata; logic [7:0] s_wstrb; logic s_wvalid; logic s_wready;
    logic [1:0] s_bresp; logic s_bvalid; logic s_bready;
    logic [11:0] s_araddr; logic s_arvalid; logic s_arready;
    logic [63:0] s_rdata; logic [1:0] s_rresp; logic s_rvalid; logic s_rready;
    logic intr;
    // small_axil master
    logic [63:0] m_awaddr; logic [2:0] m_awprot; logic m_awvalid, m_awready;
    logic [31:0] m_wdata; logic [3:0] m_wstrb; logic m_wvalid, m_wready;
    logic [1:0] m_bresp; logic m_bvalid, m_bready;
    logic [63:0] m_araddr; logic [2:0] m_arprot; logic m_arvalid, m_arready;
    logic [31:0] m_rdata; logic [1:0] m_rresp; logic m_rvalid, m_rready;
    // knobs
    logic [31:0] plm_status = 0, plm_loader_status = 0; logic plm_never_ack = 0; logic decerr_all = 0;

    AIEPdiLoader dut(
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_control_awaddr(s_awaddr), .s_axi_control_awvalid(s_awvalid), .s_axi_control_awready(s_awready),
        .s_axi_control_wdata(s_wdata), .s_axi_control_wstrb(s_wstrb), .s_axi_control_wvalid(s_wvalid), .s_axi_control_wready(s_wready),
        .s_axi_control_bresp(s_bresp), .s_axi_control_bvalid(s_bvalid), .s_axi_control_bready(s_bready),
        .s_axi_control_araddr(s_araddr), .s_axi_control_arvalid(s_arvalid), .s_axi_control_arready(s_arready),
        .s_axi_control_rdata(s_rdata), .s_axi_control_rresp(s_rresp), .s_axi_control_rvalid(s_rvalid), .s_axi_control_rready(s_rready),
        .intr(intr),
        .small_axil_awaddr(m_awaddr), .small_axil_awprot(m_awprot), .small_axil_awvalid(m_awvalid), .small_axil_awready(m_awready),
        .small_axil_wdata(m_wdata), .small_axil_wstrb(m_wstrb), .small_axil_wvalid(m_wvalid), .small_axil_wready(m_wready),
        .small_axil_bresp(m_bresp), .small_axil_bvalid(m_bvalid), .small_axil_bready(m_bready),
        .small_axil_araddr(m_araddr), .small_axil_arprot(m_arprot), .small_axil_arvalid(m_arvalid), .small_axil_arready(m_arready),
        .small_axil_rdata(m_rdata), .small_axil_rresp(m_rresp), .small_axil_rvalid(m_rvalid), .small_axil_rready(m_rready)
    );

    fake_plm_axil #(.IPI_CHANNEL(5), .PLM_DELAY(200)) plm(
        .aclk(aclk), .aresetn(aresetn),
        .awaddr(m_awaddr), .awvalid(m_awvalid), .awready(m_awready),
        .wdata(m_wdata), .wstrb(m_wstrb), .wvalid(m_wvalid), .wready(m_wready),
        .bresp(m_bresp), .bvalid(m_bvalid), .bready(m_bready),
        .araddr(m_araddr), .arvalid(m_arvalid), .arready(m_arready),
        .rdata(m_rdata), .rresp(m_rresp), .rvalid(m_rvalid), .rready(m_rready),
        .plm_status(plm_status), .plm_loader_status(plm_loader_status), .plm_never_ack(plm_never_ack), .decerr_all(decerr_all)
    );

    task ctrl_write(input [11:0] addr, input [63:0] data);
        @(posedge aclk); s_awaddr <= addr; s_awvalid <= 1; s_wdata <= data; s_wstrb <= 8'hFF; s_wvalid <= 1; s_bready <= 1;
        wait (s_awready && s_awvalid); @(posedge aclk); s_awvalid <= 0;
        wait (s_wready && s_wvalid);   @(posedge aclk); s_wvalid <= 0;
        wait (s_bvalid); @(posedge aclk); s_bready <= 0;
    endtask
    task ctrl_read(input [11:0] addr, output [63:0] data);
        @(posedge aclk); s_araddr <= addr; s_arvalid <= 1; s_rready <= 1;
        wait (s_arready && s_arvalid); @(posedge aclk); s_arvalid <= 0;
        wait (s_rvalid); data = s_rdata; @(posedge aclk); s_rready <= 0;
    endtask

    task run_case(input string name, input [31:0] st, input never, input decerr, input [63:0] expect_lo);
        logic [63:0] r;
        plm_status = st; plm_never_ack = never; decerr_all = decerr;
        ctrl_write(12'h020, 64'h0000_0100_0020_0000);  // PDI at PS 0x100_0020_0000
        ctrl_write(12'h030, 64'h0);                     // AxPROT = 0
        ctrl_write(12'h000, 64'h1);                     // start
        wait (intr);
        ctrl_read(12'h010, r);                           // result register (tapasco_ctrl_slave layout)
        if (r[31:0] !== expect_lo[31:0]) $error("%s: result[31:0]=%h expected %h", name, r[31:0], expect_lo[31:0]);
        else $display("%s: OK result=%h", name, r);
        ctrl_write(12'h000, 64'h0);                     // tlkm-style interrupt clear write, harmless
        repeat (20) @(posedge aclk);
    endtask

    initial begin
        s_awvalid = 0; s_wvalid = 0; s_bready = 0; s_arvalid = 0; s_rready = 0;
        repeat (5) @(posedge aclk); aresetn = 1; repeat (5) @(posedge aclk);
        run_case("happy",   32'h0,    0, 0, 64'h0);
        run_case("plm_err", 32'h1234, 0, 0, 64'h1234);
        run_case("decerr",  32'h0,    0, 1, 64'hFFFFFF01);
        // timeout case needs a TB build with a small TIMEOUT_CYCLES (edit gen int in the .sus)
        $finish;
    end
endmodule
