`timescale 1ns / 1ps
// =====================================================================
// 异步 FIFO（双时钟域，Cummings 式经典结构）
//  - 两侧各自维护二进制读写指针，跨域前转格雷码（每次只变 1 位）
//  - 指针经 2 级同步器（ASYNC_REG）进入对端域
//  - 空：读格雷指针 == 同步过来的写格雷指针
//  - 满：写格雷指针下一态 == 同步过来的读格雷指针（最高两位取反）
//  - 深度必须为 2 的幂（格雷码回绕性质决定）
//  - 读数据寄存输出（非 FWFT），由上层用 rdata_v 标志做 show-ahead 适配
// =====================================================================
module async_fifo #(
    parameter DATA_W = 64,
    parameter ADDR_W = 4              // 深度 = 16
)(
    // 写域
    input  wire               wclk,
    input  wire               wrst_n,
    input  wire               winc,     // 写使能（满时写被忽略）
    input  wire [DATA_W-1:0]  wdata,
    output wire               wfull,
    // 读域
    input  wire               rclk,
    input  wire               rrst_n,
    input  wire               rinc,     // 读使能（空时读被忽略）
    output wire [DATA_W-1:0]  rdata,
    output wire               rempty
);

    localparam DEPTH = 1 << ADDR_W;

    // ---------------- 指针与同步寄存器 ----------------
    reg  [ADDR_W:0] wbin, wgray;      // 写域指针（多 1 位用于区分满/空）
    reg  [ADDR_W:0] rbin, rgray;      // 读域指针
    (* ASYNC_REG = "TRUE" *) reg [ADDR_W:0] rgray_sync1, rgray_sync2; // 读指针 → 写域
    (* ASYNC_REG = "TRUE" *) reg [ADDR_W:0] wgray_sync1, wgray_sync2; // 写指针 → 读域

    wire [ADDR_W:0] wbin_next  = wbin + (winc & ~wfull);
    wire [ADDR_W:0] wgray_next = (wbin_next >> 1) ^ wbin_next;
    wire [ADDR_W:0] rbin_next  = rbin + (rinc & ~rempty);
    wire [ADDR_W:0] rgray_next = (rbin_next >> 1) ^ rbin_next;

    // 满：同步来的读指针"落后于"真实读指针（保守方向，不会溢出），
    //     最高两位取反 = 写指针比读指针整整多绕一圈
    wire wfull_val = (wgray_next == {~rgray_sync2[ADDR_W:ADDR_W-1], rgray_sync2[ADDR_W-2:0]});
    // 空：弹出一拍后读格雷指针追上同步来的写格雷指针
    wire rempty_val = (rgray_next == wgray_sync2);

    reg wfull_r, rempty_r;
    assign wfull  = wfull_r;
    assign rempty = rempty_r;

    // ---------------- 存储：双端口分布式 RAM（写 wclk / 读 rclk） ----------------
    // ram_style 显式钉死 distributed：小深度 CDC FIFO 必须落在 LUTRAM（异步读、
    // 无 BRAM CLK-to-Q 延迟）。不指定时 Vivado 会映射成 BRAM 并把读侧预取寄存器
    // 吸收进 BRAM 内置输出寄存器，导致 BRAM 输出 → 流水线第一级的 250MHz 路径
    // 违例（cdc/_signoff 报告实测：WNS -0.256，加属性后收敛）。
    (* ram_style = "distributed" *) reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg  [DATA_W-1:0] rdata_r;
    assign rdata = rdata_r;

    // ---------------- 写域 ----------------
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin       <= {(ADDR_W+1){1'b0}};
            wgray      <= {(ADDR_W+1){1'b0}};
            rgray_sync1 <= {(ADDR_W+1){1'b0}};
            rgray_sync2 <= {(ADDR_W+1){1'b0}};
            wfull_r    <= 1'b0;
        end else begin
            wbin        <= wbin_next;
            wgray       <= wgray_next;
            rgray_sync1 <= rgray;
            rgray_sync2 <= rgray_sync1;
            wfull_r     <= wfull_val;
        end
    end

    always @(posedge wclk) begin
        if (winc & ~wfull)
            mem[wbin[ADDR_W-1:0]] <= wdata;
    end

    // ---------------- 读域 ----------------
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin        <= {(ADDR_W+1){1'b0}};
            rgray       <= {(ADDR_W+1){1'b0}};
            wgray_sync1 <= {(ADDR_W+1){1'b0}};
            wgray_sync2 <= {(ADDR_W+1){1'b0}};
            rempty_r    <= 1'b1;
        end else begin
            rbin        <= rbin_next;
            rgray       <= rgray_next;
            wgray_sync1 <= wgray;
            wgray_sync2 <= wgray_sync1;
            rempty_r    <= rempty_val;
        end
    end

    // 读数据寄存输出（数据寄存器不需要复位：由 rinc/~rempty 门控，不会误发）
    always @(posedge rclk) begin
        if (rinc & ~rempty)
            rdata_r <= mem[rbin[ADDR_W-1:0]];
    end

endmodule
