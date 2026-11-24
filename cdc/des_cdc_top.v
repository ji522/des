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
//   反向通道：ready_key_o（快域电平）→ wclk 域副本 ready_key_o_wclk。
//           快域先过一个"最小保持"展宽器：电平每次变化后至少保持
//           RDY_HOLD 个 clk 周期（8×4ns=32ns > 3 个 wclk 周期），慢域再
//           用两级同步器采这个已保证稳定的电平。这样跨域源每次变化
//           都维持足够宽度，慢域不会整拍漏采（Ac_cdc01a）。
//
//   复位：每个域各一个 reset_sync（异步 assert / 同步 deassert），
//         域内所有触发器统一用本域的 wrst_n_sync / rst_n_sync。
//         顶层的 wrst_n / rst_n 是对外端口，只喂给两个同步器。
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

    // ---------------- 复位：各域独立同步（异步 assert / 同步 deassert）----------------
    // 顶层 wrst_n / rst_n 保持原样，域内一律使用同步后的版本，避免复位释放沿
    // 直接落到各触发器造成复位撤离不同步（Spyglass Ar_unsync01）。
    wire        wrst_n_sync, rst_n_sync;

    reset_sync u_rst_sync_wclk (
        .clk(wclk), .arst_n(wrst_n), .srst_n(wrst_n_sync)
    );

    reset_sync u_rst_sync_clk (
        .clk(clk),  .arst_n(rst_n),  .srst_n(rst_n_sync)
    );

    assign s_ready = ~wfull;

    // ---------------- 控制信号跨域 ----------------
    sync_2ff #(.W(1)) u_sync_encrypt (
        .clk(clk), .rst_n(rst_n_sync), .d(s_encrypt), .q(encrypt_sync)
    );

    toggle_sync u_sync_loadkey (
        .sclk(wclk), .srst_n(wrst_n_sync), .pulse_in(s_load_key),
        .dclk(clk),  .drst_n(rst_n_sync),  .pulse_out(load_key_pulse)
    );

    // ---------------- 反向通道：ready_key_o（快域）→ wclk 域 ----------------
    // 直接两级同步电平会违反 Ac_cdc01a：ready_key_o 在快域可能只保持
    // 1 个 clk 周期（4ns），慢域 10ns 周期在极端情况下会整拍漏采。
    //
    // 方案：快域先做"最小保持宽度"展宽，再交给 wclk 域两级同步器。
    //   rdy_changed = 最新值 与 已发值 不同
    //   rdy_cool_sr = 冷却移位链：每接受一次新值就在链头置 1，之后每拍右移；
    //                 链非零期间不再接受新值，输出保持稳定
    // 由此 ready_key_o_hold 每次更新后至少保持 RDY_HOLD 个快域周期
    // （8 × 4ns = 32ns > 3 个 wclk 周期），慢域两级同步必能采到。
    // 冷却窗口内的输入变化会被略过（窗口结束后重新采样最新值），
    // 对 ready_key_o 这种换钥边界上的准静态状态（key_ram_gen 的 READY
    // 状态至少持续到下一次 load_key，远长于 8 个快域周期）不丢有效值。
    //
    // 选择理由（相对"数据+toggle+ack 握手"）：
    //   1) 改动最小：只加 9 个触发器，复用现有 sync_2ff，接口不变；
    //   2) 不新增慢→快回程路径，不引入新的跨域分析条目；
    //   3) 源信号被结构性展宽，Spyglass 的 Fast->Slow 保持检查可直接证明，
    //      不需要先证明一个握手协议；
    //   4) 最坏情况只是副本更新晚 8 个快域周期（32ns），而这个副本本身
    //      已经比快域信号晚 2 个慢域周期，对使用者的语义无影响。
    localparam RDY_HOLD = 8;

    reg [RDY_HOLD-1:0] rdy_cool_sr;
    reg                ready_key_o_hold;

    wire rdy_changed = (ready_key_o != ready_key_o_hold);
    wire rdy_cool    = |rdy_cool_sr;
    wire rdy_accept  = ~rdy_cool & rdy_changed;   // 空闲且有待发新值 → 接受

    always @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync) begin
            rdy_cool_sr      <= {RDY_HOLD{1'b0}};
            ready_key_o_hold <= 1'b0;
        end else begin
            rdy_cool_sr      <= {rdy_cool_sr[RDY_HOLD-2:0], rdy_accept};
            if (rdy_accept)
                ready_key_o_hold <= ready_key_o;
        end
    end

    sync_2ff #(.W(1)) u_sync_rdykey_wclk (
        .clk(wclk), .rst_n(wrst_n_sync), .d(ready_key_o_hold), .q(ready_key_o_wclk)
    );

    // ---------------- 数据流跨域：异步 FIFO ----------------
    async_fifo #(.DATA_W(64), .ADDR_W(4)) u_fifo (
        .wclk(wclk), .wrst_n(wrst_n_sync),
        .winc(s_valid & ~wfull), .wdata(s_data), .wfull(wfull),
        .rclk(clk), .rrst_n(rst_n_sync),
        .rinc(fifo_fetch), .rdata(fifo_rdata), .rempty(rempty)
    );

    // show-ahead 适配：FIFO 读数据寄存一拍 → valid/ready
    // 取数条件：rdata 空闲 且 FIFO 非空（rempty 为保守方向，不会下溢）
    assign fifo_fetch = ~rdata_v & ~rempty;
    assign fifo_fire  = rdata_v & ready_key_o & des_ready;

    always @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync)     rdata_v <= 1'b0;
        else if (fifo_fetch) rdata_v <= 1'b1;
        else if (fifo_fire)  rdata_v <= 1'b0;
    end

    // ---------------- DES 引擎（快域）----------------
    des_pipeline_fb u_des (
        .clk         (clk),
        .rst_n       (rst_n_sync),
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
