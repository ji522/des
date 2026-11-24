`timescale 1ns / 1ps
// 带 valid/ready 反压握手的 DES 轮级。
// 采用标准"单级可反压流水寄存器"：数据一旦被本级持有（valid_o=1），
// 只有 downstream 拉高 ready_i 才会被取走；否则本级 stall(hold)，
// 并通过 ready_o=0 把反压向上游传播。支持任意上游/下游速率，不丢数据。
module des_pipe_round_fb(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_i,      // 上游数据有效
    input  wire        ready_i,      // 下游反压信号：1=下游可接收
    input  wire [31:0] L_i,
    input  wire [31:0] R_i,
    input  wire [47:0] subkey_i,
    output reg         valid_o,
    output wire        ready_o,      // 给上游的反压：0=上游请别灌
    output reg  [31:0] L_o,
    output reg  [31:0] R_o
);

    // ---- 数据通路（组合逻辑，与原版一致）----
    wire [47:0] expanded_R = {
        R_i[0], R_i[31], R_i[30], R_i[29], R_i[28], R_i[27], R_i[28], R_i[27],
        R_i[26], R_i[25], R_i[24], R_i[23], R_i[24], R_i[23], R_i[22], R_i[21],
        R_i[20], R_i[19], R_i[20], R_i[19], R_i[18], R_i[17], R_i[16], R_i[15],
        R_i[16], R_i[15], R_i[14], R_i[13], R_i[12], R_i[11], R_i[12], R_i[11],
        R_i[10], R_i[9], R_i[8], R_i[7], R_i[8], R_i[7], R_i[6], R_i[5],
        R_i[4], R_i[3], R_i[4], R_i[3], R_i[2], R_i[1], R_i[0], R_i[31]
    };
    wire [47:0] xored_R = expanded_R ^ subkey_i;

    wire [31:0] sbox_out;
    assign sbox_out[31:28] = s1_func(xored_R[47:42]);
    assign sbox_out[27:24] = s2_func(xored_R[41:36]);
    assign sbox_out[23:20] = s3_func(xored_R[35:30]);
    assign sbox_out[19:16] = s4_func(xored_R[29:24]);
    assign sbox_out[15:12] = s5_func(xored_R[23:18]);
    assign sbox_out[11:8]  = s6_func(xored_R[17:12]);
    assign sbox_out[7:4]   = s7_func(xored_R[11:6]);
    assign sbox_out[3:0]   = s8_func(xored_R[5:0]);

    wire [31:0] pbox_out = {
        sbox_out[16], sbox_out[25], sbox_out[12], sbox_out[11], sbox_out[3], sbox_out[20], sbox_out[4], sbox_out[15],
        sbox_out[31], sbox_out[17], sbox_out[9], sbox_out[6], sbox_out[27], sbox_out[14], sbox_out[1], sbox_out[22],
        sbox_out[30], sbox_out[24], sbox_out[8], sbox_out[18], sbox_out[0], sbox_out[5], sbox_out[29], sbox_out[23],
        sbox_out[13], sbox_out[19], sbox_out[2], sbox_out[26], sbox_out[10], sbox_out[21], sbox_out[28], sbox_out[7]
    };
    wire [31:0] next_R = L_i ^ pbox_out;

    // ---- 反压握手 ----
    // 本级"被下游取走"：valid_o=1 且 ready_i=1
    // 本级"stall / 反压"：valid_o=1 且 ready_i=0 -> hold 数据 + 反压上游
    // ready_o：本级为空 或 下游要取走 -> 允许上游灌新数据
    wire        stall  = valid_o & ~ready_i;
    assign ready_o     = ~valid_o | ready_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_o <= 1'b0;
            L_o     <= 32'd0;
            R_o     <= 32'd0;
        end else if (!stall) begin
            // 不反压：本级或被取空、或接收新数据
            if (valid_i) begin
                L_o     <= R_i;
                R_o     <= next_R;
                valid_o <= 1'b1;
            end else begin
                valid_o <= 1'b0;
            end
        end
        // stall 时：valid_o / L_o / R_o 全部保持（反压 hold）
    end

`include "sbox_funcs.v"
endmodule
