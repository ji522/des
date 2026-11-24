`timescale 1ns / 1ps
// =====================================================================
// des_axis_cdc_top —— AXI4-Stream 封装 + 跨时钟域 的合并顶层
//
// 结构（与 des_soc_top / des_cdc_top 的区别见文件末尾对照表）：
//
//   慢域 wclk (100MHz)                快域 clk (250MHz)
//   ┌──────────────────┐            ┌──────────────────────────────┐
//   │ s_axis_tvalid    │            │ des_axis_wrap                │
//   │ s_axis_tdata[63:0]├─►async_fifo├─► (TLAST 边带 FIFO + 流水线) ├─► m_axis_*
//   │ s_axis_tlast     │  65 bit    │                              │
//   │ s_axis_tready ◄──┤  {tlast,   │ des_axil_regs (控制面)        │
//   └──────────────────┘   data}    │  └─ load_key/key/encrypt     │
//                                   └──────────────────────────────┘
//
// 关键设计决定：TLAST 必须和数据同字过域（65 位），不能另做一个 1 位异步 FIFO。
//   两个独立异步 FIFO 的读指针同步延迟各自为 2 拍且可能不同步，TLAST 会与
//   数据错位；拼进同一个字后，同一个写使能、同一个读使能、同一套格雷码指针，
//   天然对齐。过域后，TLAST 与数据的对齐由 des_axis_wrap 的边带 FIFO 继续
//   维持（那一段是单时钟，依赖流水线保序）。
//
// 控制面放在快域：des_axil_regs 直接在快域产生 load_key/key/encrypt，并用
// wrapper 的 in_flight_o 做在途换钥保护。这样不需要把控制信号跨域，也避免了
// "慢域用同步后的 busy 判断在途"导致的 2 拍滞后（那会让保护窗口不准）。
// 慢域只保留一个反向状态 ready_key_o_wclk，供慢域主设备判断"可以开始灌数"。
//
// 复位：每个域一个 reset_sync（异步 assert / 同步 deassert），域内触发器
// 统一使用本域的同步复位。
// =====================================================================
module des_axis_cdc_top (
    // ---- 慢速源域（示例 100MHz）：AXI4-Stream slave ----
    input  wire        wclk,
    input  wire        wrst_n,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [63:0] s_axis_tdata,
    input  wire        s_axis_tlast,

    // ---- 快域（250MHz）：AXI4-Lite slave（控制面）----
    input  wire        clk,
    input  wire        rst_n,
    input  wire        s_axil_awvalid,
    output wire        s_axil_awready,
    input  wire [31:0] s_axil_awaddr,
    input  wire        s_axil_wvalid,
    output wire        s_axil_wready,
    input  wire [31:0] s_axil_wdata,
    input  wire [3:0]  s_axil_wstrb,
    output wire        s_axil_bvalid,
    input  wire        s_axil_bready,
    output wire [1:0]  s_axil_bresp,
    input  wire        s_axil_arvalid,
    output wire        s_axil_arready,
    input  wire [31:0] s_axil_araddr,
    output wire        s_axil_rvalid,
    input  wire        s_axil_rready,
    output wire [31:0] s_axil_rdata,
    output wire [1:0]  s_axil_rresp,

    // ---- 快域（250MHz）：AXI4-Stream master ----
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [63:0] m_axis_tdata,
    output wire        m_axis_tlast,

    // ---- 反向状态：ready_key_o 的慢域副本 ----
    output wire        ready_key_o_wclk
);

    // ================================================================
    // 复位同步
    // ================================================================
    wire wrst_n_sync, rst_n_sync;

    reset_sync u_rst_sync_wclk (
        .clk(wclk), .arst_n(wrst_n), .srst_n(wrst_n_sync)
    );

    reset_sync u_rst_sync_clk (
        .clk(clk),  .arst_n(rst_n),  .srst_n(rst_n_sync)
    );

    // ================================================================
    // 数据面：65 位异步 FIFO（{tlast, tdata}）
    // ================================================================
    wire        wfull, rempty;
    wire [64:0] fifo_rdata;      // {tlast, tdata}
    wire        fifo_fetch;      // 把 FIFO 头字装进 rdata_r
    wire        fifo_fire;       // 该字被 wrapper 取走

    reg         rdata_v;         // show-ahead：rdata_r 里有一个有效字

    wire        axis_s_tready;   // wrapper 的输入侧 ready
    wire        axis_s_tvalid;   // 送给 wrapper 的 valid

    // 慢域：FIFO 有空间才收；写的是 {tlast, data} 同一个字
    assign s_axis_tready = ~wfull;

    async_fifo #(.DATA_W(65), .ADDR_W(4)) u_fifo (
        .wclk   (wclk),
        .wrst_n (wrst_n_sync),
        .winc   (s_axis_tvalid & ~wfull),
        .wdata  ({s_axis_tlast, s_axis_tdata}),
        .wfull  (wfull),

        .rclk   (clk),
        .rrst_n (rst_n_sync),
        .rinc   (fifo_fetch),
        .rdata  (fifo_rdata),
        .rempty (rempty)
    );

    // show-ahead 适配：FIFO 读数据寄存输出（非 FWFT），先把头字装进 rdata_r。
    // 支持"同拍 refill"：fifo_fire 的同一拍把下一字装进来，因此快域可以
    // 背靠背每拍吐一个字，不会被 show-ahead 拖成两拍一字。
    //   ~rempty 是保守方向：它说"非空"就一定有字；说"空"可能只是同步延迟。
    wire can_fetch = ~rempty;

    assign fifo_fetch = can_fetch & (~rdata_v | fifo_fire);
    assign fifo_fire  = axis_s_tvalid & axis_s_tready;

    always @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync)
            rdata_v <= 1'b0;
        else if (fifo_fire)
            rdata_v <= can_fetch;        // 同拍装了下一字 → 1；没有下一字 → 0
        else if (fifo_fetch)
            rdata_v <= 1'b1;
    end

    // ================================================================
    // 快域控制面：AXI4-Lite 寄存器块
    // ================================================================
    wire [63:0] key_f;
    wire        load_key_f;
    wire        encrypt_f;
    wire        enable_f;
    wire        ready_key_f;
    wire [5:0]  in_flight_f;

    // "在途"必须覆盖整条链路，而不只是流水线：
    //   FIFO 里还没进流水线的字、show-ahead 寄存器里的字，同样会在换钥后
    //   被新密钥处理。如果 bus_i 只取 wrapper 的 in_flight_o，软件在 FIFO
    //   非空时换钥会被误放行，那些字会用新密钥算错（静默的数据错误）。
    //   rempty / rdata_v 都在快域，不需要跨域。
    wire        fifo_has_data = ~rempty | rdata_v;
    wire        busy_any      = (|in_flight_f) | fifo_has_data;

    des_axil_regs u_regs (
        .clk            (clk),
        .rst_n          (rst_n_sync),

        .s_axil_awvalid (s_axil_awvalid),
        .s_axil_awready (s_axil_awready),
        .s_axil_awaddr  (s_axil_awaddr),
        .s_axil_wvalid  (s_axil_wvalid),
        .s_axil_wready  (s_axil_wready),
        .s_axil_wdata   (s_axil_wdata),
        .s_axil_wstrb   (s_axil_wstrb),
        .s_axil_bvalid  (s_axil_bvalid),
        .s_axil_bready  (s_axil_bready),
        .s_axil_bresp   (s_axil_bresp),
        .s_axil_arvalid (s_axil_arvalid),
        .s_axil_arready (s_axil_arready),
        .s_axil_araddr  (s_axil_araddr),
        .s_axil_rvalid  (s_axil_rvalid),
        .s_axil_rready  (s_axil_rready),
        .s_axil_rdata   (s_axil_rdata),
        .s_axil_rresp   (s_axil_rresp),

        .key_o          (key_f),
        .load_key_o     (load_key_f),
        .encrypt_o      (encrypt_f),
        .des_enable_o   (enable_f),

        .ready_key_i    (ready_key_f),
        .busy_i         (busy_any)
    );

    // ================================================================
    // 快域数据面：复用已验证的 AXI4-Stream 封装
    // ================================================================
    // 只有当密钥就绪、数据通路使能时才把字送给 wrapper。
    // 不送给它不会丢字：字停在 rdata_r / FIFO 里，FIFO 满后自然反压慢域。
    assign axis_s_tvalid = rdata_v & ready_key_f & enable_f;

    des_axis_wrap u_axis (
        .clk           (clk),
        .rst_n         (rst_n_sync),

        .s_axis_tvalid (axis_s_tvalid),
        .s_axis_tready (axis_s_tready),
        .s_axis_tdata  (fifo_rdata[63:0]),
        .s_axis_tlast  (fifo_rdata[64]),

        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tlast  (m_axis_tlast),

        .load_key_i    (load_key_f),
        .key_i         (key_f),
        .ready_key_o   (ready_key_f),
        .encrypt_i     (encrypt_f),

        .in_flight_o   (in_flight_f)
    );

    // ================================================================
    // 反向通道：ready_key_o（快域电平）→ wclk 域
    // ================================================================
    // 与 des_cdc_top 相同的"最小保持 + 两级同步"：快域先把电平结构性展宽
    // 到 RDY_HOLD 个快域周期（8×4ns=32ns > 3 个慢域周期），慢域再同步采样，
    // 避免 Ac_cdc01a（快→慢脉宽不足）。
    localparam RDY_HOLD = 8;

    reg [RDY_HOLD-1:0] rdy_cool_sr;
    reg                ready_key_f_hold;

    wire rdy_changed = (ready_key_f != ready_key_f_hold);
    wire rdy_cool    = |rdy_cool_sr;
    wire rdy_accept  = ~rdy_cool & rdy_changed;

    always @(posedge clk or negedge rst_n_sync) begin
        if (!rst_n_sync) begin
            rdy_cool_sr       <= {RDY_HOLD{1'b0}};
            ready_key_f_hold  <= 1'b0;
        end else begin
            rdy_cool_sr      <= {rdy_cool_sr[RDY_HOLD-2:0], rdy_accept};
            if (rdy_accept)
                ready_key_f_hold <= ready_key_f;
        end
    end

    sync_2ff #(.W(1)) u_sync_rdykey_wclk (
        .clk(wclk), .rst_n(wrst_n_sync),
        .d(ready_key_f_hold), .q(ready_key_o_wclk)
    );

endmodule
// =====================================================================
// 三个顶层的关系（面试口径）：
//
//   des_soc_top       单时钟 250MHz：AXIS 封装 + AXIL 控制（无 CDC）
//   des_cdc_top       双时钟 100/250MHz：裸 valid/ready 数据 + 异步 FIFO（无 AXIS）
//   des_axis_cdc_top  双时钟 + AXIS 两端：本文件（合并版）
//
// 合并版相对 des_cdc_top 的增量：
//   1) 数据口从裸 valid/ready 换成 AXI4-Stream 两端；
//   2) 异步 FIFO 从 64 位变 65 位（多 1 位 TLAST），这是 TLAST 跨域唯一的
//      正确做法；
//   3) 控制面从"慢域端口 + 三种跨域方式"改为"快域 AXIL"：控制不再跨域，
//      在途换钥判断用真实的 in_flight_o，不受同步延迟影响；
//   4) 反向只保留 ready_key_o_wclk 一个状态。
// =====================================================================
