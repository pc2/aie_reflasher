// Testbench for module AIEngineReflasher #()
module AIEngineReflasher_tb;
    // Clocks
    logic aclk = 0;
    initial #5 forever #5 aclk = !aclk;

    // Ports
    // {aclk} input bool #() aresetn'1000
    logic aresetn;
    // {aclk} input int #(FROM: 0, TO: 4096) s_axi_control_awaddr'1000
    logic[11:0] s_axi_control_awaddr;
    // {aclk} input bool #() s_axi_control_awvalid'1000
    logic s_axi_control_awvalid;
    // {aclk} output bool #() s_axi_control_awready'1000
    wire s_axi_control_awready;
    // {aclk} input bool #()[32] s_axi_control_wdata'1000
    logic[63:0] s_axi_control_wdata;
    // {aclk} input bool #()[4] s_axi_control_wstrb'1000
    logic[7:0] s_axi_control_wstrb;
    // {aclk} input bool #() s_axi_control_wvalid'1000
    logic s_axi_control_wvalid;
    // {aclk} output bool #() s_axi_control_wready'1000
    wire s_axi_control_wready;
    // {aclk} output bool #()[2] s_axi_control_bresp'1000
    wire[1:0] s_axi_control_bresp;
    // {aclk} output bool #() s_axi_control_bvalid'1000
    wire s_axi_control_bvalid;
    // {aclk} input bool #() s_axi_control_bready'1000
    logic s_axi_control_bready;
    // {aclk} input int #(FROM: 0, TO: 4096) s_axi_control_araddr'1000
    logic[11:0] s_axi_control_araddr;
    // {aclk} input bool #() s_axi_control_arvalid'1000
    logic s_axi_control_arvalid;
    // {aclk} output bool #() s_axi_control_arready'1000
    wire s_axi_control_arready;
    // {aclk} output bool #()[32] s_axi_control_rdata'1000
    wire[63:0] s_axi_control_rdata;
    // {aclk} output bool #()[2] s_axi_control_rresp'1000
    wire[1:0] s_axi_control_rresp;
    // {aclk} output bool #() s_axi_control_rvalid'1000
    wire s_axi_control_rvalid;
    // {aclk} input bool #() s_axi_control_rready'1000
    logic s_axi_control_rready;
    // {aclk} output bool #() intr'1000
    wire intr;
    // {aclk} output int #(FROM: 0, TO: 18446744073709551616) small_axil_awaddr'0
    wire[63:0] small_axil_awaddr;
    // {aclk} output bool #() small_axil_awvalid'0
    wire small_axil_awvalid;
    // {aclk} input bool #() small_axil_awready'0
    logic small_axil_awready;
    // {aclk} output bool #()[32] small_axil_wdata'0
    wire[31:0] small_axil_wdata;
    // {aclk} output bool #()[4] small_axil_wstrb'0
    wire[3:0] small_axil_wstrb;
    // {aclk} output bool #() small_axil_wvalid'0
    wire small_axil_wvalid;
    // {aclk} input bool #() small_axil_wready'0
    logic small_axil_wready;
    // {aclk} input bool #()[2] small_axil_bresp'0
    logic[1:0] small_axil_bresp;
    // {aclk} input bool #() small_axil_bvalid'0
    logic small_axil_bvalid;
    // {aclk} output bool #() small_axil_bready'0
    wire small_axil_bready;
    // {aclk} output int #(FROM: 0, TO: 18446744073709551616) small_axil_araddr'0
    wire[63:0] small_axil_araddr;
    // {aclk} output bool #() small_axil_arvalid'0
    wire small_axil_arvalid;
    // {aclk} input bool #() small_axil_arready'0
    logic small_axil_arready;
    // {aclk} input bool #()[32] small_axil_rdata'0
    logic[31:0] small_axil_rdata;
    // {aclk} input bool #()[2] small_axil_rresp'0
    logic[1:0] small_axil_rresp;
    // {aclk} input bool #() small_axil_rvalid'0
    logic small_axil_rvalid;
    // {aclk} output bool #() small_axil_rready'0
    wire small_axil_rready;
    // {aclk} output bool #() bulk_axi_awvalid'0
    wire bulk_axi_awvalid;
    // {aclk} input bool #() bulk_axi_awready'0
    logic bulk_axi_awready;
    // {aclk} output int #(FROM: 0, TO: 18446744073709551616) bulk_axi_awaddr'0
    wire[63:0] bulk_axi_awaddr;
    // {aclk} output int #(FROM: 0, TO: 256) bulk_axi_awlen'0
    wire[7:0] bulk_axi_awlen;
    // {aclk} output int #(FROM: 0, TO: 8) bulk_axi_awsize'0
    wire[2:0] bulk_axi_awsize;
    // {aclk} output bool #()[2] bulk_axi_awburst'0
    wire[1:0] bulk_axi_awburst;
    // {aclk} output bool #()[3] bulk_axi_awprot'0
    wire[2:0] bulk_axi_awprot;
    // {aclk} output bool #()[4] bulk_axi_awcache'0
    wire[3:0] bulk_axi_awcache;
    // {aclk} output int #(FROM: 0, TO: 16) bulk_axi_awqos'0
    wire[3:0] bulk_axi_awqos;
    // {aclk} output bool #() bulk_axi_awlock'0
    wire bulk_axi_awlock;
    // {aclk} output int #(FROM: 0, TO: 16) bulk_axi_awregion'0
    wire[3:0] bulk_axi_awregion;
    // {aclk} output bool #() bulk_axi_wvalid'0
    wire bulk_axi_wvalid;
    // {aclk} input bool #() bulk_axi_wready'0
    logic bulk_axi_wready;
    // {aclk} output bool #()[32] bulk_axi_wdata'0
    wire[31:0] bulk_axi_wdata;
    // {aclk} output bool #()[4] bulk_axi_wstrb'0
    wire[3:0] bulk_axi_wstrb;
    // {aclk} output bool #() bulk_axi_wlast'0
    wire bulk_axi_wlast;
    // {aclk} input bool #() bulk_axi_bvalid'0
    logic bulk_axi_bvalid;
    // {aclk} output bool #() bulk_axi_bready'0
    wire bulk_axi_bready;
    // {aclk} input bool #()[2] bulk_axi_bresp'0
    logic[1:0] bulk_axi_bresp;
    // {aclk} output bool #() bulk_axi_arvalid'0
    wire bulk_axi_arvalid;
    // {aclk} input bool #() bulk_axi_arready'0
    logic bulk_axi_arready;
    // {aclk} output int #(FROM: 0, TO: 18446744073709551616) bulk_axi_araddr'0
    wire[63:0] bulk_axi_araddr;
    // {aclk} output int #(FROM: 0, TO: 256) bulk_axi_arlen'0
    wire[7:0] bulk_axi_arlen;
    // {aclk} output int #(FROM: 0, TO: 8) bulk_axi_arsize'0
    wire[2:0] bulk_axi_arsize;
    // {aclk} output bool #()[2] bulk_axi_arburst'0
    wire[1:0] bulk_axi_arburst;
    // {aclk} output bool #()[3] bulk_axi_arprot'0
    wire[2:0] bulk_axi_arprot;
    // {aclk} output bool #()[4] bulk_axi_arcache'0
    wire[3:0] bulk_axi_arcache;
    // {aclk} output int #(FROM: 0, TO: 16) bulk_axi_arqos'0
    wire[3:0] bulk_axi_arqos;
    // {aclk} output bool #() bulk_axi_arlock'0
    wire bulk_axi_arlock;
    // {aclk} output int #(FROM: 0, TO: 16) bulk_axi_arregion'0
    wire[3:0] bulk_axi_arregion;
    // {aclk} input bool #() bulk_axi_rvalid'0
    logic bulk_axi_rvalid;
    // {aclk} output bool #() bulk_axi_rready'0
    wire bulk_axi_rready;
    // {aclk} input bool #()[32] bulk_axi_rdata'0
    logic[31:0] bulk_axi_rdata;
    // {aclk} input bool #()[2] bulk_axi_rresp'0
    logic[1:0] bulk_axi_rresp;
    // {aclk} input bool #() bulk_axi_rlast'0
    logic bulk_axi_rlast;

    // DUT
    AIEngineReflasher dut(
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_control_awaddr(s_axi_control_awaddr),
        .s_axi_control_awvalid(s_axi_control_awvalid),
        .s_axi_control_awready(s_axi_control_awready),
        .s_axi_control_wdata(s_axi_control_wdata),
        .s_axi_control_wstrb(s_axi_control_wstrb),
        .s_axi_control_wvalid(s_axi_control_wvalid),
        .s_axi_control_wready(s_axi_control_wready),
        .s_axi_control_bresp(s_axi_control_bresp),
        .s_axi_control_bvalid(s_axi_control_bvalid),
        .s_axi_control_bready(s_axi_control_bready),
        .s_axi_control_araddr(s_axi_control_araddr),
        .s_axi_control_arvalid(s_axi_control_arvalid),
        .s_axi_control_arready(s_axi_control_arready),
        .s_axi_control_rdata(s_axi_control_rdata),
        .s_axi_control_rresp(s_axi_control_rresp),
        .s_axi_control_rvalid(s_axi_control_rvalid),
        .s_axi_control_rready(s_axi_control_rready),
        .intr(intr),
        .small_axil_awaddr(small_axil_awaddr),
        .small_axil_awvalid(small_axil_awvalid),
        .small_axil_awready(small_axil_awready),
        .small_axil_wdata(small_axil_wdata),
        .small_axil_wstrb(small_axil_wstrb),
        .small_axil_wvalid(small_axil_wvalid),
        .small_axil_wready(small_axil_wready),
        .small_axil_bresp(small_axil_bresp),
        .small_axil_bvalid(small_axil_bvalid),
        .small_axil_bready(small_axil_bready),
        .small_axil_araddr(small_axil_araddr),
        .small_axil_arvalid(small_axil_arvalid),
        .small_axil_arready(small_axil_arready),
        .small_axil_rdata(small_axil_rdata),
        .small_axil_rresp(small_axil_rresp),
        .small_axil_rvalid(small_axil_rvalid),
        .small_axil_rready(small_axil_rready),
        .bulk_axi_awvalid(bulk_axi_awvalid),
        .bulk_axi_awready(bulk_axi_awready),
        .bulk_axi_awaddr(bulk_axi_awaddr),
        .bulk_axi_awlen(bulk_axi_awlen),
        .bulk_axi_awsize(bulk_axi_awsize),
        .bulk_axi_awburst(bulk_axi_awburst),
        .bulk_axi_awprot(bulk_axi_awprot),
        .bulk_axi_awcache(bulk_axi_awcache),
        .bulk_axi_awqos(bulk_axi_awqos),
        .bulk_axi_awlock(bulk_axi_awlock),
        .bulk_axi_awregion(bulk_axi_awregion),
        .bulk_axi_wvalid(bulk_axi_wvalid),
        .bulk_axi_wready(bulk_axi_wready),
        .bulk_axi_wdata(bulk_axi_wdata),
        .bulk_axi_wstrb(bulk_axi_wstrb),
        .bulk_axi_wlast(bulk_axi_wlast),
        .bulk_axi_bvalid(bulk_axi_bvalid),
        .bulk_axi_bready(bulk_axi_bready),
        .bulk_axi_bresp(bulk_axi_bresp),
        .bulk_axi_arvalid(bulk_axi_arvalid),
        .bulk_axi_arready(bulk_axi_arready),
        .bulk_axi_araddr(bulk_axi_araddr),
        .bulk_axi_arlen(bulk_axi_arlen),
        .bulk_axi_arsize(bulk_axi_arsize),
        .bulk_axi_arburst(bulk_axi_arburst),
        .bulk_axi_arprot(bulk_axi_arprot),
        .bulk_axi_arcache(bulk_axi_arcache),
        .bulk_axi_arqos(bulk_axi_arqos),
        .bulk_axi_arlock(bulk_axi_arlock),
        .bulk_axi_arregion(bulk_axi_arregion),
        .bulk_axi_rvalid(bulk_axi_rvalid),
        .bulk_axi_rready(bulk_axi_rready),
        .bulk_axi_rdata(bulk_axi_rdata),
        .bulk_axi_rresp(bulk_axi_rresp),
        .bulk_axi_rlast(bulk_axi_rlast)
    );

    simple_axi4_mem#(
        .ADDR_WIDTH(64),
        .DATA_WIDTH(32),
        .DEPTH(64*1024)
    ) bulk_mem(
        .aclk(aclk),
        .aresetn(aresetn),
        .awvalid(bulk_axi_awvalid),
        .awready(bulk_axi_awready),
        .awaddr(bulk_axi_awaddr),
        .awlen(bulk_axi_awlen),
        .awsize(bulk_axi_awsize),
        .awburst(bulk_axi_awburst),
        .awprot(bulk_axi_awprot),
        .awcache(bulk_axi_awcache),
        .awqos(bulk_axi_awqos),
        .awlock(bulk_axi_awlock),
        .awregion(bulk_axi_awregion),
        .wvalid(bulk_axi_wvalid),
        .wready(bulk_axi_wready),
        .wdata(bulk_axi_wdata),
        .wstrb(bulk_axi_wstrb),
        .wlast(bulk_axi_wlast),
        .bvalid(bulk_axi_bvalid),
        .bready(bulk_axi_bready),
        .bresp(bulk_axi_bresp),
        .arvalid(bulk_axi_arvalid),
        .arready(bulk_axi_arready),
        .araddr(bulk_axi_araddr),
        .arlen(bulk_axi_arlen),
        .arsize(bulk_axi_arsize),
        .arburst(bulk_axi_arburst),
        .arprot(bulk_axi_arprot),
        .arcache(bulk_axi_arcache),
        .arqos(bulk_axi_arqos),
        .arlock(bulk_axi_arlock),
        .arregion(bulk_axi_arregion),
        .rvalid(bulk_axi_rvalid),
        .rready(bulk_axi_rready),
        .rdata(bulk_axi_rdata),
        .rresp(bulk_axi_rresp),
        .rlast(bulk_axi_rlast)
    );

    simple_axi4_mem#(
        .ADDR_WIDTH(64),
        .DATA_WIDTH(32),
        .DEPTH(1024)
    ) small_mem (
        .aclk(aclk),
        .aresetn(aresetn),
        .awaddr(small_axil_awaddr),
        .awburst(0),
        .awlen(0),
        .awvalid(small_axil_awvalid),
        .awready(small_axil_awready),
        .wdata(small_axil_wdata),
        .wstrb(small_axil_wstrb),
        .wvalid(small_axil_wvalid),
        .wready(small_axil_wready),
        .wlast(small_axil_wvalid),
        .bresp(small_axil_bresp),
        .bvalid(small_axil_bvalid),
        .bready(small_axil_bready),
        .araddr(small_axil_araddr),
        .arburst(0),
        .arlen(0),
        .arvalid(small_axil_arvalid),
        .arready(small_axil_arready),
        .rdata(small_axil_rdata),
        .rresp(small_axil_rresp),
        .rvalid(small_axil_rvalid),
        .rready(small_axil_rready)
    );

    
    initial begin
        s_axi_control_rready <= 0;
        s_axi_control_arvalid <= 0;
        s_axi_control_awvalid <= 0;
        s_axi_control_wvalid <= 0;
        s_axi_control_bready <= 0;
    end
    // Simple AXI write task
    task axi_write(input [11:0] addr, input [63:0] data);
        @(posedge aclk);

        s_axi_control_awaddr  <= addr;
        s_axi_control_awvalid <= 1;
        s_axi_control_wdata   <= data;
        s_axi_control_wstrb   <= -1;
        s_axi_control_wvalid  <= 1;
        s_axi_control_bready  <= 1;

        // Wait for AWREADY and WREADY handshake
        fork
            begin
                do @(posedge aclk); while(!s_axi_control_awready);
                s_axi_control_awvalid <= 0;
            end
            begin
                do @(posedge aclk); while(!s_axi_control_wready);
                s_axi_control_wvalid <= 0;
            end
            begin
                do @(posedge aclk); while(!s_axi_control_bvalid);
                s_axi_control_bready <= 0;
        
                $display("[%0t] Wrote 0x%08X to address 0x%03X. Error? 0b%02B", $time, data, addr, s_axi_control_bresp);
            end
        join
    endtask
    
    // Simple AXI read task
    task axi_read(input [11:0] addr, output [63:0] data_out);
        @(posedge aclk);

        s_axi_control_araddr  <= addr;
        s_axi_control_arvalid <= 1;
        s_axi_control_rready  <= 1;

        // Wait for ARREADY handshake
        fork
            begin
                do @(posedge aclk); while(!s_axi_control_arready);
                s_axi_control_arvalid <= 0;
            end
            begin
                do @(posedge aclk); while(!s_axi_control_rvalid);
                s_axi_control_rready <= 0;
                data_out = s_axi_control_rdata;
                $display("[%0t] Read  0x%08X from address 0x%03X Error? 0b%02B", $time, data_out, addr, s_axi_control_rresp);
            end
        join
    endtask

    logic [7:0] file_data [0:100000];
    task reflash_file(string file_name);
        automatic int file_id = $fopen(file_name, "rb");
        automatic int file_bytes = $fread(file_data, file_id);
        automatic int command_u32s = file_bytes / 4 - 5;
        for (int i = 0; i < file_bytes / 4; i++) begin
            bulk_mem.mem[i] =
                {file_data[4*i+3],
                 file_data[4*i+2],
                 file_data[4*i+1],
                 file_data[4*i+0]};
        end
        $display("File %d read of length %d\n [0] = %h\n [1] = %h\n [3] = %h\n [4] = %h",
            file_id, file_bytes,
            bulk_mem.mem[0], bulk_mem.mem[1], bulk_mem.mem[2], bulk_mem.mem[3]
        );
        $fclose(file_id);

        aresetn <= 0;

        repeat(20) @(posedge aclk);

        aresetn <= 1;

        repeat(20) @(posedge aclk);

        axi_write(12'h020, 20);
        axi_write(12'h030, command_u32s);

        // Flags for small and large AXI interface
        // Order is (from right to left)
        // - small_axil_awprot = 3'001 (Privileged, secure, data)
        // - small_axil_arprot = 3'001 (Privileged, secure, data)
        // - bulk_axi_awprot = 3'001 (Privileged, secure, data) (This is always AIE DMA write)
        // - bulk_axi_awburst = 1'b01 (Burst)
        // - bulk_axi_awcache = 4'b0011 (Bufferable, and can be broken up/recombined)
        // - bulk_axi_awlock = 1'b0 (No lock)
        // - bulk_axi_awqos = 4'b0000 (Lowest priority)
        // - bulk_axi_awregion = 4'b0000 (Region 0)
        // - bulk_axi_arprot = 3'000 (UnPrivileged, secure, data) (This is always DDR read)
        // - bulk_axi_arburst = 1'b01 (Burst)
        // - bulk_axi_arcache = 4'b0011 (Bufferable, and can be broken up/recombined)
        // - bulk_axi_arlock = 1'b0 (No lock)
        // - bulk_axi_arqos = 4'b0000 (Lowest priority)
        // - bulk_axi_arregion = 4'b0000 (Region 0)
        axi_write(12'h040, 64'h000310_000311_1_1);
        
        axi_write(12'h000, 1);

        wait(intr);

        repeat(20) @(posedge aclk);
    endtask
    
    initial begin
        $display("NOW FLASHING RESET FILE, (ONLY BASIC WRITE/MASK_WRITE/POLL)");
        reflash_file("/pc2/users/l/lennartv/eri-aie/tests/AIEngineReflasher/aie.cdo.reset.bin");

        $display("NOW FLASHING CLOCK GATING FILE");
        reflash_file("/pc2/users/l/lennartv/eri-aie/tests/AIEngineReflasher/aie.cdo.clock.gating.bin");

        $display("NOW FLASHING ERROR HANDLING FILE");
        reflash_file("/pc2/users/l/lennartv/eri-aie/tests/AIEngineReflasher/aie.cdo.error.handling.bin");

        $display("NOW FLASHING INIT FILE, (INCLUDES DMA)");
        reflash_file("/pc2/users/l/lennartv/eri-aie/tests/AIEngineReflasher/aie.cdo.init.bin");

        $display("NOW FLASHING ELFS FILE, (INCLUDES DMA)");
        reflash_file("/pc2/users/l/lennartv/eri-aie/tests/AIEngineReflasher/aie.cdo.elfs.bin");

        $display("NOW FLASHING ENABLE FILE");
        reflash_file("/pc2/users/l/lennartv/eri-aie/tests/AIEngineReflasher/aie.cdo.enable.bin");

        $finish();
    end

    localparam int READ_COMMAND_HEADER = 0;
    localparam int READING_LONG_FORM_LENGTH = 1;
    localparam int READ_ARGUMENTS = 2;
    localparam int EXECUTE_COMMAND = 3;
    localparam int DMA_WRITING = 4;
    localparam int DMA_FINISHING = 5;

    localparam int COMMAND_MASK_POLL = 1;
    localparam int COMMAND_MASK_WRITE = 2;
    localparam int COMMAND_WRITE = 3;
    localparam int COMMAND_DELAY = 4;
    localparam int COMMAND_DMA_WRITE = 5;
    localparam int COMMAND_MASK_POLL64 = 6;
    localparam int COMMAND_MASK_WRITE64 = 7;
    localparam int COMMAND_WRITE64 = 8;
    localparam int COMMAND_NOP = 17;
    logic[7:0] prev_state;
    always @(posedge aclk) begin
        if(dut.cur_state == EXECUTE_COMMAND && prev_state != EXECUTE_COMMAND) begin
            if(dut.cur_command == COMMAND_NOP) begin
                $display("[%0t] EXECUTE NOP", $time);
            end else if(dut.cur_command == COMMAND_MASK_POLL64) begin
                $display("[%0t] EXECUTE Mask Poll @ %h (Mask %h, Expected %h Timeout %h)", $time, dut.addr64, dut.argument_regs[2], dut.argument_regs[3], dut.argument_regs[4]);
            end else if(dut.cur_command == COMMAND_MASK_WRITE64) begin
                $display("[%0t] EXECUTE Mask Write @ %h (Mask %h, Data %h)", $time, dut.addr64, dut.argument_regs[2], dut.argument_regs[3]);
            end else if(dut.cur_command == COMMAND_WRITE64) begin
                $display("[%0t] EXECUTE Write @ %h (Data %h)", $time, dut.addr64, dut.argument_regs[2]);
            end else if(dut.cur_command == COMMAND_DMA_WRITE) begin
                $display("[%0t] EXECUTE DMA @ %h (Length %d)", $time, dut.addr64, dut.dma_payload_remaining);
            end else begin
                $fatal("[%0t] EXECUTE UNKNOWN COMMAND '%d'??? @ %h (%h, %h, %h)", $time, dut.cur_command, dut.addr64, dut.argument_regs[2], dut.argument_regs[3], dut.argument_regs[4]);
            end
        end
        prev_state <= dut.cur_state;
    end
endmodule // AIEngineReflasher_tb


module simple_axi4_mem #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 512,
    parameter DEPTH      = 1024
)(
    input  logic                     aclk,
    input  logic                     aresetn,

    // ============================================================
    // AXI WRITE ADDRESS CHANNEL
    // ============================================================

    input  logic                     awvalid,
    output logic                     awready,
    input  logic [ADDR_WIDTH-1:0]    awaddr,
    input  logic [7:0]               awlen,
    input  logic [2:0]               awsize,
    input  logic [1:0]               awburst,
    input  logic [3:0]               awregion,
    input  logic                     awlock,
    input  logic [3:0]               awqos,
    input  logic [3:0]               awcache,
    input  logic [2:0]               awprot,

    // ============================================================
    // AXI WRITE DATA CHANNEL
    // ============================================================

    input  logic                     wvalid,
    output logic                     wready,
    input  logic [DATA_WIDTH-1:0]    wdata,
    input  logic [DATA_WIDTH/8-1:0]  wstrb,
    input  logic                     wlast,

    // ============================================================
    // AXI WRITE RESPONSE CHANNEL
    // ============================================================

    output logic                     bvalid,
    input  logic                     bready,
    output logic [1:0]               bresp,

    // ============================================================
    // AXI READ ADDRESS CHANNEL
    // ============================================================

    input  logic                     arvalid,
    output logic                     arready,
    input  logic [ADDR_WIDTH-1:0]    araddr,
    input  logic [7:0]               arlen,
    input  logic [2:0]               arsize,
    input  logic [1:0]               arburst,
    input  logic [3:0]               arregion,
    input  logic                     arlock,
    input  logic [3:0]               arqos,
    input  logic [3:0]               arcache,
    input  logic [2:0]               arprot,

    // ============================================================
    // AXI READ DATA CHANNEL
    // ============================================================

    output logic                     rvalid,
    input  logic                     rready,
    output logic [DATA_WIDTH-1:0]    rdata,
    output logic [1:0]               rresp,
    output logic                     rlast
);

    // ============================================================
    // MEMORY
    // ============================================================

    logic [DATA_WIDTH:0] mem [0:DEPTH-1];

    // ============================================================
    // WRITE STATE
    // ============================================================

    logic [ADDR_WIDTH-1:0] wr_addr;
    integer                wr_beats_left;
    logic                  wr_active;

    // ============================================================
    // READ STATE
    // ============================================================

    logic [ADDR_WIDTH-1:0] rd_addr;
    integer                rd_beats_left;
    logic                  rd_active;

    // ============================================================
    // MAIN LOGIC
    // ============================================================

	assign arready = !rd_active & aresetn;
	assign awready = !wr_active & !bvalid & aresetn;

	logic nope = 1;
	// always_ff@(posedge aclk) nope <= !nope;
	assign rvalid = rd_active & nope & aresetn;
	assign wready = wr_active & nope & aresetn;

	always_comb begin
		if(rvalid) begin
			// build read data
			for (int i = 0; i < DATA_WIDTH / 8; i++) begin
				rdata[i*8 +: 8] = mem[rd_addr][i*8 +: 8];
			end

			rlast = rd_beats_left == 1;			
		end
	end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            bvalid  <= 1'b0;
            bresp   <= 2'b00;

            rresp   <= 2'b00;
            rlast   <= 1'b0;

            wr_active <= 1'b0;
            rd_active <= 1'b0;
        end else begin

            // ====================================================
            // WRITE ADDRESS HANDSHAKE
            // ====================================================

            if (awvalid && awready) begin
                wr_addr       = awaddr / (DATA_WIDTH / 8);
                wr_beats_left = awlen+1;
                wr_active     <= 1'b1;

                if(awburst == 1) // Some diagnostics only for large writes
                    $display("[%0t] Large Write @ %h len %d", $time, wr_addr * (DATA_WIDTH / 8), awlen + 1);

            end

            // ====================================================
            // WRITE DATA
            // ====================================================

            if (wvalid && wready) begin
                // byte-wise write
                for (int i = 0; i < DATA_WIDTH / 8; i++) begin
                    if (wstrb[i]) begin
                        mem[wr_addr][i*8 +: 8] <= wdata[i*8 +: 8];
                    end
                end

                if(awburst == 0) // Some diagnostics only for small writes
                    $display("[%0t] Write @ %h = %h", $time, wr_addr * (DATA_WIDTH / 8), wdata);

                // burst increment
                wr_addr <= wr_addr + 1;

				wr_beats_left--;

                if (wlast) begin

                    bvalid <= 1'b1;
                    bresp  <= 2'b00; // OKAY
					wr_active <= 1'b0;

					if(wr_beats_left != 0) begin
						$fatal("WR Beats Left Isn't 0 at the end of write transer???");
					end
                end else if(wr_beats_left == 0) begin
                    $fatal("WR Beats Left Is 0 but the write transfer hasn't ended???");
                end
            end

            // ====================================================
            // WRITE RESPONSE
            // ====================================================

            if (bvalid && bready) begin
                bvalid <= 1'b0;
            end

            // ====================================================
            // READ ADDRESS HANDSHAKE
            // ====================================================

            if (arvalid && arready) begin
                rd_addr       <= araddr / (DATA_WIDTH / 8);
                rd_beats_left <= arlen+1;
                rd_active     <= 1'b1;

                rvalid <= 1'b1;
                rresp  <= 2'b00;
            end

            // ====================================================
            // READ DATA CHANNEL
            // ====================================================

			if(rready && rvalid) begin
                if(arburst == 0) // Some diagnostics only for small reads
                    $display("[%0t] Read @ %h = %h", $time, rd_addr * (DATA_WIDTH / 8), rdata);

                // advance burst
                rd_addr <= rd_addr + 1;

                if (rlast) begin
                    rd_active <= 1'b0;
                end else begin
                    rd_beats_left <= rd_beats_left - 1;
                end
			end
        end
    end

endmodule

