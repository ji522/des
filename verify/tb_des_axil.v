`timescale 1ns / 1ps
// ============================================================================
// tb_des_axil.v —— des_axil_regs 自检 testbench
//
// 覆盖目标：
//   T1 复位值              ：STATUS/CTRL/KEY 上电可读
//   T2 AW/W 同时到达        ：最理想情况基线
//   T3 AW 先到、W 迟到       ：AXI-Lite 经典坑之一
//   T4 W 先到、AW 迟到       ：经典坑之二（与 T3 对称，必须单独测）
//   T5 WSTRB 逐字节写       ：只写高/低字节，验证掩码
//   T6 写 KEY_HI 触发加载   ：load_key_o 必须恰好一拍
//   T7 在途换钥被拒绝       ：busy_i=1 时写 KEY_HI → REKEY_ERR=1，且无 load 脉冲
//   T8 REKEY_GUARD 放行      ：置位后同样场景应允许换钥
//   T9 CTRL.CLR_ERR 清粘滞   ：REKEY_ERR 回落
//   T10 读通道反压          ：RREADY 延迟拉高，RVALID/DATA 必须保持
//   T11 地址越界读           ：返回 0xDEADBEEF
// ============================================================================
module tb_des_axil;

    reg         clk;
    reg         rst_n;

    reg         awvalid, wvalid, arvalid, bready, rready;
    wire        awready, wready, bvalid, arready, rvalid;
    reg  [31:0] awaddr, wdata, araddr;
    reg  [3:0]  wstrb;
    wire [31:0] rdata;
    wire [1:0]  bresp, rresp;

    wire [63:0] key_o;
    wire        load_key_o;
    wire        encrypt_o;
    wire        des_enable_o;

    reg         ready_key_i;
    reg         busy_i;

    integer n_pass, n_err;
    integer load_pulses;
    integer j;
    integer WD_LIMIT;            // 有界等待上限，把"挂死"变成干净的失败

    des_axil_regs uut (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axil_awvalid(awvalid), .s_axil_awready(awready), .s_axil_awaddr(awaddr),
        .s_axil_wvalid (wvalid),  .s_axil_wready (wready),  .s_axil_wdata (wdata),
        .s_axil_wstrb  (wstrb),
        .s_axil_bvalid (bvalid),  .s_axil_bready (bready),  .s_axil_bresp (bresp),
        .s_axil_arvalid(arvalid), .s_axil_arready(arready), .s_axil_araddr(araddr),
        .s_axil_rvalid (rvalid),  .s_axil_rready (rready),  .s_axil_rdata (rdata),
        .s_axil_rresp  (rresp),
        .key_o         (key_o),
        .load_key_o    (load_key_o),
        .encrypt_o     (encrypt_o),
        .des_enable_o  (des_enable_o),
        .ready_key_i   (ready_key_i),
        .busy_i        (busy_i)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // 统计 load_key_o 脉冲数
    always @(posedge clk) begin
        if (rst_n && load_key_o) load_pulses = load_pulses + 1;
    end

    // ---------------- 任务 ----------------
    task check(input bit cond, input [255:0] msg);
        begin
            if (cond) begin
                n_pass = n_pass + 1;
            end else begin
                n_err = n_err + 1;
                $display("[%0t] FAIL : %0s", $time, msg);
            end
        end
    endtask

    // AW 与 W 同时到达
    task axil_write(input [31:0] addr, input [31:0] data, input [3:0] strb);
        integer wd;
        begin
            @(negedge clk);
            awaddr = addr; awvalid = 1'b1;
            wdata  = data; wstrb   = strb;  wvalid = 1'b1;
            bready = 1'b1;
            @(posedge clk);
            wd = 0;
            while (!(awvalid && awready) && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(超时) : AWREADY", $time); end
            wd = 0;
            while (!(wvalid && wready) && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(超时) : WREADY", $time); end
            @(negedge clk);
            awvalid = 1'b0;
            wvalid  = 1'b0;
            wd = 0;
            while (!bvalid && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(超时) : BVALID", $time); end
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    // AW 先到，W 延迟 gap 拍
    task axil_write_aw_first(input [31:0] addr, input [31:0] data, input integer gap);
        integer wd;
        begin
            @(negedge clk);
            awaddr = addr; awvalid = 1'b1;
            wvalid = 1'b0; bready = 1'b1;
            @(posedge clk);
            wd = 0;
            while (!(awvalid && awready) && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(超时) : AW-first AWREADY", $time); end
            @(negedge clk);
            awvalid = 1'b0;
            repeat (gap) @(negedge clk);
            wdata = data; wstrb = 4'hF; wvalid = 1'b1;
            @(posedge clk);
            wd = 0;
            while (!(wvalid && wready) && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(超时) : AW-first WREADY", $time); end
            @(negedge clk);
            wvalid = 1'b0;
            wd = 0;
            while (!bvalid && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(超时) : AW-first BVALID", $time); end
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    // W 先到，AW 延迟 gap 拍
    task axil_write_w_first(input [31:0] addr, input [31:0] data, input integer gap);
        integer wd;
        begin
            @(negedge clk);
            wdata = data; wstrb = 4'hF; wvalid = 1'b1;
            awvalid = 1'b0; bready = 1'b1;
            @(posedge clk);
            wd = 0;
            while (!(wvalid && wready) && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(超时) : W-first WREADY", $time); end
            @(negedge clk);
            wvalid = 1'b0;
            repeat (gap) @(negedge clk);
            awaddr = addr; awvalid = 1'b1;
            @(posedge clk);
            wd = 0;
            while (!(awvalid && awready) && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(超时) : W-first AWREADY", $time); end
            @(negedge clk);
            awvalid = 1'b0;
            wd = 0;
            while (!bvalid && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(超时) : W-first BVALID", $time); end
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task axil_read(input [31:0] addr, output [31:0] data);
        integer wd;
        begin
            @(negedge clk);
            araddr = addr; arvalid = 1'b1; rready = 1'b1;
            @(posedge clk);
            wd = 0;
            while (!(arvalid && arready) && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(超时) : ARREADY", $time); end
            @(negedge clk);
            arvalid = 1'b0;
            wd = 0;
            while (!rvalid && wd < WD_LIMIT) begin @(posedge clk); wd = wd + 1; end
            if (wd >= WD_LIMIT) begin n_err = n_err + 1; $display("[%0t] FAIL(超时) : RVALID", $time); end
            data = rdata;
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    reg [31:0] rd;

    initial begin
        rst_n       = 1'b0;
        awvalid     = 1'b0; wvalid = 1'b0; arvalid = 1'b0;
        bready      = 1'b0; rready = 1'b0;
        awaddr      = 32'h0; wdata = 32'h0; araddr = 32'h0; wstrb = 4'h0;
        ready_key_i = 1'b0;
        busy_i      = 1'b0;
        n_pass      = 0;
        n_err       = 0;
        load_pulses = 0;
        WD_LIMIT    = 200;

        #100;
        rst_n = 1'b1;
        #20;

        $display("=== T1 复位值 ===");
        axil_read(32'h08, rd);
        check(rd[0] === 1'b1, "T1 复位后 CTRL.MODE 应为 1（加密）");
        check(rd[1] === 1'b0, "T1 复位后 CTRL.ENABLE 应为 0");
        axil_read(32'h00, rd);
        check(rd === 32'h00000000, "T1 复位后 KEY_LO 应为 0");

        $display("=== T2 AW/W 同时到达 ===");
        axil_write(32'h00, 32'hDEADBEEF, 4'hF);
        axil_read(32'h00, rd);
        check(rd === 32'hDEADBEEF, "T2 KEY_LO 写入后读回应等于写入值");

        $display("=== T3 AW 先到、W 迟到 3 拍 ===");
        axil_write_aw_first(32'h04, 32'hCAFEF00D, 3);
        axil_read(32'h04, rd);
        check(rd === 32'hCAFEF00D, "T3 AW 先到时 KEY_HI 仍应正确写入");

        $display("=== T4 W 先到、AW 迟到 3 拍 ===");
        axil_write_w_first(32'h00, 32'h12345678, 3);
        axil_read(32'h00, rd);
        check(rd === 32'h12345678, "T4 W 先到时 KEY_LO 仍应正确写入（经典坑）");

        $display("=== T5 WSTRB 逐字节写 ===");
        axil_write(32'h00, 32'hFFFFFFFF, 4'hF);
        axil_write(32'h00, 32'hAABBCCDD, 4'b0011);   // 只写低两字节
        axil_read(32'h00, rd);
        check(rd === 32'hFFFFCCDD, "T5 WSTRB=0011 只应改低两字节");
        axil_write(32'h00, 32'h11223344, 4'b1100);   // 只写高两字节
        axil_read(32'h00, rd);
        check(rd === 32'h1122CCDD, "T5 WSTRB=1100 只应改高两字节");

        $display("=== T6 写 KEY_HI 触发一次加载 ===");
        load_pulses = 0;
        axil_write(32'h04, 32'h13579BDF, 4'hF);
        @(posedge clk);
        check(load_pulses == 1, "T6 写 KEY_HI 应恰好产生 1 个 load_key_o 脉冲");
        axil_read(32'h00, rd);
        check(rd === 32'h1122CCDD, "T6 写 KEY_HI 不应影响 KEY_LO");

        $display("=== T7 在途换钥被拒绝 ===");
        busy_i = 1'b1;
        load_pulses = 0;
        axil_write(32'h04, 32'hFFFFFFFF, 4'hF);
        @(posedge clk);
        check(load_pulses == 0, "T7 在途换钥不应产生 load_key_o 脉冲");
        axil_read(32'h0C, rd);
        check(rd[3] === 1'b1, "T7 在途换钥应置 REKEY_ERR");
        check(rd[1] === 1'b1, "T7 STATUS.BUSY 应跟随 busy_i");

        $display("=== T8 REKEY_GUARD 放行 ===");
        axil_write(32'h10, 32'h00000001, 4'hF);
        load_pulses = 0;
        axil_write(32'h04, 32'h0F0F0F0F, 4'hF);
        @(posedge clk);
        check(load_pulses == 1, "T8 GUARD=1 时在途换钥应放行");
        busy_i = 1'b0;

        $display("=== T9 CTRL.CLR_ERR 清粘滞 ===");
        axil_read(32'h0C, rd);
        check(rd[3] === 1'b1, "T9 清之前 REKEY_ERR 应仍为 1");
        axil_write(32'h08, 32'h00000007, 4'hF);   // bit0 MODE=1, bit1 ENABLE=1, bit2 CLR_ERR=1
        axil_read(32'h0C, rd);
        check(rd[3] === 1'b0, "T9 CLR_ERR 后 REKEY_ERR 应回 0");

        $display("=== T10 读通道反压 ===");
        @(negedge clk);
        araddr = 32'h00; arvalid = 1'b1; rready = 1'b0;
        @(posedge clk);
        while (!(arvalid && arready)) @(posedge clk);
        @(negedge clk);
        arvalid = 1'b0;
        while (!rvalid) @(posedge clk);
        rd = rdata;
        // RVALID 拉高后至少保持 3 拍不撤
        repeat (3) begin
            @(posedge clk);
            check(rvalid === 1'b1, "T10 RREADY=0 时 RVALID 必须保持");
            check(rdata === rd,     "T10 RREADY=0 时 RDATA 必须保持");
        end
        @(negedge clk);
        rready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rready = 1'b0;

        $display("=== T11 地址越界读 ===");
        axil_read(32'h2C, rd);
        check(rd === 32'hDEADBEEF, "T11 越界地址应返回 0xDEADBEEF");

        $display("=================================================");
        $display("  pass : %0d", n_pass);
        $display("  err  : %0d", n_err);
        if (n_err == 0) $display("  AXIL TB PASS : %0d/%0d", n_pass, n_pass);
        else            $display("  AXIL TB FAIL : pass=%0d err=%0d", n_pass, n_err);
        $display("=================================================");
        $finish;
    end

    initial begin
        #500000;
        $display("AXIL TB TIMEOUT");
        $finish;
    end

endmodule
