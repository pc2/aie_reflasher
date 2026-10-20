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
    // ipi_lpd_interface AXI4-Full master
    logic [63:0] m_awaddr; logic [7:0] m_awlen; logic [2:0] m_awsize; logic [1:0] m_awburst; logic m_awlock;
    logic [3:0] m_awcache; logic [2:0] m_awprot; logic [3:0] m_awqos, m_awregion; logic m_awvalid, m_awready;
    logic [31:0] m_wdata; logic [3:0] m_wstrb; logic m_wlast, m_wvalid, m_wready;
    logic [1:0] m_bresp; logic m_bvalid, m_bready;
    logic [63:0] m_araddr; logic [7:0] m_arlen; logic [2:0] m_arsize; logic [1:0] m_arburst; logic m_arlock;
    logic [3:0] m_arcache; logic [2:0] m_arprot; logic [3:0] m_arqos, m_arregion; logic m_arvalid, m_arready;
    logic [31:0] m_rdata; logic [1:0] m_rresp; logic m_rlast, m_rvalid, m_rready;
    // knobs
    logic [31:0] plm_status = 0, plm_loader_status = 0; logic plm_never_ack = 0; logic decerr_all = 0; logic obs_preset = 0;
    logic [2:0] ipi_channel = 5;

    AIEPdiLoader dut(
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_control_awaddr(s_awaddr), .s_axi_control_awvalid(s_awvalid), .s_axi_control_awready(s_awready),
        .s_axi_control_wdata(s_wdata), .s_axi_control_wstrb(s_wstrb), .s_axi_control_wvalid(s_wvalid), .s_axi_control_wready(s_wready),
        .s_axi_control_bresp(s_bresp), .s_axi_control_bvalid(s_bvalid), .s_axi_control_bready(s_bready),
        .s_axi_control_araddr(s_araddr), .s_axi_control_arvalid(s_arvalid), .s_axi_control_arready(s_arready),
        .s_axi_control_rdata(s_rdata), .s_axi_control_rresp(s_rresp), .s_axi_control_rvalid(s_rvalid), .s_axi_control_rready(s_rready),
        .intr(intr),
        .ipi_lpd_interface_awaddr(m_awaddr), .ipi_lpd_interface_awlen(m_awlen), .ipi_lpd_interface_awsize(m_awsize),
        .ipi_lpd_interface_awburst(m_awburst), .ipi_lpd_interface_awlock(m_awlock), .ipi_lpd_interface_awcache(m_awcache),
        .ipi_lpd_interface_awprot(m_awprot), .ipi_lpd_interface_awqos(m_awqos), .ipi_lpd_interface_awregion(m_awregion),
        .ipi_lpd_interface_awvalid(m_awvalid), .ipi_lpd_interface_awready(m_awready),
        .ipi_lpd_interface_wdata(m_wdata), .ipi_lpd_interface_wstrb(m_wstrb), .ipi_lpd_interface_wlast(m_wlast),
        .ipi_lpd_interface_wvalid(m_wvalid), .ipi_lpd_interface_wready(m_wready),
        .ipi_lpd_interface_bresp(m_bresp), .ipi_lpd_interface_bvalid(m_bvalid), .ipi_lpd_interface_bready(m_bready),
        .ipi_lpd_interface_araddr(m_araddr), .ipi_lpd_interface_arlen(m_arlen), .ipi_lpd_interface_arsize(m_arsize),
        .ipi_lpd_interface_arburst(m_arburst), .ipi_lpd_interface_arlock(m_arlock), .ipi_lpd_interface_arcache(m_arcache),
        .ipi_lpd_interface_arprot(m_arprot), .ipi_lpd_interface_arqos(m_arqos), .ipi_lpd_interface_arregion(m_arregion),
        .ipi_lpd_interface_arvalid(m_arvalid), .ipi_lpd_interface_arready(m_arready),
        .ipi_lpd_interface_rdata(m_rdata), .ipi_lpd_interface_rresp(m_rresp), .ipi_lpd_interface_rlast(m_rlast),
        .ipi_lpd_interface_rvalid(m_rvalid), .ipi_lpd_interface_rready(m_rready)
    );

    fake_plm_axil #(.PLM_DELAY(200)) plm(
        .aclk(aclk), .aresetn(aresetn),
        .awaddr(m_awaddr), .awlen(m_awlen), .awsize(m_awsize), .awburst(m_awburst), .awvalid(m_awvalid), .awready(m_awready),
        .wdata(m_wdata), .wstrb(m_wstrb), .wlast(m_wlast), .wvalid(m_wvalid), .wready(m_wready),
        .bresp(m_bresp), .bvalid(m_bvalid), .bready(m_bready),
        .araddr(m_araddr), .arlen(m_arlen), .arsize(m_arsize), .arburst(m_arburst), .arvalid(m_arvalid), .arready(m_arready),
        .rdata(m_rdata), .rresp(m_rresp), .rlast(m_rlast), .rvalid(m_rvalid), .rready(m_rready),
        .plm_status(plm_status), .plm_loader_status(plm_loader_status), .plm_never_ack(plm_never_ack), .decerr_all(decerr_all), .obs_preset(obs_preset),
        .ipi_channel(ipi_channel)
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

    // chan_pe: channel field handed to the PE; chan_model: channel the fake IPI block implements
    task run_case(input string name, input [31:0] st, input never, input decerr, input busy, input [63:0] cmdw,
                  input [2:0] chan_pe, input [2:0] chan_model, input [63:0] expect_lo);
        logic [63:0] r;
        plm_status = st; plm_never_ack = never; decerr_all = decerr; obs_preset = busy; ipi_channel = chan_model;
        ctrl_write(12'h020, 64'h0000_0100_0020_0000);  // PDI at PS 0x100_0020_0000
        ctrl_write(12'h030, (cmdw << 32) | (64'(chan_pe) << 16)); // AxPROT = 0, channel [18:16], command override [63:32]
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
        run_case("happy",      32'h0,    0, 0, 0, 64'h0,      5, 5, 64'h0);
        run_case("plm_err",    32'h1234, 0, 0, 0, 64'h0,      5, 5, 64'h1234);
        run_case("decerr",     32'h0,    0, 1, 0, 64'h0,      5, 5, 64'hFFFFFF01);
        run_case("busy",       32'h0,    0, 0, 1, 64'h0,      5, 5, 64'hFFFFFF05);
        run_case("ping",       32'h0,    0, 0, 0, 64'h010100, 5, 5, 64'h0);
        run_case("ipi2",       32'h0,    0, 0, 0, 64'h0,      2, 2, 64'h0);         // channel select reaches IPI2's regs/buffers
        run_case("ipi0_vs_3",  32'h0,    0, 0, 0, 64'h0,      0, 3, 64'hFFFFFF02);  // wrong block: IPI0's OBS unmapped -> read DECERR
        run_case("bad_chan",   32'h0,    0, 0, 0, 64'h0,      7, 5, 64'hFFFFFF06);  // channel 7 rejected before touching the bus
        // timeout case needs a TB build with a small TIMEOUT_CYCLES (edit gen int in the .sus)
        $finish;
    end
endmodule
