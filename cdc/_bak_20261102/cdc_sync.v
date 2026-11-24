`timescale 1ns / 1ps
// =====================================================================
// CDC 原语库
//  1) sync_2ff   电平信号跨域：两级同步器（快采慢，要求源电平保持
//                ≥2 个目的域周期；多比特电平总线禁止直接用，应走 FIFO）
//  2) toggle_sync 脉冲信号跨域：源域脉冲转电平翻转，目的域 2 级同步
//                后做边沿检测还原单周期脉冲（脉冲可能比目的域周期还窄，
//                直接两级同步会丢失）
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
