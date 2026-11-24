`timescale 1ns / 1ps
// =====================================================================
// tb_des_cdc —— 异步 FIFO + CDC 版 DES 顶层多时钟验证
//
//   慢域 100MHz 注入（随机间隔 + FIFO 满时被 s_ready 节流）
//   快域 250MHz 消费（随机反压 + 周期性长 stall 制造 FIFO 满）
//   校验：跨域后输出与黄金向量逐笔比对（顺序保持、零丢失、零多余）
//
//   向量：verify/vectors/*.mem（28 加密 + 14 解密，pycryptodome 黄金模型）
// =====================================================================
module tb_des_cdc;

    reg  wclk = 1'b0, clk = 1'b0;
    reg  wrst_n = 1'b0, rst_n = 1'b0;
    reg  s_valid = 1'b0, s_encrypt = 1'b1, s_load_key = 1'b0;
    reg  [63:0] s_data = 64'd0, s_key = 64'd0;
    wire s_ready, valid_o, ready_key_o, ready_key_o_wclk;
    wire [63:0] data_o;
    reg  ready_i = 1'b0;

    des_cdc_top dut(
        .wclk(wclk), .wrst_n(wrst_n),
        .s_valid(s_valid), .s_data(s_data), .s_ready(s_ready),
        .s_encrypt(s_encrypt), .s_load_key(s_load_key), .s_key(s_key),
        .clk(clk), .rst_n(rst_n),
        .valid_o(valid_o), .ready_i(ready_i), .data_o(data_o),
        .ready_key_o(ready_key_o), .ready_key_o_wclk(ready_key_o_wclk)
    );

    always #5 wclk = ~wclk;      // 100 MHz
    always #2 clk  = ~clk;       // 250 MHz（与 wclk 无公共沿，天然异步）

    // ---------------- 向量 ----------------
    reg [63:0] keys_e [0:27], ins_e [0:27], exps_e [0:27];
    reg [63:0] keys_d [0:13], ins_d [0:13], exps_d [0:13];
    reg [63:0] exp_q [0:191];    // 按注入顺序排队的期望值（3 轮 × 42 笔 + 64 笔满压力）

    integer n_push = 0, n_cmp = 0, n_err = 0, n_x = 0, n_extra = 0;
    integer n_full = 0, n_rekey = 0, i, rep;

    always @(posedge wclk) begin
        if (dut.wfull) n_full = n_full + 1;   // FIFO 满的周期数（节流发生过）
    end

    // ---------------- 输出比对（快域）----------------
    always @(posedge clk) begin
        if (rst_n && valid_o && ready_i) begin
            if ($isunknown(data_o)) begin
                n_x = n_x + 1;
                $display("[%0t] ** X ON DATA_O", $time);
            end else if (n_cmp >= n_push) begin
                n_extra = n_extra + 1;
                $display("[%0t] ** EXTRA OUTPUT %h", $time, data_o);
            end else begin
                if (data_o !== exp_q[n_cmp]) begin
                    n_err = n_err + 1;
                    $display("[%0t] ** MISMATCH #%0d exp=%h got=%h", $time, n_cmp, exp_q[n_cmp], data_o);
                end
                n_cmp = n_cmp + 1;
            end
        end
    end

    // ---------------- 下游随机反压 + 周期性长 stall（制造 FIFO 满）----------------
    integer last_big_stall = 0;
    initial begin
        ready_i = 1'b0;
        @(posedge rst_n);
        forever begin
            @(posedge clk);
            if (n_push - last_big_stall >= 8) begin
                last_big_stall = n_push;
                ready_i <= 1'b0;
                repeat (250) @(posedge clk);   // 长 stall：FIFO 必然写满、源侧被节流
                ready_i <= 1'b1;
            end else if ($urandom_range(0, 99) < 85) begin
                ready_i <= 1'b1;               // 常态 85% ready
            end else begin
                ready_i <= 1'b0;
                repeat ($urandom_range(5, 15)) @(posedge clk);
                ready_i <= 1'b1;
            end
        end
    end

    // ---------------- 慢域注入任务 ----------------
    // 负沿驱动（避免与 DUT 正沿采样同沿撞车），正沿采样 s_ready 判定接受
    task push_word(input [63:0] d, input [63:0] exp);
        begin
            @(negedge wclk);
            s_valid <= 1'b1;
            s_data  <= d;
            forever begin
                @(posedge wclk);
                if (s_ready) begin              // 本拍被 FIFO 接受
                    exp_q[n_push] = exp;
                    n_push = n_push + 1;
                    s_valid <= 1'b0;            // NBA：下一拍前撤销，防重复注入
                    break;
                end
            end
            repeat ($urandom_range(0, 3)) @(posedge wclk);   // 随机间隔 0~3 拍
        end
    endtask

    task drain;
        begin
            s_valid <= 1'b0;
            wait (n_cmp == n_push);
            repeat (200) @(posedge clk);        // 等 FIFO/流水线/同步器彻底走空
        end
    endtask

    // 排空 → 稳定 key（准静态）→ 切模式（电平）→ 换钥脉冲（toggle）→ 等就绪
    task do_rekey(input [63:0] k, input enc);
        begin
            drain();
            @(negedge wclk);
            s_key      = k;
            s_encrypt  <= enc;
            s_load_key <= 1'b1;
            @(negedge wclk);
            s_load_key <= 1'b0;                 // 一个慢域周期脉冲
            n_rekey = n_rekey + 1;
            // 反向通道走 wclk 域同步副本（慢域主设备的真实视角，副本滞后 2 慢拍）
            @(posedge wclk);
            while (ready_key_o_wclk)  @(posedge wclk);   // 等待 FSM 离开 READY
            while (!ready_key_o_wclk) @(posedge wclk);   // 等待 16 拍密钥预计算完成
            repeat (4) @(posedge wclk);
        end
    endtask

    // ---------------- 主序列 ----------------
    initial begin
        wrst_n = 1'b0;
        rst_n  = 1'b0;
        #37 wrst_n = 1'b1;      // 两域复位释放时刻错开，强化异步性
        #13 rst_n  = 1'b1;
        #100;

        $readmemh("keys.mem",  keys_e);
        $readmemh("ins.mem",   ins_e);
        $readmemh("exps.mem",  exps_e);
        $readmemh("dkeys.mem", keys_d);
        $readmemh("dins.mem",  ins_d);
        $readmemh("dexps.mem", exps_d);

        // ===== 3 轮 ×（28 加密 + 14 解密）= 126 笔 =====
        // 向量总量需远大于在途缓冲（FIFO 16 + 流水级 16），否则长 stall
        // 期间源侧先没数据了、FIFO 满节流路径激励不到
        for (rep = 0; rep < 3; rep = rep + 1) begin
            do_rekey(keys_e[0], 1'b1);
            for (i = 0; i < 28; i = i + 1) begin
                if (i > 0 && keys_e[i] !== keys_e[i-1]) do_rekey(keys_e[i], 1'b1);
                push_word(ins_e[i], exps_e[i]);
            end

            do_rekey(keys_d[0], 1'b0);
            for (i = 0; i < 14; i = i + 1) begin
                if (i > 0 && keys_d[i] !== keys_d[i-1]) do_rekey(keys_d[i], 1'b0);
                push_word(ins_d[i], exps_d[i]);
            end
        end

        // ===== FIFO 满压力场景：单密钥连续灌 64 笔（无换钥打断）=====
        // 换钥 drain 会截断在途数据流，导致常规序列打不满缓冲
        // （FIFO 16 + 流水级 16 ≈ 33 深）；单钥长跑 + 长 stall 必然写满
        do_rekey(keys_e[0], 1'b1);
        for (i = 0; i < 64; i = i + 1) begin
            push_word(ins_e[0], exps_e[0]);
        end

        drain();
        #300;

        $display("========== CDC TB ==========");
        $display("  push / cmp        : %0d / %0d", n_push, n_cmp);
        $display("  mismatch          : %0d", n_err);
        $display("  X / extra output  : %0d / %0d", n_x, n_extra);
        $display("  rekey 次数        : %0d", n_rekey);
        $display("  wfull 周期数      : %0d", n_full);
        $display("============================");
        if (n_err == 0 && n_x == 0 && n_extra == 0 && n_cmp == n_push && n_push == 190)
            $display("**** CDC TB PASS : 190/190 跨域全对（含 FIFO 满节流 %0d 拍）****", n_full);
        else
            $display("**** CDC TB FAIL ****");
        $finish;
    end

    // 看门狗
    initial begin
        #1_000_000;
        $display("**** TIMEOUT FAIL ****");
        $finish;
    end

endmodule
