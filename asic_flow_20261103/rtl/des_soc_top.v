`timescale 1ns / 1ps
// ============================================================================
// des_soc_top.v —— DES 的完整可集成形态
//
// 数据面：AXI4-Stream（64bit TDATA + TVALID/TREADY/TLAST）
// 控制面：AXI4-Lite（密钥、模式、使能、状态）
//
// 这是原来 des_axis_wrap.v 头注释里那句 "It can be driven by an AXI4-Lite
// register block later" 的落地版本。wrapper 本身一行未改，只是把它和寄存器块
// 拼在这一层，控制面从裸端口换成总线。
//
// 换钥保护：寄存器块拿 in_flight_o 判断在途与否，在途时拒绝换钥并置
// REKEY_ERR —— 把原来只能靠"验证环境强制排空"规避的约束，下沉成了 RTL 行为。
// ============================================================================
module des_soc_top (
    input  wire        clk,
    input  wire        rst_n,

    // ---- AXI4-Stream slave（数据入）----
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [63:0] s_axis_tdata,
    input  wire        s_axis_tlast,

    // ---- AXI4-Stream master（数据出）----
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [63:0] m_axis_tdata,
    output wire        m_axis_tlast,

    // ---- AXI4-Lite slave（控制面）----
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
    output wire [1:0]  s_axil_rresp
);

    wire [63:0] key_w;
    wire        load_key_w;
    wire        encrypt_w;
    wire        enable_w;
    wire        ready_key_w;
    wire [5:0]  in_flight_w;    // LAST_FIFO_AW=5 → 计数位宽 6

    des_axil_regs u_regs (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axil_awvalid (s_axil_awvalid), .s_axil_awready(s_axil_awready), .s_axil_awaddr(s_axil_awaddr),
        .s_axil_wvalid  (s_axil_wvalid),  .s_axil_wready (s_axil_wready),  .s_axil_wdata (s_axil_wdata),
        .s_axil_wstrb   (s_axil_wstrb),
        .s_axil_bvalid  (s_axil_bvalid),  .s_axil_bready (s_axil_bready),  .s_axil_bresp (s_axil_bresp),
        .s_axil_arvalid (s_axil_arvalid), .s_axil_arready(s_axil_arready), .s_axil_araddr(s_axil_araddr),
        .s_axil_rvalid  (s_axil_rvalid),  .s_axil_rready (s_axil_rready),  .s_axil_rdata (s_axil_rdata),
        .s_axil_rresp   (s_axil_rresp),
        .key_o          (key_w),
        .load_key_o     (load_key_w),
        .encrypt_o      (encrypt_w),
        .des_enable_o   (enable_w),
        .ready_key_i    (ready_key_w),
        .busy_i         (|in_flight_w)
    );

    // ENABLE=0 时把输入 valid 挡掉，数据通路空转但不接收新数据。
    // tready 必须同步门控：否则出现"tready=1 但数据被丢弃"，
    // 违反 AXI4-Stream —— 握手成功就必须接收。
    wire axis_in_valid = s_axis_tvalid && enable_w;
    wire axis_in_ready;
    assign s_axis_tready = axis_in_ready && enable_w;

    des_axis_wrap #(.LAST_FIFO_AW(5)) u_axis (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axis_tvalid (axis_in_valid),
        .s_axis_tready (axis_in_ready),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tlast  (s_axis_tlast),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tlast  (m_axis_tlast),
        .load_key_i    (load_key_w),
        .key_i         (key_w),
        .ready_key_o   (ready_key_w),
        .encrypt_i     (encrypt_w),
        .in_flight_o   (in_flight_w)
    );

endmodule
