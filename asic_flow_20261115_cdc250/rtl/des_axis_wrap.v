`timescale 1ns / 1ps
// ============================================================================
// des_axis_wrap.v
// AXI4-Stream wrapper for the 16-stage, back-pressure capable DES pipeline.
//
// Data path:
//   S_AXIS: 64-bit TDATA + TVALID/TREADY + TLAST
//   M_AXIS: 64-bit TDATA + TVALID/TREADY + TLAST
//
// TLAST is carried in a small sideband FIFO.  It is pushed on every accepted
// input beat and popped on every accepted output beat, so packet boundaries
// stay aligned with the DES pipeline even when the output is back-pressured.
//
// Key/mode control is kept as simple ports to avoid changing the verified DES
// core.  It can be driven by an AXI4-Lite register block later.
// ============================================================================
module des_axis_wrap #(
    parameter integer LAST_FIFO_AW = 5
)(
    input  wire        clk,
    input  wire        rst_n,

    // AXI4-Stream slave interface
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [63:0] s_axis_tdata,
    input  wire        s_axis_tlast,

    // AXI4-Stream master interface
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [63:0] m_axis_tdata,
    output wire        m_axis_tlast,

    // Key/mode control
    input  wire        load_key_i,
    input  wire [63:0] key_i,
    output wire        ready_key_o,
    input  wire        encrypt_i,

    // 在途拍数（= 边带 FIFO 计数，等价于已输入未输出的事务数）
    // 供 AXI4-Lite 寄存器块的 BUSY 状态位与在途换钥保护使用
    // 位宽 = LAST_FIFO_AW+1；端口列表里不能引用后面才声明的 localparam
    output wire [LAST_FIFO_AW:0] in_flight_o
);

    localparam integer LAST_FIFO_DEPTH = (1 << LAST_FIFO_AW);
    localparam integer CNT_W           = LAST_FIFO_AW + 1;
    localparam [CNT_W-1:0] LAST_FIFO_DEPTH_C = LAST_FIFO_DEPTH;

    wire        axis_ready;
    wire        des_valid_o;
    wire [63:0] des_data_o;
    wire        des_valid_i;

    wire        last_fifo_full;
    wire        in_fire;
    wire        out_fire;

    reg  [LAST_FIFO_AW-1:0] last_wr_ptr;
    reg  [LAST_FIFO_AW-1:0] last_rd_ptr;
    reg  [CNT_W-1:0]        last_count;
    reg                     last_fifo [0:LAST_FIFO_DEPTH-1];

    // A beat is accepted only when the DES is ready and the TLAST sideband
    // FIFO has room.  Gating des_valid_i as well keeps the sideband FIFO and
    // the DES data pipeline in lockstep when the FIFO is full.
    assign s_axis_tready = axis_ready && !last_fifo_full;
    assign des_valid_i   = s_axis_tvalid && !last_fifo_full;
    assign in_fire       = s_axis_tvalid && s_axis_tready;
    assign out_fire      = m_axis_tvalid && m_axis_tready;

    assign m_axis_tvalid = des_valid_o;
    assign m_axis_tdata  = des_data_o;
    assign m_axis_tlast  = (last_count != 0) ? last_fifo[last_rd_ptr] : 1'b0;

    assign last_fifo_full = (last_count == LAST_FIFO_DEPTH_C);

    assign in_flight_o = last_count;

    des_pipeline_fb u_des (
        .clk         (clk),
        .rst_n       (rst_n),
        .load_key_i  (load_key_i),
        .key_i       (key_i),
        .ready_key_o (ready_key_o),
        .encrypt_i   (encrypt_i),
        .valid_i     (des_valid_i),
        .data_i      (s_axis_tdata),
        .ready_i     (m_axis_tready),
        .valid_o     (des_valid_o),
        .ready_o     (axis_ready),
        .data_o      (des_data_o)
    );

    // Sideband TLAST FIFO.  It stores one bit per accepted input beat; DES
    // preserves beat order, so the FIFO head always matches the next output.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_wr_ptr <= {LAST_FIFO_AW{1'b0}};
            last_rd_ptr <= {LAST_FIFO_AW{1'b0}};
            last_count  <= {CNT_W{1'b0}};
        end else begin
            if (in_fire) begin
                last_fifo[last_wr_ptr] <= s_axis_tlast;
                last_wr_ptr <= last_wr_ptr + 1'b1;
            end

            if (out_fire) begin
                last_rd_ptr <= last_rd_ptr + 1'b1;
            end

            case ({in_fire, out_fire})
                2'b10:   last_count <= last_count + 1'b1;
                2'b01:   last_count <= last_count - 1'b1;
                default: last_count <= last_count;
            endcase
        end
    end

endmodule
