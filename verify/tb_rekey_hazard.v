`timescale 1ns / 1ps
// ============================================================================
// tb_rekey_hazard.v —— 换密钥时序约束（hazard）专项用例
//
// 目的：显式证明设计存在一条"换密钥必须排空流水线"的使用约束。
//
// 机理：
//   key_ram 是 key schedule FSM 与流水线各级共用的同一块存储。
//   FSM 进入 CALC 后会按 0,1,2,...,15 的顺序逐条重写 key_ram。
//   此时若流水线里还有在途数据，这些数据会读到"半新半旧"的子密钥。
//
//   加密方向：第 i 轮读 key_ram[i]，而 FSM 从 0 往上写 —— 在途数据所在的
//             轮次总是大于 FSM 当前写入下标，恰好躲开，因此加密方向"碰巧安全"。
//   解密方向：第 i 轮读 key_ram[15-i]，即靠后几轮读的是低下标 —— 与 FSM
//             从 0 开始的写入顺序正面相撞，在途数据必然被污染。
//
// 用法：
//   Phase H（危险）：4 笔解密在途时立刻重算 key schedule -> 期望看到 MISMATCH
//   Phase S（正确）：4 笔解密全部收完（排空）后再重算       -> 期望 0 mismatch
// ============================================================================
module tb_rekey_hazard;

    reg         clk, rst_n, load_key_i, encrypt_i, valid_i, ready_i;
    reg  [63:0] key_i, data_i;
    wire        ready_key_o, valid_o, ready_o;
    wire [63:0] data_o;

    des_pipeline_fb uut (
        .clk(clk), .rst_n(rst_n),
        .load_key_i(load_key_i), .key_i(key_i), .ready_key_o(ready_key_o),
        .encrypt_i(encrypt_i),
        .valid_i(valid_i), .data_i(data_i), .ready_i(ready_i),
        .valid_o(valid_o), .ready_o(ready_o), .data_o(data_o)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    localparam [63:0] KEY1 = 64'h133457799BBCDFF1;
    localparam [63:0] KEY2 = 64'hFFFFFFFFFFFFFFFF;

    // KEY1 解密用的 4 组 (密文 -> 明文)
    reg [63:0] ct [0:3];
    reg [63:0] pt [0:3];

    integer n_out, n_cmp, mism_h, mism_s;
    integer phase;              // 1 = Phase H(危险), 2 = Phase S(排空后)
    integer pushed, popped;
    reg [63:0] pend [0:15];
    integer ph, pt_;

    // 采集输出：按弹出顺序与当前阶段的期望比对
    always @(posedge clk) begin
        if (rst_n && valid_o && ready_i) begin
            if (popped < pushed) begin
                n_cmp = n_cmp + 1;
                if (data_o !== pend[popped]) begin
                    $display("[%0t]  phase%0d MISMATCH #%0d : DUT=%h expect=%h", $time, phase, popped, data_o, pend[popped]);
                    if (phase == 1) mism_h = mism_h + 1; else mism_s = mism_s + 1;
                end else begin
                    $display("[%0t]  phase%0d   OK   #%0d : %h", $time, phase, popped, data_o);
                end
                popped = popped + 1;
            end
        end
    end

    task load_key(input [63:0] k);
        begin
            @(negedge clk); key_i = k; load_key_i = 1;
            @(posedge clk); @(negedge clk); load_key_i = 0;
            wait(ready_key_o == 1'b0);
            wait(ready_key_o == 1'b1);
        end
    endtask

    task inject(input [63:0] d);
        begin
            @(negedge clk); data_i = d; valid_i = 1;
            @(posedge clk);
            while (!(valid_i && ready_o)) @(posedge clk);
            @(negedge clk); valid_i = 0; data_i = 0;
        end
    endtask

    task push_expect(input [63:0] e);
        begin
            pend[pushed] = e; pushed = pushed + 1;
        end
    endtask

    // 复位并准备阶段
    task do_reset;
        begin
            rst_n = 0; valid_i = 0; data_i = 0; ready_i = 1;
            load_key_i = 0; key_i = 0; encrypt_i = 0;
            #100; rst_n = 1; #20;
        end
    endtask

    integer i;
    initial begin
        ct[0]=64'h85E813540F0AB405; pt[0]=64'h0123456789ABCDEF;
        ct[1]=64'h9768537ED9ACE3CE; pt[1]=64'h1111111111111111;
        ct[2]=64'h5E185389844E8363; pt[2]=64'h2222222222222222;
        ct[3]=64'h5B82BB92E243206F; pt[3]=64'h403EA380E1462EC4;

        n_out=0; n_cmp=0; mism_h=0; mism_s=0; pushed=0; popped=0;

        // ---------------- Phase H：在途数据未清空就换密钥（危险） ----------------
        phase = 1;
        do_reset;
        load_key(KEY1);
        $display("[%0t] === Phase H: 在途数据未排空就重算 key schedule ===", $time);
        for (i=0; i<4; i=i+1) begin
            push_expect(pt[i]);
            inject(ct[i]);
        end
        // 关键：不等输出收完，立刻用 KEY2 重算子密钥
        $display("[%0t]   -- 4 笔仍在流水线中，立即 load_key(KEY2) --", $time);
        load_key(KEY2);
        // 等 4 笔全部吐出
        while (popped < 4) @(posedge clk);
        #40;
        $display("[%0t] Phase H 结果: mismatch=%0d / 4", $time, mism_h);

        // ---------------- Phase S：排空后再换密钥（正确） ----------------
        phase = 2;
        pushed = 0; popped = 0;
        do_reset;
        load_key(KEY1);
        $display("[%0t] === Phase S: 先把 4 笔收完再重算 key schedule ===", $time);
        for (i=0; i<4; i=i+1) begin
            push_expect(pt[i]);
            inject(ct[i]);
        end
        while (popped < 4) @(posedge clk);   // 排空
        $display("[%0t]   -- 流水线已排空，现在 load_key(KEY2) --", $time);
        load_key(KEY2);
        #40;
        $display("[%0t] Phase S 结果: mismatch=%0d / 4", $time, mism_s);

        $display("");
        $display("==================== REKEY HAZARD SUMMARY ====================");
        $display("  Phase H (不排空换密钥) mismatch : %0d / 4", mism_h);
        $display("  Phase S (排空后换密钥) mismatch : %0d / 4", mism_s);
        if (mism_h > 0 && mism_s == 0)
            $display("  >> 结论：确认存在【换密钥必须排空流水线】约束（加密方向碰巧安全，解密方向会撞）");
        else
            $display("  >> 结论：本次未复现出差异，请检查激励时序");
        $display("=============================================================");
        $finish;
    end

    initial begin #50000; $display("HAZARD TIMEOUT"); $finish; end
endmodule
