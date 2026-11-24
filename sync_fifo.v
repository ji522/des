`timescale 1ns / 1ps
// ============================================================================
// sync_fifo.v —— 单时钟同步 FIFO（带计数、几乎满/空、溢出/下溢脉冲）
//
// 用途：2 通道 AXIS 仲裁器的每通道缓冲。存 {tlast, tdata}，深度 2^ADDR_W。
//  - 写满时若同拍有读，允许写入（利用刚腾出的位置），不丢吞吐；
//  - dout 为组合读出（小深度 LUTRAM/寄存器实现，适合 16~32 深）；
//  - almost_full/almost_empty 阈值由外部给出，便于 AXI-Lite 动态配置。
// ============================================================================
module sync_fifo #(
    parameter integer DATA_W = 65,
    parameter integer ADDR_W = 4
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire                 wr_en,
    input  wire [DATA_W-1:0]    din,
    output wire                 full,
    output wire                 almost_full,

    input  wire                 rd_en,
    output wire [DATA_W-1:0]    dout,
    output wire                 empty,
    output wire                 almost_empty,

    output wire [ADDR_W:0]      count,
    output wire                 overflow_pulse,
    output wire                 underflow_pulse,

    input  wire [ADDR_W:0]      almost_full_thresh,
    input  wire [ADDR_W:0]      almost_empty_thresh
);

    localparam integer DEPTH = (1 << ADDR_W);

    reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] rd_ptr;
    reg [ADDR_W:0]   count_r;

    wire do_read  = rd_en && (count_r != 0);
    wire do_write = wr_en && ((count_r != DEPTH) || do_read);

    assign full          = (count_r == DEPTH);
    assign empty         = (count_r == 0);
    assign almost_full   = (count_r >= almost_full_thresh);
    assign almost_empty  = (count_r <= almost_empty_thresh);
    assign dout          = mem[rd_ptr];
    assign count         = count_r;

    // 只统计真正“想写但没空间/想读但空”的拍，供性能监控用
    assign overflow_pulse  = wr_en && (count_r == DEPTH) && !do_read;
    assign underflow_pulse = rd_en && (count_r == 0);

    always @(posedge clk) begin
        if (do_write)
            mem[wr_ptr] <= din;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr  <= {ADDR_W{1'b0}};
            rd_ptr  <= {ADDR_W{1'b0}};
            count_r <= {(ADDR_W+1){1'b0}};
        end else begin
            if (do_write) wr_ptr <= wr_ptr + 1'b1;
            if (do_read)  rd_ptr <= rd_ptr + 1'b1;
            count_r <= count_r + (do_write ? 1'b1 : 1'b0)
                               - (do_read  ? 1'b1 : 1'b0);
        end
    end

endmodule
