`timescale 1ns / 1ps
// ============================================================================
// tb_des_axis_wrap.v
// Self-checking AXI4-Stream wrapper testbench.
//
// - Reuses the existing 42-vector set (28 encrypt + 14 decrypt).
// - Drives random-like output back-pressure with an LFSR.
// - Checks data order, golden values, and TLAST alignment.
// - Rekeys only after the pipeline is drained.
// ============================================================================
`include "params.vh"

module tb_des_axis_wrap;

    reg         clk;
    reg         rst_n;

    reg         s_axis_tvalid;
    wire        s_axis_tready;
    reg  [63:0] s_axis_tdata;
    reg         s_axis_tlast;

    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire [63:0] m_axis_tdata;
    wire        m_axis_tlast;

    reg         load_key_i;
    reg  [63:0] key_i;
    wire        ready_key_o;
    reg         encrypt_i;

    des_axis_wrap uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tlast (s_axis_tlast),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tlast (m_axis_tlast),
        .load_key_i   (load_key_i),
        .key_i        (key_i),
        .ready_key_o  (ready_key_o),
        .encrypt_i    (encrypt_i)
    );

    // Vector storage
    reg [63:0] k_arr  [0:`N_ENC-1];
    reg [63:0] i_arr  [0:`N_ENC-1];
    reg [63:0] e_arr  [0:`N_ENC-1];
    reg [63:0] dk_arr [0:`N_DEC-1];
    reg [63:0] di_arr [0:`N_DEC-1];
    reg [63:0] de_arr [0:`N_DEC-1];

    // Expected queue
    reg [63:0] exp_q    [0:127];
    reg        exp_last [0:127];
    integer    q_head;
    integer    q_tail;

    integer n_pass;
    integer n_err;
    integer n_last_err;
    integer n_extra;
    integer pushed;
    integer popped;
    integer stall_cnt;
    integer key_sw;
    integer rekey_busy;

    reg [63:0] cur_key;
    reg [15:0] lfsr;
    integer    j;

    // 100 MHz clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Random-like output back-pressure.  The LFSR sets ready low near 0x0 and
    // high near 0xF, producing stalls of several cycles without external
    // random-number dependencies.
    always @(negedge clk) begin
        if (!rst_n) begin
            lfsr          <= 16'hACE1;
            m_axis_tready <= 1'b1;
        end else begin
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            if (lfsr[3:0] == 4'h0)
                m_axis_tready <= 1'b0;
            else if (lfsr[3:0] == 4'hF)
                m_axis_tready <= 1'b1;
        end
    end

    // Scoreboard and protocol counters
    always @(posedge clk) begin
        if (rst_n) begin
            if (s_axis_tvalid && s_axis_tready)
                pushed = pushed + 1;

            if (m_axis_tvalid && !m_axis_tready)
                stall_cnt = stall_cnt + 1;

            if (m_axis_tvalid && m_axis_tready) begin
                popped = popped + 1;

                if (q_head < q_tail) begin
                    if ((^m_axis_tdata === 1'bx) || (^exp_q[q_head] === 1'bx)) begin
                        n_err = n_err + 1;
                        $display("[%0t] X/Z #%0d : DUT=%h EXP=%h",
                                 $time, q_head, m_axis_tdata, exp_q[q_head]);
                    end else if (m_axis_tdata !== exp_q[q_head]) begin
                        n_err = n_err + 1;
                        $display("[%0t] DATA MISMATCH #%0d : DUT=%h EXP=%h",
                                 $time, q_head, m_axis_tdata, exp_q[q_head]);
                    end else if (m_axis_tlast !== exp_last[q_head]) begin
                        n_last_err = n_last_err + 1;
                        $display("[%0t] TLAST MISMATCH #%0d : DUT=%b EXP=%b",
                                 $time, q_head, m_axis_tlast, exp_last[q_head]);
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

    // Rekey while in-flight data exists is a design violation.
    always @(posedge clk) begin
        if (rst_n && load_key_i && (popped < pushed)) begin
            rekey_busy = rekey_busy + 1;
            $display("[%0t] REKEY WHILE BUSY : in-flight=%0d",
                     $time, pushed - popped);
        end
    end

    task load_key(input [63:0] k);
        begin
            @(negedge clk);
            key_i      = k;
            load_key_i = 1'b1;
            @(posedge clk);
            @(negedge clk);
            load_key_i = 1'b0;
            wait (ready_key_o == 1'b0);
            wait (ready_key_o == 1'b1);
        end
    endtask

    task send_beat(input [63:0] d, input last);
        begin
            @(negedge clk);
            s_axis_tvalid = 1'b1;
            s_axis_tdata  = d;
            s_axis_tlast  = last;
            @(posedge clk);
            while (!(s_axis_tvalid && s_axis_tready))
                @(posedge clk);
            @(negedge clk);
            s_axis_tvalid = 1'b0;
            s_axis_tdata  = 64'h0;
            s_axis_tlast  = 1'b0;
        end
    endtask

    task wait_drain;
        begin
            while (popped < pushed)
                @(posedge clk);
        end
    endtask

    task rekey(input [63:0] k);
        begin
            wait_drain;
            load_key(k);
            cur_key = k;
            key_sw  = key_sw + 1;
        end
    endtask

    initial begin
        rst_n         = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata  = 64'h0;
        s_axis_tlast  = 1'b0;
        load_key_i    = 1'b0;
        key_i         = 64'h0;
        encrypt_i     = 1'b1;

        q_head     = 0;
        q_tail     = 0;
        n_pass     = 0;
        n_err      = 0;
        n_last_err = 0;
        n_extra    = 0;
        pushed     = 0;
        popped     = 0;
        stall_cnt  = 0;
        key_sw     = 0;
        rekey_busy = 0;
        cur_key    = 64'h0;

        $readmemh("keys.mem",  k_arr);
        $readmemh("ins.mem",   i_arr);
        $readmemh("exps.mem",  e_arr);
        $readmemh("dkeys.mem", dk_arr);
        $readmemh("dins.mem",  di_arr);
        $readmemh("dexps.mem", de_arr);

        #100;
        rst_n = 1'b1;
        #20;

        $display("=== DES AXI4-Stream wrapper test : N_ENC=%0d N_DEC=%0d ===",
                 `N_ENC, `N_DEC);

        // Encryption vectors
        for (j = 0; j < `N_ENC; j = j + 1) begin
            if (k_arr[j] !== cur_key)
                rekey(k_arr[j]);
            exp_q[q_tail]    = e_arr[j];
            exp_last[q_tail] = ((j % 4) == 3);
            q_tail           = q_tail + 1;
            send_beat(i_arr[j], ((j % 4) == 3));
        end
        wait_drain;
        #40;
        $display("Encryption done : pushed=%0d popped=%0d", pushed, popped);

        // Decryption vectors
        encrypt_i = 1'b0;
        cur_key   = 64'h0;
        for (j = 0; j < `N_DEC; j = j + 1) begin
            if (dk_arr[j] !== cur_key)
                rekey(dk_arr[j]);
            exp_q[q_tail]    = de_arr[j];
            exp_last[q_tail] = ((j % 4) == 3);
            q_tail           = q_tail + 1;
            send_beat(di_arr[j], ((j % 4) == 3));
        end
        wait_drain;
        #40;
        $display("Decryption done : pushed=%0d popped=%0d", pushed, popped);

        $display("================ AXI4-STREAM WRAPPER SUMMARY ================");
        $display("  pass          : %0d", n_pass);
        $display("  data errors   : %0d", n_err);
        $display("  TLAST errors  : %0d", n_last_err);
        $display("  extra outputs : %0d", n_extra);
        $display("  pushed/popped : %0d / %0d", pushed, popped);
        $display("  stalls        : %0d cycles", stall_cnt);
        $display("  key reloads   : %0d", key_sw);
        $display("  rekey busy    : %0d", rekey_busy);
        $display("  SVA A6..A11 fail : %0d %0d %0d %0d %0d %0d",
                 uut.u_axis_check.a6_hits,  uut.u_axis_check.a7_hits,
                 uut.u_axis_check.a8_hits,  uut.u_axis_check.a9_hits,
                 uut.u_axis_check.a10_hits, uut.u_axis_check.a11_hits);
        $display("  SVA A6..A11 fire : %0d %0d %0d %0d %0d %0d",
                 uut.u_axis_check.a6_cov,  uut.u_axis_check.a7_cov,
                 uut.u_axis_check.a8_cov,  uut.u_axis_check.a9_cov,
                 uut.u_axis_check.a10_cov, uut.u_axis_check.a11_cov);
        $display("==============================================================");

        // SVA 覆盖率判据：A6~A11 不得失败；且输出反压前件（A6/A7/A9：
        // m_axis_tvalid && !m_axis_tready）必须真的发生过，证明断言不是空过。
        // 注：A10 的前件是输入反压（s_axis_tvalid && !s_axis_tready）。本
        // 用例逐笔发送，每笔之间留气泡，16 级流水永远填不满，故 A10 fire=0
        // 属结构性正常；A10 的非空过由 tb_axis_sva_neg 故意违约来证明。
        if (n_err == 0 && n_last_err == 0 && n_extra == 0 &&
            rekey_busy == 0 && pushed == popped && popped == q_tail &&
            q_tail == (`N_ENC + `N_DEC) && stall_cnt > 0 &&
            uut.u_axis_check.a6_hits  == 0 && uut.u_axis_check.a7_hits  == 0 &&
            uut.u_axis_check.a8_hits  == 0 && uut.u_axis_check.a9_hits  == 0 &&
            uut.u_axis_check.a10_hits == 0 && uut.u_axis_check.a11_hits == 0 &&
            uut.u_axis_check.a6_cov  > 0 && uut.u_axis_check.a7_cov  > 0 &&
            uut.u_axis_check.a9_cov  > 0 && uut.u_axis_check.a8_cov  > 0)
            $display("AXIS TB PASS : %0d/%0d", n_pass, pushed);
        else
            $display("AXIS TB FAIL : pass=%0d err=%0d last_err=%0d extra=%0d rekey_busy=%0d pushed=%0d popped=%0d stall=%0d sva_fail=%0d/%0d/%0d/%0d/%0d/%0d",
                     n_pass, n_err, n_last_err, n_extra, rekey_busy,
                     pushed, popped, stall_cnt,
                     uut.u_axis_check.a6_hits,  uut.u_axis_check.a7_hits,
                     uut.u_axis_check.a8_hits,  uut.u_axis_check.a9_hits,
                     uut.u_axis_check.a10_hits, uut.u_axis_check.a11_hits);

        $finish;
    end

    initial begin
        #2000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
