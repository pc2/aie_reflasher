// Testbench: DataStreamerVN with a behavioural AIE (z = scale * sqrt(x^2 + y^2) per 128-bit
// beat pair), a DMA source and a DMA sink, all with random stalls. Drives the Tapasco control
// slave like tlkm does (SAMPLES at 0x20, CTRL bit 0, wait for intr, read 0x10).
`timescale 1ns/1ps
module DataStreamerVN_tb;
    logic aclk = 0; always #2 aclk = !aclk;   // 250 MHz
    logic aresetn = 0;

    // control slave
    logic [11:0] s_awaddr; logic s_awvalid; logic s_awready;
    logic [63:0] s_wdata; logic [7:0] s_wstrb; logic s_wvalid; logic s_wready;
    logic [1:0] s_bresp; logic s_bvalid; logic s_bready;
    logic [11:0] s_araddr; logic s_arvalid; logic s_arready;
    logic [63:0] s_rdata; logic [1:0] s_rresp; logic s_rvalid; logic s_rready;
    logic intr;
    // streams
    logic sdma_tready, sdma_tvalid, sdma_tlast; logic [511:0] sdma_tdata; logic [63:0] sdma_tkeep;
    logic x_tready, x_tvalid, x_tlast; logic [127:0] x_tdata;
    logic y_tready, y_tvalid, y_tlast; logic [127:0] y_tdata;
    logic z_tready, z_tvalid, z_tlast; logic [127:0] z_tdata;
    logic mdma_tready, mdma_tvalid, mdma_tlast; logic [511:0] mdma_tdata; logic [63:0] mdma_tkeep;

    DataStreamerVN dut(
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_control_awaddr(s_awaddr), .s_axi_control_awvalid(s_awvalid), .s_axi_control_awready(s_awready),
        .s_axi_control_wdata(s_wdata), .s_axi_control_wstrb(s_wstrb), .s_axi_control_wvalid(s_wvalid), .s_axi_control_wready(s_wready),
        .s_axi_control_bresp(s_bresp), .s_axi_control_bvalid(s_bvalid), .s_axi_control_bready(s_bready),
        .s_axi_control_araddr(s_araddr), .s_axi_control_arvalid(s_arvalid), .s_axi_control_arready(s_arready),
        .s_axi_control_rdata(s_rdata), .s_axi_control_rresp(s_rresp), .s_axi_control_rvalid(s_rvalid), .s_axi_control_rready(s_rready),
        .intr(intr),
        .S_AXIS_DMA_tready(sdma_tready), .S_AXIS_DMA_tvalid(sdma_tvalid), .S_AXIS_DMA_tdata(sdma_tdata),
        .S_AXIS_DMA_tkeep(sdma_tkeep), .S_AXIS_DMA_tlast(sdma_tlast),
        .M_AXIS_AIE_X_tready(x_tready), .M_AXIS_AIE_X_tvalid(x_tvalid), .M_AXIS_AIE_X_tdata(x_tdata), .M_AXIS_AIE_X_tlast(x_tlast),
        .M_AXIS_AIE_Y_tready(y_tready), .M_AXIS_AIE_Y_tvalid(y_tvalid), .M_AXIS_AIE_Y_tdata(y_tdata), .M_AXIS_AIE_Y_tlast(y_tlast),
        .S_AXIS_AIE_tready(z_tready), .S_AXIS_AIE_tvalid(z_tvalid), .S_AXIS_AIE_tdata(z_tdata), .S_AXIS_AIE_tlast(z_tlast),
        .M_AXIS_DMA_tready(mdma_tready), .M_AXIS_DMA_tvalid(mdma_tvalid), .M_AXIS_DMA_tdata(mdma_tdata),
        .M_AXIS_DMA_tkeep(mdma_tkeep), .M_AXIS_DMA_tlast(mdma_tlast)
    );

    // ------------------------------------------------------------------ knobs
    bit debug = 0;
    int stall_pct = 0;          // probability (%) of a stall on every stream handshake
    real aie_scale = 1.0;       // 2.0 models the libadf_b graph

    function logic stall(); return ($urandom_range(99) < stall_pct); endfunction

    // IEEE-754 binary32 <-> real by hand: Verilator's $shortrealtobits/$bitstoshortreal do
    // not work on real arguments (shortreal is promoted to real).
    function logic [31:0] f2b(input real v);
        logic [31:0] b; int e; real m; logic sgn;
        if (v == 0.0) return 32'h0;
        sgn = v < 0.0; if (sgn) v = -v;
        e = 0;
        while (v >= 2.0) begin v = v / 2.0; e++; end
        while (v < 1.0)  begin v = v * 2.0; e--; end
        m = (v - 1.0) * 8388608.0;                 // 2^23
        b = {sgn, 8'(e + 127), 23'($rtoi(m + 0.5))};
        return b;
    endfunction
    function real b2f(input logic [31:0] b);
        real v; int e;
        e = int'(b[30:23]) - 127;
        v = (1.0 + real'(b[22:0]) / 8388608.0) * (2.0 ** e);
        if (b[30:23] == 0) v = 0.0;
        return b[31] ? -v : v;
    endfunction

    // ------------------------------------------------------------------ behavioural AIE
    // x and y beats are queued independently (the real shim ports apply backpressure
    // independently too); a z beat is produced whenever both queues hold a beat. All stream
    // signals are driven from clocked logic (Verilator does not re-evaluate always_comb on
    // queue changes).
    logic [127:0] xq[$], yq[$], zq[$];
    logic [127:0] xb, yb, zb; real xr, yr;
    initial begin z_tvalid = 0; z_tdata = 0; z_tlast = 0; x_tready = 0; y_tready = 0; end
    always @(posedge aclk) begin
        x_tready <= !stall();
        y_tready <= !stall();
        if (x_tvalid && x_tready) begin xq.push_back(x_tdata); if (debug) $display("X  %h", x_tdata); end
        if (y_tvalid && y_tready) begin yq.push_back(y_tdata); if (debug) $display("Y  %h", y_tdata); end
        if (xq.size() > 0 && yq.size() > 0) begin
            xb = xq.pop_front(); yb = yq.pop_front();
            for (int j = 0; j < 4; j++) begin
                xr = b2f(xb[j*32 +: 32]);
                yr = b2f(yb[j*32 +: 32]);
                zb[j*32 +: 32] = f2b(aie_scale * $sqrt(xr*xr + yr*yr));
            end
            zq.push_back(zb); if (debug) $display("Z  %h", zb);
        end
        if (!z_tvalid || z_tready) begin           // output register free
            if (zq.size() > 0 && !stall()) begin z_tvalid <= 1; z_tdata <= zq.pop_front(); end
            else z_tvalid <= 0;
        end
    end

    // ------------------------------------------------------------------ DMA sink
    logic [511:0] out_beats[$]; int last_seen = 0;
    always @(posedge aclk) begin
        mdma_tready <= !stall();
        if (mdma_tvalid && mdma_tready) begin
            out_beats.push_back(mdma_tdata); if (debug) $display("OUT %h last=%b", mdma_tdata, mdma_tlast);
            if (mdma_tlast) last_seen++;
            if (mdma_tkeep !== 64'hFFFF_FFFF_FFFF_FFFF) $display("ERROR tkeep not all ones");
        end
    end

    // ------------------------------------------------------------------ control helpers
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

    // ------------------------------------------------------------------ DMA source
    logic [511:0] in_q[$];
    initial begin sdma_tvalid = 0; sdma_tdata = 0; sdma_tkeep = '1; sdma_tlast = 0; end
    always @(posedge aclk) begin
        if (!sdma_tvalid || sdma_tready) begin
            if (in_q.size() > 0 && !stall()) begin
                sdma_tdata <= in_q.pop_front(); sdma_tvalid <= 1; sdma_tlast <= (in_q.size() == 0);
            end else sdma_tvalid <= 0;
        end
    end
    task queue_input(input int n);
        logic [511:0] beat; int i;
        for (int b = 0; b < n / 8; b++) begin           // 8 (x, y) pairs per 512-bit beat
            for (int w = 0; w < 16; w++) begin
                i = b * 8 + w / 2;                           // sample index of this word
                beat[w*32 +: 32] = (w % 2 == 0) ? f2b(real'(i)) : f2b(real'(n - i));
            end
            in_q.push_back(beat); if (debug) $display("IN %h", beat);
        end
    endtask

    task run_case(input string name, input int n, input int stalls, input real scale);
        logic [63:0] r; int errors;
        errors = 0; stall_pct = stalls; aie_scale = scale; out_beats.delete(); last_seen = 0;
        ctrl_write(12'h020, 64'(n));
        ctrl_write(12'h000, 64'h1);
        queue_input(n);
        wait (intr);
        ctrl_read(12'h010, r);
        if (out_beats.size() != n / 16) begin $display("ERROR %s: got %0d beats, expected %0d", name, out_beats.size(), n / 16); errors++; end
        else begin
            real x, y, ref_z, got;
            for (int i = 0; i < n; i++) begin
                x = real'(i); y = real'(n - i); ref_z = scale * $sqrt(x*x + y*y);
                got = b2f(out_beats[i / 16][(i % 16) * 32 +: 32]);
                if (got < ref_z * 0.99999 || got > ref_z * 1.00001) begin
                    if (errors < 5) $display("ERROR %s: sample %0d: got %f expected %f", name, i, got, ref_z);
                    errors++;
                end
            end
        end
        if (last_seen != 1) begin $display("ERROR %s: tlast seen %0d times", name, last_seen); errors++; end
        if (errors == 0) $display("%s: OK %0d samples, %0d cycles (stall %0d%%, scale %0.1f)", name, n, r[31:0], stalls, scale);
        ctrl_write(12'h000, 64'h0);
        repeat (20) @(posedge aclk);
    endtask

    int n_sdma = 0, n_x = 0, n_y = 0, n_z = 0, n_mdma = 0;
    always @(posedge aclk) begin
        if (sdma_tvalid && sdma_tready) n_sdma++;
        if (x_tvalid && x_tready) n_x++;
        if (y_tvalid && y_tready) n_y++;
        if (z_tvalid && z_tready) n_z++;
        if (mdma_tvalid && mdma_tready) n_mdma++;
    end
    task show(input string tag);
        $display("%s: sdma=%0d x=%0d y=%0d z=%0d mdma=%0d | sdma_tready=%b x_tvalid=%b z_tvalid=%b z_tready=%b mdma_tvalid=%b in_q=%0d zq=%0d",
                 tag, n_sdma, n_x, n_y, n_z, n_mdma, sdma_tready, x_tvalid, z_tvalid, z_tready, mdma_tvalid, in_q.size(), zq.size());
    endtask
    initial begin #2ms; show("watchdog"); $display("ERROR watchdog timeout"); $finish; end

    initial begin
        s_awvalid = 0; s_wvalid = 0; s_bready = 0; s_arvalid = 0; s_rready = 0;
        repeat (5) @(posedge aclk); aresetn = 1; repeat (5) @(posedge aclk);
        run_case("single_beat", 16,   0,  1.0);   // set debug = 1 above to print every beat
        run_case("no_stall",    1024, 0,  1.0);
        run_case("stalls",      1024, 40, 1.0);
        run_case("scale2",      2048, 25, 2.0);
        run_case("back_to_back", 512, 0,  1.0);
        $finish;
    end
endmodule
