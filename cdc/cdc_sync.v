`timescale 1ns / 1ps
// =====================================================================
// CDC 原语库
//  1) sync_2ff   电平信号跨域：两级同步器（快采慢，要求源电平保持
//                ≥2 个目的域周期；多比特电平总线禁止直接用，应走 FIFO）
//  2) toggle_sync 脉冲信号跨域：源域脉冲转电平翻转，目的域 2 级同步
//                后做边沿检测还原单周期脉冲（脉冲可能比目的域周期还窄，
//                直接两级同步会丢失）
//  3) reset_sync 复位同步器：异步 assert（复位到来立刻生效，不等时钟）、
//                同步 deassert（释放沿经 2 级同步，避免不同触发器在
//                复位释放沿附近进入亚稳态）——Spyglass Ar_unsync01 要求
//                每个时钟域内的异步复位都必须经由本域复位同步器
// =====================================================================

module sync_2ff #(
    parameter W = 1
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire [W-1:0] d,
    output wire [W-1:0] q
);
    (* ASYNC_REG = "TRUE" *) reg [W-1:0] ff1, ff2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ff1 <= {W{1'b0}};
            ff2 <= {W{1'b0}};
        end else begin
            ff1 <= d;
            ff2 <= ff1;
        end
    end

    assign q = ff2;
endmodule


module toggle_sync (
    input  wire sclk,       // 源域时钟
    input  wire srst_n,
    input  wire pulse_in,   // 源域单周期脉冲
    input  wire dclk,       // 目的域时钟
    input  wire drst_n,
    output wire pulse_out   // 目的域还原出的单周期脉冲
);
    // 源域：脉冲 → 电平翻转
    reg toggle;
    always @(posedge sclk or negedge srst_n) begin
        if (!srst_n)    toggle <= 1'b0;
        else if (pulse_in) toggle <= ~toggle;
    end

    // 目的域：2 级同步 + 边沿检测
    (* ASYNC_REG = "TRUE" *) reg [1:0] sync_ff;
    reg toggle_d;
    always @(posedge dclk or negedge drst_n) begin
        if (!drst_n) begin
            sync_ff  <= 2'b00;
            toggle_d <= 1'b0;
        end else begin
            sync_ff  <= {sync_ff[0], toggle};
            toggle_d <= sync_ff[1];
        end
    end

    assign pulse_out = sync_ff[1] ^ toggle_d;
endmodule


// ---------------------------------------------------------------------
// reset_sync —— 异步 assert / 同步 deassert 复位同步器
//   arst_n 拉低：两级触发器被异步清零，srst_n 立即拉低（不等时钟沿）；
//   arst_n 释放：1 经两级触发器同步，srst_n 在目的域连续采到 2 个 1
//                之后才释放，保证本域所有触发器在同一时钟沿退出复位，
//                不会在复位释放沿附近采到亚稳态。
//   本模块的输出只能驱动"同一个 clk 域"内触发器的异步复位端。
// ---------------------------------------------------------------------
module reset_sync (
    input  wire clk,
    input  wire arst_n,     // 异步复位，低有效
    output wire srst_n      // 同步释放后的复位
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] sync;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) sync <= 2'b00;
        else         sync <= {sync[0], 1'b1};
    end

    assign srst_n = sync[1];
endmodule
