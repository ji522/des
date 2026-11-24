`timescale 1ns / 1ps
// =====================================================================
// des_cdc_top —— DES 16 级全流水引擎的跨时钟域封装
//
// 慢速源域（示例 100MHz）→ 异步 FIFO → 250MHz 加密域：
//   数据流：异步 FIFO（格雷码指针 + 两级同步）跨域，读侧经 1 拍
//           show-ahead 适配成 valid/ready 握手后驱动流水线
//   控制流：encrypt_i 电平跨域（2 级同步，仅在排空+换钥边界切换）
//           load_key_i 脉冲跨域（toggle 同步）
//           key_i 准静态数据跨域（源侧保持到 ready_key_o=1，
//           两域经 cdc.xdc 的 set_clock_groups 声明异步）
//   反向通道：ready_key_o 经两级同步输出 wclk 域副本 ready_key_o_wclk，
//           供慢域主设备使用（避免慢域直采快域寄存器）
//
// 协议约定：换钥/切换加解密前，源侧必须停流并等流水线排空
// （数据已在途时切换 encrypt 会破坏流的语义，与单时钟版一致）。
// =====================================================================
module des_cdc_top(
    // ---- 慢速源域（示例 100MHz）----
    input  wire        wclk,
    input  wire        wrst_n,
    input  wire        s_valid,      // 流数据有效
    input  wire [63:0] s_data,
    output wire        s_ready,      // = ~wfull（FIFO 有空间才收）
    input  wire        s_encrypt,    // 电平跨域
    input  wire        s_load_key,   // 脉冲跨域
    input  wire [63:0] s_key,        // 准静态跨域
    // ---- DES 快域（250MHz）----
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ready_i,      // 下游反压
    output wire        valid_o,
    output wire [63:0] data_o,
    output wire        ready_key_o,
    output wire        ready_key_o_wclk   // ready_key_o 的 wclk 域同步副本（供慢域主设备）
);

    wire        wfull, rempty;
    wire [63:0] fifo_rdata;
    wire        encrypt_sync;
    wire        load_key_pulse;
    wire        des_ready;
    wire        fifo_fetch;     // 从 FIFO 取一字（读指针步进 + 装载 rdata）
    wire        fifo_fire;      // DES 本拍取走 rdata
    reg         rdata_v;        // show-ahead 标志：fifo_rdata 有效

    assign s_ready = ~wfull;

    // ---------------- 控制信号跨域 ----------------
    sync_2ff #(.W(1)) u_sync_encrypt (
        .clk(clk), .rst_n(rst_n), .d(s_encrypt), .q(encrypt_sync)
    );

    toggle_sync u_sync_loadkey (
        .sclk(wclk), .srst_n(wrst_n), .pulse_in(s_load_key),
        .dclk(clk),  .drst_n(rst_n),  .pulse_out(load_key_pulse)
    );

    // 反向通道：ready_key_o（快域）→ wclk 域两级同步副本，供慢域主设备使用，
    // 避免慢域直采快域寄存器
    sync_2ff #(.W(1)) u_sync_rdykey_wclk (
        .clk(wclk), .rst_n(wrst_n), .d(ready_key_o), .q(ready_key_o_wclk)
    );

    // ---------------- 数据流跨域：异步 FIFO ----------------
    async_fifo #(.DATA_W(64), .ADDR_W(4)) u_fifo (
        .wclk(wclk), .wrst_n(wrst_n),
        .winc(s_valid & ~wfull), .wdata(s_data), .wfull(wfull),
        .rclk(clk), .rrst_n(rst_n),
        .rinc(fifo_fetch), .rdata(fifo_rdata), .rempty(rempty)
    );

    // show-ahead 适配：FIFO 读数据寄存一拍 → valid/ready
    // 取数条件：rdata 空闲 且 FIFO 非空（rempty 为保守方向，不会下溢）
    assign fifo_fetch = ~rdata_v & ~rempty;
    assign fifo_fire  = rdata_v & ready_key_o & des_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          rdata_v <= 1'b0;
        else if (fifo_fetch) rdata_v <= 1'b1;
        else if (fifo_fire)  rdata_v <= 1'b0;
    end

    // ---------------- DES 引擎（快域）----------------
    des_pipeline_fb u_des (
        .clk         (clk),
        .rst_n       (rst_n),
        .load_key_i  (load_key_pulse),
        .key_i       (s_key),          // 准静态跨域，保持到 ready_key_o
        .ready_key_o (ready_key_o),
        .encrypt_i   (encrypt_sync),
        .valid_i     (rdata_v & ready_key_o),
        .data_i      (fifo_rdata),
        .ready_i     (ready_i),
        .valid_o     (valid_o),
        .ready_o     (des_ready),
        .data_o      (data_o)
    );

endmodule
