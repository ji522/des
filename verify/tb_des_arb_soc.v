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

    // DES AXI-Lite
    reg         d_awvalid;
    wire        d_awready;
    reg  [31:0] d_awaddr;
    reg         d_wvalid;
    wire        d_wready;
    reg  [31:0] d_wdata;
    reg  [3:0]  d_wstrb;
    wire        d_bvalid;
    reg         d_bready;
    wire [1:0]  d_bresp;
    reg         d_arvalid;
    wire        d_arready;
    reg  [31:0] d_araddr;
    reg         d_rready;
    wire        d_rvalid;
    wire [31:0] d_rdata;
    wire [1:0]  d_rresp;

    // arbiter AXI-Lite
    reg         a_awvalid;
    wire        a_awready;
    reg  [31:0] a_awaddr;
    reg         a_wvalid;
    wire        a_wready;
    reg  [31:0] a_wdata;
    reg  [3:0]  a_wstrb;
    wire        a_bvalid;
    reg         a_bready;
    wire [1:0]  a_bresp;
    reg         a_arvalid;
    wire        a_arready;
    reg  [31:0] a_araddr;
    reg         a_rready;
    wire        a_rvalid;
    wire [31:0] a_rdata;
    wire [1:0]  a_rresp;

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

        .s_axil_des_awvalid   (d_awvalid),
        .s_axil_des_awready   (d_awready),
        .s_axil_des_awaddr    (d_awaddr),
        .s_axil_des_wvalid    (d_wvalid),
        .s_axil_des_wready    (d_wready),
        .s_axil_des_wdata     (d_wdata),
        .s_axil_des_wstrb     (d_wstrb),
        .s_axil_des_bvalid    (d_bvalid),
        .s_axil_des_bready    (d_bready),
        .s_axil_des_bresp     (d_bresp),
        .s_axil_des_arvalid   (d_arvalid),
        .s_axil_des_arready   (d_arready),
        .s_axil_des_araddr    (d_araddr),
        .s_axil_des_rready    (d_rready),
        .s_axil_des_rvalid    (d_rvalid),
        .s_axil_des_rdata     (d_rdata),
        .s_axil_des_rresp     (d_rresp),

        .s_axil_arb_awvalid   (a_awvalid),
        .s_axil_arb_awready   (a_awready),
        .s_axil_arb_awaddr    (a_awaddr),
        .s_axil_arb_wvalid    (a_wvalid),
        .s_axil_arb_wready    (a_wready),
        .s_axil_arb_wdata     (a_wdata),
        .s_axil_arb_wstrb     (a_wstrb),
        .s_axil_arb_bvalid    (a_bvalid),
        .s_axil_arb_bready    (a_bready),
        .s_axil_arb_bresp     (a_bresp),
        .s_axil_arb_arvalid   (a_arvalid),
        .s_axil_arb_arready   (a_arready),
        .s_axil_arb_araddr    (a_araddr),
        .s_axil_arb_rready    (a_rready),
        .s_axil_arb_rvalid    (a_rvalid),
        .s_axil_arb_rdata     (a_rdata),
        .s_axil_arb_rresp     (a_rresp),

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
    // AXI4-Lite helpers (DES / arbiter)
    // ------------------------------------------------------------------
    task des_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk);
            d_awvalid <= 1'b1; d_awaddr <= {24'h0, addr};
            d_wvalid  <= 1'b1; d_wdata  <= data; d_wstrb <= 4'hF;
            @(posedge clk);
            while (!(d_awready && d_wready)) @(posedge clk);
            d_awvalid <= 1'b0; d_wvalid <= 1'b0;
            while (!d_bvalid) @(posedge clk);
            d_bready <= 1'b1;
            @(posedge clk);
            d_bready <= 1'b0;
        end
    endtask

    task des_read;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk);
            d_arvalid <= 1'b1; d_araddr <= {24'h0, addr};
            @(posedge clk);
            while (!d_arready) @(posedge clk);
            d_arvalid <= 1'b0;
            while (!d_rvalid) @(posedge clk);
            data = d_rdata;
            d_rready <= 1'b1;
            @(posedge clk);
            d_rready <= 1'b0;
        end
    endtask

    task arb_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk);
            a_awvalid <= 1'b1; a_awaddr <= {24'h0, addr};
            a_wvalid  <= 1'b1; a_wdata  <= data; a_wstrb <= 4'hF;
            @(posedge clk);
            while (!(a_awready && a_wready)) @(posedge clk);
            a_awvalid <= 1'b0; a_wvalid <= 1'b0;
            while (!a_bvalid) @(posedge clk);
            a_bready <= 1'b1;
            @(posedge clk);
            a_bready <= 1'b0;
        end
    endtask

    task arb_read;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk);
            a_arvalid <= 1'b1; a_araddr <= {24'h0, addr};
            @(posedge clk);
            while (!a_arready) @(posedge clk);
            a_arvalid <= 1'b0;
            while (!a_rvalid) @(posedge clk);
            data = a_rdata;
            a_rready <= 1'b1;
            @(posedge clk);
            a_rready <= 1'b0;
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

        d_awvalid = 1'b0; d_awaddr = 32'h0;
        d_wvalid  = 1'b0; d_wdata  = 32'h0; d_wstrb = 4'h0;
        d_bready  = 1'b0;
        d_arvalid = 1'b0; d_araddr = 32'h0; d_rready = 1'b0;

        a_awvalid = 1'b0; a_awaddr = 32'h0;
        a_wvalid  = 1'b0; a_wdata  = 32'h0; a_wstrb = 4'h0;
        a_bready  = 1'b0;
        a_arvalid = 1'b0; a_araddr = 32'h0; a_rready = 1'b0;

        out_cnt = 0;
        err     = 0;

        $readmemh("keys.mem", keys);
        $readmemh("ins.mem",  ins);
        $readmemh("exps.mem", exps);

        #50 rst_n = 1'b1;
        #20;

        // DES: key + mode + enable
        des_write(8'h00, keys[0][31:0]);
        des_write(8'h04, keys[0][63:32]);
        wait (ready_key === 1'b1);
        des_write(8'h08, 32'h0000_0003);   // MODE=1 (encrypt), ENABLE=1

        // arbiter enable, round-robin
        arb_write(8'h00, 32'h0000_0001);
        arb_write(8'h0C, 32'h0000_0008);

        // ch0 packet = ins[0..3], ch1 packet = ins[4..7]
        send0(4, 0);
        send1(4, 4);

        wait (out_cnt == 8);
        #200;

        if (out_cnt !== 8) begin
            err = err + 1;
            $display("ERROR: out_cnt=%0d expected 8", out_cnt);
        end

        arb_read(8'h1C, rd);   // ch0 packets_out
        if (rd !== 32'd1) begin err = err + 1; $display("ERROR ch0 pkts_out=%0d", rd); end
        arb_read(8'h34, rd);   // ch1 packets_out
        if (rd !== 32'd1) begin err = err + 1; $display("ERROR ch1 pkts_out=%0d", rd); end
        arb_read(8'h18, rd);   // ch0 beats_out
        if (rd !== 32'd4) begin err = err + 1; $display("ERROR ch0 beats_out=%0d", rd); end
        arb_read(8'h30, rd);   // ch1 beats_out
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
