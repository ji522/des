`timescale 1ns / 1ps
// ============================================================================
// async_axis_fifo.v —— 65 位异步 FIFO + show-ahead AXI4-Stream 适配
//
// 写域：标准 AXIS slave，写 {tlast, tdata} 到 65 位异步 FIFO。
// 读域：show-ahead，支持同拍 refill —— 下游 ready 时背靠背每拍吐一个字。
//
// 读侧沿用 cdc/des_axis_cdc_top.v 的成熟写法：
//   ~rempty 是保守方向：它说"非空"就一定有字；说"空"可能只是同步延迟。
//   fifo_fetch = can_fetch & (~rdata_v | fifo_fire)
//   fifo_fire 的同一拍把下一字装进 rdata_v，因此不会两拍一字。
//
// 复位：wrst_n / rrst_n 必须是各自时钟域内已经同步释放的复位。
// ============================================================================
module async_axis_fifo #(
    parameter integer DATA_W = 64,
    parameter integer ADDR_W = 4
)(
    // write domain
    input  wire              wclk,
    input  wire              wrst_n,
    input  wire              s_axis_tvalid,
    output wire              s_axis_tready,
    input  wire [DATA_W-1:0] s_axis_tdata,
    input  wire              s_axis_tlast,
    output wire              wfull,

    // read domain
    input  wire              rclk,
    input  wire              rrst_n,
    output wire              m_axis_tvalid,
    input  wire              m_axis_tready,
    output wire [DATA_W-1:0] m_axis_tdata,
    output wire              m_axis_tlast,
    output wire              rempty
);

    wire [DATA_W:0] fifo_rdata;   // {tlast, tdata}
    wire            fifo_fetch;
    wire            fifo_fire;
    reg             rdata_v;

    assign s_axis_tready = ~wfull;

    async_fifo #(.DATA_W(DATA_W+1), .ADDR_W(ADDR_W)) u_fifo (
        .wclk   (wclk),
        .wrst_n (wrst_n),
        .winc   (s_axis_tvalid & ~wfull),
        .wdata  ({s_axis_tlast, s_axis_tdata}),
        .wfull  (wfull),

        .rclk   (rclk),
        .rrst_n (rrst_n),
        .rinc   (fifo_fetch),
        .rdata  (fifo_rdata),
        .rempty (rempty)
    );

    wire can_fetch = ~rempty;

    assign m_axis_tvalid = rdata_v;
    assign m_axis_tdata  = fifo_rdata[DATA_W-1:0];
    assign m_axis_tlast  = fifo_rdata[DATA_W];

    assign fifo_fire  = m_axis_tvalid && m_axis_tready;
    assign fifo_fetch = can_fetch & (~rdata_v | fifo_fire);

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n)
            rdata_v <= 1'b0;
        else if (fifo_fire)
            rdata_v <= can_fetch;      // 同拍装了下一字 → 1；没有下一字 → 0
        else if (fifo_fetch)
            rdata_v <= 1'b1;
    end

endmodule
