// Testbench: AIEPdiLoader PE -> Tapasco PDILoader core -> fake_plm_axil. Drives the Tapasco control
// slave the way tlkm does (write args, write CTRL bit 0, wait for intr, read result at 0x10). The
// PDILoader is the one the PDI-Loader feature instantiates ($TAPASCO_HOME_TCL/common/ip/PDILoader);
// its IPI channel and timeout are parameters (the feature sets them from its properties), so there is
// one loader instance per parameter set under test and `sel` picks which one faces the PE and the PLM.
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
    // PDILoad interface between the PE and the selected loader
    logic start_valid, start_ready; logic [63:0] start_addr;
    logic finish_valid, finish_ready; logic [7:0] finish_error; logic [31:0] finish_status, finish_loader_status;
    // M_AXI_LPD of the selected loader
    logic [63:0] m_awaddr; logic [7:0] m_awlen; logic [2:0] m_awsize; logic [1:0] m_awburst; logic m_awvalid, m_awready;
    logic [31:0] m_wdata; logic [3:0] m_wstrb; logic m_wlast, m_wvalid, m_wready;
    logic [1:0] m_bresp; logic m_bvalid, m_bready;
    logic [63:0] m_araddr; logic [7:0] m_arlen; logic [2:0] m_arsize; logic [1:0] m_arburst; logic m_arvalid, m_arready;
    logic [31:0] m_rdata; logic [1:0] m_rresp; logic m_rlast, m_rvalid, m_rready;
    // PLM model knobs
    logic [31:0] plm_status = 0, plm_loader_status = 0; logic plm_never_ack = 0; logic ack_early = 0; logic decerr_all = 0; logic obs_preset = 0;
    logic [2:0] model_channel = 5;

    AIEPdiLoader dut(
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_control_awaddr(s_awaddr), .s_axi_control_awvalid(s_awvalid), .s_axi_control_awready(s_awready),
        .s_axi_control_wdata(s_wdata), .s_axi_control_wstrb(s_wstrb), .s_axi_control_wvalid(s_wvalid), .s_axi_control_wready(s_wready),
        .s_axi_control_bresp(s_bresp), .s_axi_control_bvalid(s_bvalid), .s_axi_control_bready(s_bready),
        .s_axi_control_araddr(s_araddr), .s_axi_control_arvalid(s_arvalid), .s_axi_control_arready(s_arready),
        .s_axi_control_rdata(s_rdata), .s_axi_control_rresp(s_rresp), .s_axi_control_rvalid(s_rvalid), .s_axi_control_rready(s_rready),
        .intr(intr),
        .M_PDI_LOAD_start_valid(start_valid), .M_PDI_LOAD_start_ready(start_ready), .M_PDI_LOAD_start_addr(start_addr),
        .M_PDI_LOAD_finish_valid(finish_valid), .M_PDI_LOAD_finish_ready(finish_ready),
        .M_PDI_LOAD_finish_error(finish_error), .M_PDI_LOAD_finish_status(finish_status),
        .M_PDI_LOAD_finish_loader_status(finish_loader_status)
    );

    // the loaders under test: (IPI_CHANNEL, TIMEOUT_CYCLES)
    localparam int NUM_LOADERS = 3;
    localparam int CHANNELS [NUM_LOADERS] = '{5, 2, 0};
    localparam int TIMEOUTS [NUM_LOADERS] = '{1 << 30, 2000, 1 << 30};   // loader 1 times out quickly
    int sel = 0;
    logic [NUM_LOADERS-1:0] l_start_ready, l_finish_valid, l_awvalid, l_wvalid, l_wlast, l_arvalid, l_bready, l_rready;
    logic [7:0]  l_finish_error [NUM_LOADERS];
    logic [31:0] l_finish_status [NUM_LOADERS], l_finish_loader_status [NUM_LOADERS], l_wdata [NUM_LOADERS];
    logic [63:0] l_awaddr [NUM_LOADERS], l_araddr [NUM_LOADERS];
    logic [7:0]  l_awlen [NUM_LOADERS], l_arlen [NUM_LOADERS];
    logic [2:0]  l_awsize [NUM_LOADERS], l_arsize [NUM_LOADERS];
    logic [1:0]  l_awburst [NUM_LOADERS], l_arburst [NUM_LOADERS];
    logic [3:0]  l_wstrb [NUM_LOADERS];
    for (genvar g = 0; g < NUM_LOADERS; g++) begin : loaders
        PDILoader #(.IPI_CHANNEL(CHANNELS[g]), .TIMEOUT_CYCLES(TIMEOUTS[g])) loader(
            .aclk(aclk), .aresetn(aresetn),
            .S_PDI_LOAD_start_valid(start_valid && sel == g), .S_PDI_LOAD_start_ready(l_start_ready[g]),
            .S_PDI_LOAD_start_addr(start_addr),
            .S_PDI_LOAD_finish_valid(l_finish_valid[g]), .S_PDI_LOAD_finish_ready(finish_ready),
            .S_PDI_LOAD_finish_error(l_finish_error[g]), .S_PDI_LOAD_finish_status(l_finish_status[g]),
            .S_PDI_LOAD_finish_loader_status(l_finish_loader_status[g]),
            .M_AXI_LPD_awaddr(l_awaddr[g]), .M_AXI_LPD_awlen(l_awlen[g]), .M_AXI_LPD_awsize(l_awsize[g]),
            .M_AXI_LPD_awburst(l_awburst[g]), .M_AXI_LPD_awlock(), .M_AXI_LPD_awcache(), .M_AXI_LPD_awprot(),
            .M_AXI_LPD_awqos(), .M_AXI_LPD_awregion(),
            .M_AXI_LPD_awvalid(l_awvalid[g]), .M_AXI_LPD_awready(m_awready && sel == g),
            .M_AXI_LPD_wdata(l_wdata[g]), .M_AXI_LPD_wstrb(l_wstrb[g]), .M_AXI_LPD_wlast(l_wlast[g]),
            .M_AXI_LPD_wvalid(l_wvalid[g]), .M_AXI_LPD_wready(m_wready && sel == g),
            .M_AXI_LPD_bresp(m_bresp), .M_AXI_LPD_bvalid(m_bvalid && sel == g), .M_AXI_LPD_bready(l_bready[g]),
            .M_AXI_LPD_araddr(l_araddr[g]), .M_AXI_LPD_arlen(l_arlen[g]), .M_AXI_LPD_arsize(l_arsize[g]),
            .M_AXI_LPD_arburst(l_arburst[g]), .M_AXI_LPD_arlock(), .M_AXI_LPD_arcache(), .M_AXI_LPD_arprot(),
            .M_AXI_LPD_arqos(), .M_AXI_LPD_arregion(),
            .M_AXI_LPD_arvalid(l_arvalid[g]), .M_AXI_LPD_arready(m_arready && sel == g),
            .M_AXI_LPD_rdata(m_rdata), .M_AXI_LPD_rresp(m_rresp), .M_AXI_LPD_rlast(m_rlast),
            .M_AXI_LPD_rvalid(m_rvalid && sel == g), .M_AXI_LPD_rready(l_rready[g])
        );
    end
    assign start_ready = l_start_ready[sel];
    assign finish_valid = l_finish_valid[sel];
    assign finish_error = l_finish_error[sel];
    assign finish_status = l_finish_status[sel];
    assign finish_loader_status = l_finish_loader_status[sel];
    assign m_awaddr = l_awaddr[sel]; assign m_awlen = l_awlen[sel]; assign m_awsize = l_awsize[sel]; assign m_awburst = l_awburst[sel];
    assign m_awvalid = l_awvalid[sel]; assign m_wdata = l_wdata[sel]; assign m_wstrb = l_wstrb[sel]; assign m_wlast = l_wlast[sel];
    assign m_wvalid = l_wvalid[sel]; assign m_bready = l_bready[sel];
    assign m_araddr = l_araddr[sel]; assign m_arlen = l_arlen[sel]; assign m_arsize = l_arsize[sel]; assign m_arburst = l_arburst[sel];
    assign m_arvalid = l_arvalid[sel]; assign m_rready = l_rready[sel];

    fake_plm_axil #(.PLM_DELAY(200)) plm(
        .aclk(aclk), .aresetn(aresetn),
        .awaddr(m_awaddr), .awlen(m_awlen), .awsize(m_awsize), .awburst(m_awburst), .awvalid(m_awvalid), .awready(m_awready),
        .wdata(m_wdata), .wstrb(m_wstrb), .wlast(m_wlast), .wvalid(m_wvalid), .wready(m_wready),
        .bresp(m_bresp), .bvalid(m_bvalid), .bready(m_bready),
        .araddr(m_araddr), .arlen(m_arlen), .arsize(m_arsize), .arburst(m_arburst), .arvalid(m_arvalid), .arready(m_arready),
        .rdata(m_rdata), .rresp(m_rresp), .rlast(m_rlast), .rvalid(m_rvalid), .rready(m_rready),
        .plm_status(plm_status), .plm_loader_status(plm_loader_status), .plm_never_ack(plm_never_ack), .ack_early(ack_early), .decerr_all(decerr_all), .obs_preset(obs_preset),
        .ipi_channel(model_channel)
    );

    int errors = 0;

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

    // loader: index into CHANNELS/TIMEOUTS; chan_model: the channel the fake IPI block implements
    task run_case(input string name, input [31:0] st, input never, input decerr, input busy,
                  input int loader, input [2:0] chan_model, input [63:0] expect_lo, input early = 0);
        logic [63:0] r;
        plm_status = st; plm_never_ack = never; decerr_all = decerr; obs_preset = busy; model_channel = chan_model; ack_early = early;
        sel = loader;
        ctrl_write(12'h020, 64'h0000_0100_0020_0000);  // PDI at PS 0x100_0020_0000
        ctrl_write(12'h000, 64'h1);                     // start
        wait (intr);
        ctrl_read(12'h010, r);                           // result register (tapasco_ctrl_slave layout)
        if (r[31:0] !== expect_lo[31:0]) begin
            $error("%s: result[31:0]=%h expected %h", name, r[31:0], expect_lo[31:0]); errors++;
        end else if (expect_lo[31:0] != 0 && expect_lo[31:8] != 24'hFFFFFF && r[63:32] !== plm_loader_status) begin
            $error("%s: result[63:32]=%h expected the XilLoader status %h", name, r[63:32], plm_loader_status); errors++;
        end else $display("%s: OK result=%h (hi = %0d: cycles, or loader status on PLM error)", name, r, r[63:32]);
        if (finish_valid) begin $error("%s: finish still pending after the PE took it", name); errors++; end
        if (!start_ready) begin $error("%s: loader not ready for the next request", name); errors++; end
        ctrl_write(12'h000, 64'h0);                     // tlkm-style interrupt clear write, harmless
        repeat (20) @(posedge aclk);
    endtask

    initial begin
        s_awvalid = 0; s_wvalid = 0; s_bready = 0; s_arvalid = 0; s_rready = 0;
        repeat (5) @(posedge aclk); aresetn = 1; repeat (5) @(posedge aclk);
        run_case("happy",      32'h0,    0, 0, 0, 0, 5, 64'h0);
        plm_loader_status = 32'h00000042;
        run_case("plm_err",    32'h1234, 0, 0, 0, 0, 5, 64'h1234);
        run_case("decerr",     32'h0,    0, 1, 0, 0, 5, 64'hFFFFFF01);
        run_case("busy",       32'h0,    0, 0, 1, 0, 5, 64'hFFFFFF05);
        run_case("ipi2",       32'h0,    0, 0, 0, 1, 2, 64'h0);         // IPI_CHANNEL 2 reaches IPI2's regs/buffers
        run_case("ipi0_vs_3",  32'h0,    0, 0, 0, 2, 3, 64'hFFFFFF02);  // wrong block: IPI0's OBS unmapped -> read DECERR
        run_case("ack_early",  32'h0,    0, 0, 0, 1, 2, 64'h0,       1);  // OBS cleared before the response is written: loader must wait
        run_case("ack_early_err", 32'h1234, 0, 0, 0, 1, 2, 64'h1234,  1);
        run_case("timeout",    32'h0,    1, 0, 0, 1, 2, 64'hFFFFFF03);  // PLM never acks: error 3 after TIMEOUT_CYCLES
        run_case("stale",      32'h0,    0, 0, 0, 1, 2, 64'hFFFFFF05);  // the unacknowledged request still sits in OBS: busy
        plm.obs_pmc = 0;                                               // the PLM got to it after all
        run_case("after_timeout", 32'h0, 0, 0, 0, 1, 2, 64'h0);         // the loader recovered without a reset
        if (errors == 0) $display("ALL OK"); else $display("FAILED: %0d errors", errors);
        $finish;
    end
endmodule
