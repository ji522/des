`timescale 1ns / 1ps
// ============================================================================
// tb_axis_arb_corner.v —— 仲裁器 corner 用例（补覆盖率）
//
// 三个 phase：
//  1) 固定优先 ch0：包长 1/2/3 + 1/2/5，ch0 全部先出，再出 ch1；
//  2) round-robin + FIFO 压满：ch0 单包 20 beat，先不 ready，FIFO 满后
//     blocked 计数增加；释放后 20 beat 全出；
//  3) 单拍包：ch0 len1、ch1 len1，覆盖 lock 旁路路径。
//
// 通过标志：AXIS ARB CORNER PASS
// ============================================================================
module tb_axis_arb_corner;

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
    wire        m_tuser;

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

    wire        arb_enable;
    wire        arb_mode;
    wire [7:0]  af_thresh0, af_thresh1;
    wire        clear_counters;

    wire [4:0]  fifo0_count, fifo1_count;
    wire        fifo0_full, fifo1_full;
    wire        fifo0_af, fifo1_af;
    wire        ch0_done, ch1_done;
    wire        cur_ch, arb_lock, arb_busy;

    wire [31:0] ch0_beats_in, ch0_packets_in, ch0_beats_out, ch0_packets_out;
    wire [31:0] ch0_stall, ch0_blocked;
    wire [31:0] ch1_beats_in, ch1_packets_in, ch1_beats_out, ch1_packets_out;
    wire [31:0] ch1_stall, ch1_blocked;

    axis_arb2 #(.DATA_W(64), .FIFO_AW(4)) dut (
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
        .m_axis_tuser         (m_tuser),
        .enable               (arb_enable),
        .arb_mode             (arb_mode),
        .almost_full_thresh0  (af_thresh0),
        .almost_full_thresh1  (af_thresh1),
        .clear_counters       (clear_counters),
        .fifo0_count_o        (fifo0_count),
        .fifo1_count_o        (fifo1_count),
        .fifo0_full_o         (fifo0_full),
        .fifo1_full_o         (fifo1_full),
        .fifo0_almost_full_o  (fifo0_af),
        .fifo1_almost_full_o  (fifo1_af),
        .ch0_done_o           (ch0_done),
        .ch1_done_o           (ch1_done),
        .cur_ch_o             (cur_ch),
        .lock_o               (arb_lock),
        .busy_o               (arb_busy),
        .ch0_beats_in_o       (ch0_beats_in),
        .ch0_packets_in_o     (ch0_packets_in),
        .ch0_beats_out_o      (ch0_beats_out),
        .ch0_packets_out_o    (ch0_packets_out),
        .ch0_stall_o          (ch0_stall),
        .ch0_blocked_o        (ch0_blocked),
        .ch1_beats_in_o       (ch1_beats_in),
        .ch1_packets_in_o     (ch1_packets_in),
        .ch1_beats_out_o      (ch1_beats_out),
        .ch1_packets_out_o    (ch1_packets_out),
        .ch1_stall_o          (ch1_stall),
        .ch1_blocked_o        (ch1_blocked)
    );

    axis_arb_regs #(.FIFO_AW(4)) regs (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .s_axil_awvalid         (axil_awvalid),
        .s_axil_awready         (axil_awready),
        .s_axil_awaddr          (axil_awaddr),
        .s_axil_wvalid          (axil_wvalid),
        .s_axil_wready          (axil_wready),
        .s_axil_wdata           (axil_wdata),
        .s_axil_wstrb           (axil_wstrb),
        .s_axil_bvalid          (axil_bvalid),
        .s_axil_bready          (axil_bready),
        .s_axil_bresp           (axil_bresp),
        .s_axil_arvalid         (axil_arvalid),
        .s_axil_arready         (axil_arready),
        .s_axil_araddr          (axil_araddr),
        .s_axil_rready          (axil_rready),
        .s_axil_rvalid          (axil_rvalid),
        .s_axil_rdata           (axil_rdata),
        .s_axil_rresp           (axil_rresp),
        .enable_o               (arb_enable),
        .arb_mode_o             (arb_mode),
        .af_thresh0_o           (af_thresh0),
        .af_thresh1_o           (af_thresh1),
        .clear_counters_o       (clear_counters),
        .fifo0_count_i          (fifo0_count),
        .fifo1_count_i          (fifo1_count),
        .fifo0_full_i           (fifo0_full),
        .fifo1_full_i           (fifo1_full),
        .fifo0_almost_full_i    (fifo0_af),
        .fifo1_almost_full_i    (fifo1_af),
        .ch0_done_i             (ch0_done),
        .ch1_done_i             (ch1_done),
        .cur_ch_i               (cur_ch),
        .lock_i                 (arb_lock),
        .busy_i                 (arb_busy),
        .ch0_beats_in_i         (ch0_beats_in),
        .ch0_packets_in_i       (ch0_packets_in),
        .ch0_beats_out_i        (ch0_beats_out),
        .ch0_packets_out_i      (ch0_packets_out),
        .ch0_stall_i            (ch0_stall),
        .ch0_blocked_i          (ch0_blocked),
        .ch1_beats_in_i         (ch1_beats_in),
        .ch1_packets_in_i       (ch1_packets_in),
        .ch1_beats_out_i        (ch1_beats_out),
        .ch1_packets_out_i      (ch1_packets_out),
        .ch1_stall_i            (ch1_stall),
        .ch1_blocked_i          (ch1_blocked),
        .irq_o                  (irq)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg m_ready_en;
    assign m_tready = m_ready_en;

    // ------------------------------------------------------------------
    // AXI4-Lite helpers
    // ------------------------------------------------------------------
    task axil_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk);
            axil_awvalid <= 1'b1; axil_awaddr <= {24'h0, addr};
            axil_wvalid  <= 1'b1; axil_wdata  <= data; axil_wstrb <= 4'hF;
            @(posedge clk);
            while (!(axil_awready && axil_wready)) @(posedge clk);
            axil_awvalid <= 1'b0; axil_wvalid <= 1'b0;
            while (!axil_bvalid) @(posedge clk);
            axil_bready <= 1'b1;
            @(posedge clk);
            axil_bready <= 1'b0;
        end
    endtask

    task axil_read;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk);
            axil_arvalid <= 1'b1; axil_araddr <= {24'h0, addr};
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
        input integer pkt;
        integer k;
        begin
            for (k = 0; k < len; k = k + 1) begin
                @(posedge clk);
                s0_tvalid <= 1'b1;
                s0_tdata  <= {32'hA000_0000 | (pkt << 8) | k, 32'h0};
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
        input integer pkt;
        integer k;
        begin
            for (k = 0; k < len; k = k + 1) begin
                @(posedge clk);
                s1_tvalid <= 1'b1;
                s1_tdata  <= {32'hB000_0000 | (pkt << 8) | k, 32'h0};
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

    task do_reset;
        begin
            rst_n       = 1'b0;
            m_ready_en  = 1'b0;
            #40;
            rst_n       = 1'b1;
            #20;
        end
    endtask

    // 避免在 posedge 上直接用阻塞赋值改 m_ready_en，和 DUT/监视器抢同一个沿
    task release_output;
        begin
            @(negedge clk);
            m_ready_en = 1'b1;
        end
    endtask

    // ------------------------------------------------------------------
    // expected packets / checker
    // ------------------------------------------------------------------
    reg [2:0] exp_pkt;
    reg       exp_ch  [0:15];
    integer   exp_len [0:15];
    integer   exp_id  [0:15];
    integer   exp_total;
    integer   beat_in_pkt;
    integer   out_beats;
    integer   out_pkts;
    integer   err;

    reg [63:0] exp_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exp_pkt     <= 0;
            beat_in_pkt <= 0;
        end else if (m_tvalid && m_tready) begin
            if (exp_pkt >= exp_total) begin
                err = err + 1;
                $display("[%0t] ERROR: extra beat", $time);
            end else begin
                if (m_tuser !== exp_ch[exp_pkt]) begin
                    err = err + 1;
                    $display("[%0t] ERROR tuser=%b exp=%b", $time, m_tuser, exp_ch[exp_pkt]);
                end
                if (exp_ch[exp_pkt] == 1'b0)
                    exp_data = {32'hA000_0000 | (exp_id[exp_pkt] << 8) | beat_in_pkt, 32'h0};
                else
                    exp_data = {32'hB000_0000 | (exp_id[exp_pkt] << 8) | beat_in_pkt, 32'h0};
                if (m_tdata !== exp_data) begin
                    err = err + 1;
                    $display("[%0t] ERROR data=%h exp=%h", $time, m_tdata, exp_data);
                end
                if (m_tlast !== (beat_in_pkt == exp_len[exp_pkt]-1)) begin
                    err = err + 1;
                    $display("[%0t] ERROR tlast=%b pkt=%0d beat=%0d", $time, m_tlast, exp_pkt, beat_in_pkt);
                end

                out_beats   = out_beats + 1;
                beat_in_pkt = beat_in_pkt + 1;
                if (m_tlast) begin
                    out_pkts    = out_pkts + 1;
                    exp_pkt     = exp_pkt + 1;
                    beat_in_pkt = 0;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // main
    // ------------------------------------------------------------------
    reg [31:0] rd;
    integer i;

    initial begin
        rst_n       = 1'b0;
        s0_tvalid   = 1'b0; s0_tdata = 64'h0; s0_tlast = 1'b0;
        s1_tvalid   = 1'b0; s1_tdata = 64'h0; s1_tlast = 1'b0;
        m_ready_en  = 1'b0;
        axil_awvalid= 1'b0; axil_awaddr= 32'h0;
        axil_wvalid = 1'b0; axil_wdata = 32'h0; axil_wstrb = 4'h0;
        axil_bready = 1'b0;
        axil_arvalid= 1'b0; axil_araddr= 32'h0; axil_rready = 1'b0;

        exp_total   = 0;
        out_beats   = 0;
        out_pkts    = 0;
        err         = 0;
        for (i = 0; i < 16; i = i + 1) begin
            exp_ch[i] = 0; exp_len[i] = 1; exp_id[i] = 0;
        end

        // ---------------- phase 1: fixed priority ----------------
        do_reset();
        axil_write(8'h00, 32'h0000_0003);   // enable + fixed ch0
        axil_write(8'h0C, 32'h0000_0008);

        exp_total = 6;
        exp_ch[0]=0; exp_len[0]=1; exp_id[0]=0;
        exp_ch[1]=0; exp_len[1]=2; exp_id[1]=1;
        exp_ch[2]=0; exp_len[2]=5; exp_id[2]=2;
        exp_ch[3]=1; exp_len[3]=1; exp_id[3]=0;
        exp_ch[4]=1; exp_len[4]=2; exp_id[4]=1;
        exp_ch[5]=1; exp_len[5]=5; exp_id[5]=2;

        send0(1,0); send0(2,1); send0(5,2);
        send1(1,0); send1(2,1); send1(5,2);
        release_output();
        wait (exp_pkt == 6);
        #200;

        // ---------------- phase 2: FIFO full / blocked ----------------
        do_reset();
        axil_write(8'h00, 32'h0000_0001);   // enable + RR
        axil_write(8'h0C, 32'h0000_0004);

        exp_total = 1;
        exp_ch[0]=0; exp_len[0]=20; exp_id[0]=0;

        fork
            send0(20,0);
            begin #600; release_output(); end
        join
        wait (exp_pkt == 1);
        #300;

        axil_read(8'h24, rd);   // ch0 blocked
        if (rd == 0) begin err = err + 1; $display("ERROR: ch0 blocked=0"); end

        // ---------------- phase 2b: ch1 FIFO full ----------------
        do_reset();
        axil_write(8'h00, 32'h0000_0001);   // enable + RR
        axil_write(8'h0C, 32'h0000_0004);

        exp_total = 1;
        exp_ch[0]=1; exp_len[0]=20; exp_id[0]=0;

        fork
            send1(20,0);
            begin #600; release_output(); end
        join
        wait (exp_pkt == 1);
        #300;

        axil_read(8'h38, rd);   // ch1 blocked
        if (rd == 0) begin err = err + 1; $display("ERROR: ch1 blocked=0"); end

        // ---------------- phase 3: single-beat packets ----------------
        do_reset();
        axil_write(8'h00, 32'h0000_0001);   // enable + RR

        exp_total = 2;
        exp_ch[0]=0; exp_len[0]=1; exp_id[0]=0;
        exp_ch[1]=1; exp_len[1]=1; exp_id[1]=0;

        send0(1,0);
        send1(1,0);
        release_output();
        wait (exp_pkt == 2);
        #200;

        // ---------------- report ----------------
        if (err == 0)
            $display("AXIS ARB CORNER PASS : beats=%0d packets=%0d", out_beats, out_pkts);
        else
            $display("AXIS ARB CORNER FAIL : err=%0d", err);
        $finish;
    end

    initial begin
        #300000;
        $display("AXIS ARB CORNER FAIL : TIMEOUT");
        $finish;
    end

endmodule
