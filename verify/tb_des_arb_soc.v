`timescale 1ns / 1ps
// ============================================================================
// tb_des_arb_soc.v —— 2 通道仲裁 + DES 加密 SoC 集成自检
//
// 用 vectors/keys.mem / ins.mem / exps.mem：
//   - ch0 发 ins[0..3]（4 beat），ch1 发 ins[4..7]（4 beat）；
//   - 期望输出顺序 exps[0..7]，TLAST 在第 4/8 拍；
//   - 同时检查 arbiter 计数器 ch0/ch1 packets_out = 1。
// 通过标志：DES ARB SOC PASS
// ============================================================================
module tb_des_arb_soc;

    reg         clk;
    reg         rst_n;

    reg         s0_tvalid;
    wire        s0_tready;
    reg  [63:0] s0_tdata;
    reg         s0_tlast;

    reg         s1_tvalid;
    wire        s1_tready;
    reg  [63:0] s1_tdata;
    reg         s1_tlast;

    wire        m_tvalid;
    reg         m_tready;
    wire [63:0] m_tdata;
    wire        m_tlast;

    // AXI4-Lite（单控制端口）
    reg         axil_awvalid;
    wire        axil_awready;
    reg  [31:0] axil_awaddr;
    reg         axil_wvalid;
    wire        axil_wready;
    reg  [31:0] axil_wdata;
    reg  [3:0]  axil_wstrb;
    wire        axil_bvalid;
    reg         axil_bready;
    wire [1:0]  axil_bresp;
    reg         axil_arvalid;
    wire        axil_arready;
    reg  [31:0] axil_araddr;
    reg         axil_rready;
    wire        axil_rvalid;
    wire [31:0] axil_rdata;
    wire [1:0]  axil_rresp;

    wire        irq;
    wire        arb_busy;
    wire        ready_key;

    // vectors
    reg [63:0] keys  [0:31];
    reg [63:0] ins   [0:31];
    reg [63:0] exps  [0:31];

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    des_arb_soc_top dut (
        .clk                  (clk),
        .rst_n                (rst_n),

        .s0_axis_tvalid       (s0_tvalid),
        .s0_axis_tready       (s0_tready),
        .s0_axis_tdata        (s0_tdata),
        .s0_axis_tlast        (s0_tlast),

        .s1_axis_tvalid       (s1_tvalid),
        .s1_axis_tready       (s1_tready),
        .s1_axis_tdata        (s1_tdata),
        .s1_axis_tlast        (s1_tlast),

        .m_axis_tvalid        (m_tvalid),
        .m_axis_tready        (m_tready),
        .m_axis_tdata         (m_tdata),
        .m_axis_tlast         (m_tlast),

        .s_axil_awvalid       (axil_awvalid),
        .s_axil_awready       (axil_awready),
        .s_axil_awaddr        (axil_awaddr),
        .s_axil_wvalid        (axil_wvalid),
        .s_axil_wready        (axil_wready),
        .s_axil_wdata         (axil_wdata),
        .s_axil_wstrb         (axil_wstrb),
        .s_axil_bvalid        (axil_bvalid),
        .s_axil_bready        (axil_bready),
        .s_axil_bresp         (axil_bresp),
        .s_axil_arvalid       (axil_arvalid),
        .s_axil_arready       (axil_arready),
        .s_axil_araddr        (axil_araddr),
        .s_axil_rready        (axil_rready),
        .s_axil_rvalid        (axil_rvalid),
        .s_axil_rdata         (axil_rdata),
        .s_axil_rresp         (axil_rresp),

        .irq_o                (irq),
        .arb_busy_o           (arb_busy),
        .ready_key_o          (ready_key)
    );

    // ------------------------------------------------------------------
    // clock / reset
    // ------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // AXI4-Lite helpers（单端口；DES=0x0xx，arbiter=0x1xx）
    // ------------------------------------------------------------------
    task axil_write;
        input [15:0] addr;
        input [31:0] data;
        integer aw_done, w_done;
        begin
            @(posedge clk);
            axil_awvalid <= 1'b1; axil_awaddr <= {16'h0, addr};
            axil_wvalid  <= 1'b1; axil_wdata  <= data; axil_wstrb <= 4'hF;
            aw_done = 0;
            w_done  = 0;
            while (!(aw_done && w_done)) begin
                @(posedge clk);
                if (!aw_done && axil_awvalid && axil_awready) begin
                    axil_awvalid <= 1'b0;
                    aw_done = 1;
                end
                if (!w_done && axil_wvalid && axil_wready) begin
                    axil_wvalid <= 1'b0;
                    w_done = 1;
                end
            end
            while (!axil_bvalid) @(posedge clk);
            axil_bready <= 1'b1;
            @(posedge clk);
            axil_bready <= 1'b0;
        end
    endtask

    task axil_read;
        input  [15:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            axil_arvalid <= 1'b1; axil_araddr <= {16'h0, addr};
            @(posedge clk);
            while (!axil_arready) @(posedge clk);
            axil_arvalid <= 1'b0;
            while (!axil_rvalid) @(posedge clk);
            data = axil_rdata;
            axil_rready <= 1'b1;
            @(posedge clk);
            axil_rready <= 1'b0;
        end
    endtask

    // ------------------------------------------------------------------
    // channel drivers
    // ------------------------------------------------------------------
    task send0;
        input integer len;
        input integer base;
        integer k;
        begin
            for (k = 0; k < len; k = k + 1) begin
                @(posedge clk);
                s0_tvalid <= 1'b1;
                s0_tdata  <= ins[base + k];
                s0_tlast  <= (k == len-1);
                @(posedge clk);
                while (!s0_tready) @(posedge clk);
                s0_tvalid <= 1'b0;
                s0_tlast  <= 1'b0;
            end
            s0_tvalid <= 1'b0;
            s0_tlast  <= 1'b0;
        end
    endtask

    task send1;
        input integer len;
        input integer base;
        integer k;
        begin
            for (k = 0; k < len; k = k + 1) begin
                @(posedge clk);
                s1_tvalid <= 1'b1;
                s1_tdata  <= ins[base + k];
                s1_tlast  <= (k == len-1);
                @(posedge clk);
                while (!s1_tready) @(posedge clk);
                s1_tvalid <= 1'b0;
                s1_tlast  <= 1'b0;
            end
            s1_tvalid <= 1'b0;
            s1_tlast  <= 1'b0;
        end
    endtask

    // ------------------------------------------------------------------
    // output checker
    // ------------------------------------------------------------------
    integer out_cnt;
    integer err;

    always @(posedge clk) begin
        if (rst_n && m_tvalid && m_tready) begin
            if (out_cnt < 8) begin
                if (m_tdata !== exps[out_cnt]) begin
                    err = err + 1;
                    $display("[%0t] ERROR: out[%0d]=%h expected=%h",
                             $time, out_cnt, m_tdata, exps[out_cnt]);
                end
                if (m_tlast !== ((out_cnt == 3) || (out_cnt == 7))) begin
                    err = err + 1;
                    $display("[%0t] ERROR: out[%0d] tlast=%b", $time, out_cnt, m_tlast);
                end
            end else begin
                err = err + 1;
                $display("[%0t] ERROR: extra output beat %h", $time, m_tdata);
            end
            out_cnt = out_cnt + 1;
        end
    end

    // ------------------------------------------------------------------
    // main
    // ------------------------------------------------------------------
    integer i;
    reg [31:0] rd;

    initial begin
        rst_n = 1'b0;
        s0_tvalid = 1'b0; s0_tdata = 64'h0; s0_tlast = 1'b0;
        s1_tvalid = 1'b0; s1_tdata = 64'h0; s1_tlast = 1'b0;
        m_tready  = 1'b1;

        axil_awvalid = 1'b0; axil_awaddr = 32'h0;
        axil_wvalid  = 1'b0; axil_wdata  = 32'h0; axil_wstrb = 4'h0;
        axil_bready  = 1'b0;
        axil_arvalid = 1'b0; axil_araddr = 32'h0; axil_rready = 1'b0;

        out_cnt = 0;
        err     = 0;

        $readmemh("keys.mem", keys);
        $readmemh("ins.mem",  ins);
        $readmemh("exps.mem", exps);

        #50 rst_n = 1'b1;
        #20;

        // DES: key + mode + enable
        axil_write(16'h0000, keys[0][31:0]);
        axil_write(16'h0004, keys[0][63:32]);
        wait (ready_key === 1'b1);
        axil_write(16'h0008, 32'h0000_0003);   // MODE=1 (encrypt), ENABLE=1

        // arbiter: 0x100 起的地址
        axil_write(16'h0100, 32'h0000_0001);
        axil_write(16'h010C, 32'h0000_0008);

        // ch0 packet = ins[0..3], ch1 packet = ins[4..7]
        send0(4, 0);
        send1(4, 4);

        wait (out_cnt == 8);
        #200;

        if (out_cnt !== 8) begin
            err = err + 1;
            $display("ERROR: out_cnt=%0d expected 8", out_cnt);
        end

        axil_read(16'h011C, rd);   // ch0 packets_out
        if (rd !== 32'd1) begin err = err + 1; $display("ERROR ch0 pkts_out=%0d", rd); end
        axil_read(16'h0134, rd);   // ch1 packets_out
        if (rd !== 32'd1) begin err = err + 1; $display("ERROR ch1 pkts_out=%0d", rd); end
        axil_read(16'h0118, rd);   // ch0 beats_out
        if (rd !== 32'd4) begin err = err + 1; $display("ERROR ch0 beats_out=%0d", rd); end
        axil_read(16'h0130, rd);   // ch1 beats_out
        if (rd !== 32'd4) begin err = err + 1; $display("ERROR ch1 beats_out=%0d", rd); end

        #100;
        if (err == 0)
            $display("DES ARB SOC PASS : 8 beats, 2 packets, TLAST aligned");
        else
            $display("DES ARB SOC FAIL : err=%0d", err);
        $finish;
    end

    initial begin
        #200000;
        $display("DES ARB SOC FAIL : TIMEOUT");
        $finish;
    end

endmodule
