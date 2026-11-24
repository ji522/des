`timescale 1ns / 1ps
// ============================================================================
// tb_des_axis_cdc.v —— AXI4-Stream 封装 + 跨时钟域 合并顶层的自检 TB
//
// 结构：
//   慢域 100MHz：AXI4-Stream slave 灌 28 笔加密 + 14 笔解密，TLAST 每 4 拍一次
//   快域 250MHz：AXI4-Lite 配置密钥/模式/使能；AXI4-Stream master 输出
//   快域随机反压 + 周期性长 stall，把流水线和异步 FIFO 一起写满（触发 wfull）
//
// 检查：
//   1) 数据逐笔对拍（黄金向量）
//   2) TLAST 与数据拍对齐（过域后仍然对齐）
//   3) 不丢不重：pushed == popped == q_tail == 42
//   4) 反压真的发生：stall_cnt > 0
//   5) 慢域被节流过：wfull 至少拉高过一次（证明异步 FIFO 的满路径被走到）
//   6) 换钥只在排空后做；若发生在途换钥，rekey_busy 会加
//
// 向量：verify/vectors/*.mem（28 加密 + 14 解密）
// ============================================================================
module tb_des_axis_cdc;

    // ---------------- 时钟 / 复位 ----------------
    reg wclk = 1'b0, clk = 1'b0;
    reg wrst_n = 1'b0, rst_n = 1'b0;

    always #5 wclk = ~wclk;      // 100 MHz
    always #2 clk  = ~clk;       // 250 MHz（与 wclk 无公共沿）

    // ---------------- 慢域 AXIS slave ----------------
    reg         s_axis_tvalid = 1'b0;
    wire        s_axis_tready;
    reg  [63:0] s_axis_tdata  = 64'd0;
    reg         s_axis_tlast  = 1'b0;

    // ---------------- 快域 AXIL ----------------
    reg         awvalid = 1'b0, wvalid = 1'b0;
    reg  [31:0] awaddr  = 32'd0, wdata  = 32'd0;
    reg  [3:0]  wstrb   = 4'hF;
    wire        awready, wready, bvalid;
    reg         bready  = 1'b0;
    reg         arvalid = 1'b0;
    reg  [31:0] araddr  = 32'd0;
    wire        arready, rvalid;
    reg         rready  = 1'b0;
    wire [31:0] rdata;
    wire [1:0]  bresp, rresp;

    // ---------------- 快域 AXIS master ----------------
    wire        m_axis_tvalid, m_axis_tlast;
    wire [63:0] m_axis_tdata;
    reg         m_axis_tready;

    // ---------------- 反向状态 ----------------
    wire ready_key_o_wclk;

    des_axis_cdc_top dut (
        .wclk            (wclk),
        .wrst_n          (wrst_n),
        .s_axis_tvalid   (s_axis_tvalid),
        .s_axis_tready   (s_axis_tready),
        .s_axis_tdata    (s_axis_tdata),
        .s_axis_tlast    (s_axis_tlast),

        .clk             (clk),
        .rst_n           (rst_n),
        .s_axil_awvalid  (awvalid),
        .s_axil_awready  (awready),
        .s_axil_awaddr   (awaddr),
        .s_axil_wvalid   (wvalid),
        .s_axil_wready   (wready),
        .s_axil_wdata    (wdata),
        .s_axil_wstrb    (wstrb),
        .s_axil_bvalid   (bvalid),
        .s_axil_bready   (bready),
        .s_axil_bresp    (bresp),
        .s_axil_arvalid  (arvalid),
        .s_axil_arready  (arready),
        .s_axil_araddr   (araddr),
        .s_axil_rvalid   (rvalid),
        .s_axil_rready   (rready),
        .s_axil_rdata    (rdata),
        .s_axil_rresp    (rresp),

        .m_axis_tvalid   (m_axis_tvalid),
        .m_axis_tready   (m_axis_tready),
        .m_axis_tdata    (m_axis_tdata),
        .m_axis_tlast    (m_axis_tlast),

        .ready_key_o_wclk(ready_key_o_wclk)
    );

    // ---------------- 向量 ----------------
    reg [63:0] k_arr  [0:27];
    reg [63:0] i_arr  [0:27];
    reg [63:0] e_arr  [0:27];
    reg [63:0] dk_arr [0:13];
    reg [63:0] di_arr [0:13];
    reg [63:0] de_arr [0:13];

    // 期望队列
    reg [63:0] exp_q    [0:127];
    reg        exp_last [0:127];
    integer    q_head, q_tail;

    // 计数
    integer n_pass, n_err, n_last_err, n_extra;
    integer pushed, popped, stall_cnt, n_full, rekey_busy;
    integer n_rdy_wclk;

    reg [63:0] cur_key;
    reg [15:0] lfsr;
    integer    j, wd;

    localparam integer WD_LIMIT = 2000;

    // ---------------- 慢域写计数（真正的输入握手）----------------
    always @(posedge wclk) begin
        if (wrst_n && s_axis_tvalid && s_axis_tready)
            pushed = pushed + 1;
    end

    // ---------------- 快域读比对 ----------------
    always @(posedge clk) begin
        if (rst_n) begin
            if (m_axis_tvalid && !m_axis_tready)
                stall_cnt = stall_cnt + 1;

            if (m_axis_tvalid && m_axis_tready) begin
                popped = popped + 1;
                if (q_head < q_tail) begin
                    if ($isunknown(m_axis_tdata) || $isunknown(exp_q[q_head])) begin
                        n_err = n_err + 1;
                        $display("[%0t] X/Z #%0d : DUT=%h EXP=%h", $time, q_head, m_axis_tdata, exp_q[q_head]);
                    end else if (m_axis_tdata !== exp_q[q_head]) begin
                        n_err = n_err + 1;
                        $display("[%0t] DATA MISMATCH #%0d : DUT=%h EXP=%h", $time, q_head, m_axis_tdata, exp_q[q_head]);
                    end else if (m_axis_tlast !== exp_last[q_head]) begin
                        n_last_err = n_last_err + 1;
                        $display("[%0t] TLAST MISMATCH #%0d : DUT=%b EXP=%b", $time, q_head, m_axis_tlast, exp_last[q_head]);
                    end else begin
                        n_pass = n_pass + 1;
                    end
                    q_head = q_head + 1;
                end else begin
                    n_extra = n_extra + 1;
                    $display("[%0t] EXTRA OUTPUT : %h", $time, m_axis_tdata);
                end
            end
        end
    end

    // FIFO 满计数（慢域看 wfull）
    always @(posedge wclk) begin
        if (wrst_n && dut.wfull) n_full = n_full + 1;
    end

    // 探针：慢域被节流的拍数 + FIFO 最大占用
    integer n_sr0;
    integer max_occ;
    integer occ_now;
    integer max_pipe;
    integer n_ffetch;
    initial begin
        n_sr0    = 0;
        max_occ  = 0;
        max_pipe = 0;
        n_ffetch = 0;
    end
    always @(posedge wclk) begin
        if (wrst_n) begin
            if (!s_axis_tready) n_sr0 = n_sr0 + 1;
            occ_now = dut.u_fifo.wbin - dut.u_fifo.rbin;
            if (occ_now > max_occ) max_occ = occ_now;
        end
    end
    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.in_flight_f > max_pipe) max_pipe = dut.in_flight_f;
            if (dut.fifo_fetch) n_ffetch = n_ffetch + 1;
        end
    end

    // 在途换钥检查
    always @(posedge clk) begin
        if (rst_n && dut.load_key_f && (popped < pushed)) begin
            rekey_busy = rekey_busy + 1;
            $display("[%0t] REKEY WHILE BUSY : in-flight=%0d", $time, pushed - popped);
        end
    end

    // 反向状态确实传到了慢域
    always @(posedge wclk) begin
        if (wrst_n && ready_key_o_wclk) n_rdy_wclk = n_rdy_wclk + 1;
    end

    // ---------------- 快域反压：正常节奏 + 满压力窗口 ----------------
    // 每个 negedge 都显式给 m_axis_tready 赋值，避免任何分支"保持"导致锁死。
    // 正常节奏：200 拍 ready / 200 拍长 stall，ready 窗口内再用 LFSR 插短 stall。
    // 满压力：stress_req 置 1 后，连续 500 拍全 stall，用来把 FIFO 写满。
    integer cyc_cnt;
    integer stress_left;
    reg     stress_req;

    always @(negedge clk) begin
        if (!rst_n) begin
            lfsr          <= 16'hACE1;
            cyc_cnt       <= 0;
            stress_left   <= 0;
            stress_req    <= 1'b0;
            m_axis_tready <= 1'b1;
        end else begin
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};

            if (stress_left > 0) begin
                m_axis_tready <= 1'b0;
                stress_left   <= stress_left - 1;
            end else if (stress_req) begin
                stress_req    <= 1'b0;
                stress_left   <= 500;
                m_axis_tready <= 1'b0;
            end else begin
                if (cyc_cnt >= 399)
                    cyc_cnt <= 0;
                else
                    cyc_cnt <= cyc_cnt + 1;

                if (cyc_cnt < 200)
                    m_axis_tready <= (lfsr[3:0] != 4'h0);
                else
                    m_axis_tready <= 1'b0;
            end
        end
    end

    // ---------------- AXIL 任务 ----------------
    task axil_write(input [31:0] a, input [31:0] d, input [3:0] strb);
        begin
            @(negedge clk);
            awaddr = a; awvalid = 1'b1;
            wdata  = d; wstrb = strb; wvalid = 1'b1;
            bready = 1'b1;

            @(posedge clk);
            wd = 0;
            while (!(awvalid && awready) && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(TIMEOUT) AWREADY", $time); end

            wd = 0;
            while (!(wvalid && wready) && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(TIMEOUT) WREADY", $time); end

            @(negedge clk);
            awvalid = 1'b0; wvalid = 1'b0;

            wd = 0;
            while (!bvalid && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(TIMEOUT) BVALID", $time); end

            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task axil_read(input [31:0] a, output [31:0] d);
        begin
            @(negedge clk);
            araddr = a; arvalid = 1'b1; rready = 1'b1;

            @(posedge clk);
            wd = 0;
            while (!(arvalid && arready) && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(TIMEOUT) ARREADY", $time); end

            @(negedge clk);
            arvalid = 1'b0;

            wd = 0;
            while (!rvalid && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(TIMEOUT) RVALID", $time); end
            d = rdata;

            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    // 等密钥就绪：STATUS[0]=KEY_READY
    task wait_key_ready;
        reg [31:0] st;
        integer t;
        begin
            t = 0;
            st = 0;
            while (!(st[0] === 1'b1) && t < 200) begin
                axil_read(32'h0C, st);
                t = t + 1;
            end
            if (t >= 200) begin
                n_err = n_err + 1;
                $display("[%0t] FAIL(TIMEOUT) KEY_READY", $time);
            end
        end
    endtask

    // ---------------- 慢域送一拍 ----------------
    task push_beat(input [63:0] d, input last);
        begin
            @(negedge wclk);
            s_axis_tvalid = 1'b1;
            s_axis_tdata  = d;
            s_axis_tlast  = last;
            @(posedge wclk);
            while (!(s_axis_tvalid && s_axis_tready)) @(posedge wclk);
            @(negedge wclk);
            s_axis_tvalid = 1'b0;
            s_axis_tdata  = 64'h0;
            s_axis_tlast  = 1'b0;
        end
    endtask

    task wait_drain;
        begin
            while (popped < pushed) @(posedge clk);
        end
    endtask

    // 排空后换钥：写 KEY_LO / KEY_HI，等 ready
    task rekey(input [63:0] k);
        begin
            wait_drain;
            axil_write(32'h00, k[31:0],  4'hF);
            axil_write(32'h04, k[63:32], 4'hF);   // 写高字触发 load_key
            wait_key_ready;
            cur_key = k;
        end
    endtask

    // ---------------- 主流程 ----------------
    initial begin
        q_head = 0; q_tail = 0;
        n_pass = 0; n_err = 0; n_last_err = 0; n_extra = 0;
        pushed = 0; popped = 0; stall_cnt = 0; n_full = 0;
        rekey_busy = 0; n_rdy_wclk = 0;
        cur_key = 64'h0;

        $readmemh("keys.mem",  k_arr);
        $readmemh("ins.mem",   i_arr);
        $readmemh("exps.mem",  e_arr);
        $readmemh("dkeys.mem", dk_arr);
        $readmemh("dins.mem",  di_arr);
        $readmemh("dexps.mem", de_arr);

        // 复位：两个域同时
        wrst_n = 1'b0; rst_n = 1'b0;
        #200;
        wrst_n = 1'b1; rst_n = 1'b1;
        #200;

        $display("=== DES AXI4-Stream + CDC test : N_ENC=28 N_DEC=14 ===");

        // ---- 加密段：先配密钥，再开使能 ----
        axil_write(32'h00, k_arr[0][31:0],  4'hF);
        axil_write(32'h04, k_arr[0][63:32], 4'hF);
        wait_key_ready;
        cur_key = k_arr[0];
        axil_write(32'h08, 32'h0000_0003, 4'hF);   // MODE=1, ENABLE=1

        for (j = 0; j < 28; j = j + 1) begin
            if (k_arr[j] !== cur_key)
                rekey(k_arr[j]);
            exp_q[q_tail]    = e_arr[j];
            exp_last[q_tail] = ((j % 4) == 3);
            q_tail           = q_tail + 1;
            push_beat(i_arr[j], ((j % 4) == 3));
        end
        wait_drain;
        #200;
        $display("Encryption done : pushed=%0d popped=%0d", pushed, popped);

        // ---- 解密段 ----
        axil_write(32'h08, 32'h0000_0002, 4'hF);   // MODE=0, ENABLE=1
        cur_key = 64'h0;
        for (j = 0; j < 14; j = j + 1) begin
            if (dk_arr[j] !== cur_key)
                rekey(dk_arr[j]);
            exp_q[q_tail]    = de_arr[j];
            exp_last[q_tail] = ((j % 4) == 3);
            q_tail           = q_tail + 1;
            push_beat(di_arr[j], ((j % 4) == 3));
        end
        wait_drain;
        #400;

        // ---- 满压力段：同一密钥连灌 48 拍，输出强制停 500 拍 ----
        // 目的：把 16 深异步 FIFO + 16 级流水线一起灌满，真正踩到 wfull。
        // 前面 42 笔里每次换钥都要排空，数据量堆不起来，踩不到满。
        //
        // 注意：只有向量 0..11 与 k_arr[0] 同密钥（keys.mem 的 3 段：
        // 1334..[0..11] / ffff..[12..19] / 0123..[20..27]）。压力段必须只用
        // 这 12 笔循环，否则期望值 e_arr[j] 对应的密钥和实际密钥不一致，
        // 会得到"DUT 看起来错、其实是 TB 期望值错"的假失败。
        rekey(k_arr[0]);
        axil_write(32'h08, 32'h0000_0003, 4'hF);   // MODE=1, ENABLE=1
        stress_req = 1'b1;

        for (j = 0; j < 48; j = j + 1) begin
            exp_q[q_tail]    = e_arr[j % 12];
            exp_last[q_tail] = ((j % 4) == 3);
            q_tail           = q_tail + 1;
            push_beat(i_arr[j % 12], ((j % 4) == 3));
        end
        wait_drain;
        #400;

        $display("================ AXIS-CDC SUMMARY ================");
        $display("  pass          : %0d", n_pass);
        $display("  data errors   : %0d", n_err);
        $display("  TLAST errors  : %0d", n_last_err);
        $display("  extra outputs : %0d", n_extra);
        $display("  pushed/popped : %0d / %0d", pushed, popped);
        $display("  stalls        : %0d cycles", stall_cnt);
        $display("  wfull cycles  : %0d", n_full);
        $display("  rekey busy    : %0d", rekey_busy);
        $display("  rdy_key wclk  : %0d cycles", n_rdy_wclk);
        $display("  s_tready low  : %0d cycles", n_sr0);
        $display("  fifo max occ  : %0d / 16", max_occ);
        $display("  pipe max infl : %0d", max_pipe);
        $display("  fifo fetch    : %0d", n_ffetch);
        $display("==================================================");

        if (n_err == 0 && n_last_err == 0 && n_extra == 0 &&
            rekey_busy == 0 && pushed == popped && popped == q_tail &&
            q_tail == 90 && stall_cnt > 0 && n_full > 0 && n_rdy_wclk > 0)
            $display("AXIS-CDC TB PASS : %0d/%0d", n_pass, pushed);
        else
            $display("AXIS-CDC TB FAIL : pass=%0d err=%0d last_err=%0d extra=%0d rekey_busy=%0d pushed=%0d popped=%0d stall=%0d full=%0d rdy=%0d",
                     n_pass, n_err, n_last_err, n_extra, rekey_busy,
                     pushed, popped, stall_cnt, n_full, n_rdy_wclk);

        $finish;
    end

    initial begin
        #2_000_000;
        $display("TIMEOUT");
        $finish;
    end

    // 状态监控（每 2us 打印一次）
    always #2000 begin
        $display("[MON %0t] push=%0d pop=%0d wfull=%b mrdy=%b rv=%b infl=%0d occ=%0d",
                 $time, pushed, popped, dut.wfull, m_axis_tready, dut.rdata_v,
                 dut.in_flight_f, dut.u_fifo.wbin - dut.u_fifo.rbin);
    end

endmodule
