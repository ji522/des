`timescale 1ns / 1ps
// 带 valid/ready 反压握手的 16 级全流水 DES。
// 数据通路与原版一致（16 级 generate + LUTRAM 无关，子密钥由 key_ram_gen 预计算进寄存器堆）。
// 新增：每级 `des_pipe_round_fb` 为可反压握手寄存器，反压从末级(ready_i)逐级向前传播到 ready_o。
// 上游持续灌入而下游不 ready 时，流水线内部自动 hold，数据不丢（即防止 overflow）。
module des_pipeline_fb(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        load_key_i,
    input  wire [63:0] key_i,
    output wire        ready_key_o,   // 密钥就绪（来自 key_ram_gen）

    input  wire        encrypt_i,

    input  wire        valid_i,
    input  wire [63:0] data_i,
    input  wire        ready_i,       // 下游反压：0=下游满，请停
    output wire        valid_o,
    output wire        ready_o,       // 给上游的反压
    output wire [63:0] data_o
);

    wire [767:0] round_keys_flat;
    key_ram_gen u_key_ram_gen(
        .clk            (clk            ),
        .rst_n          (rst_n          ),
        .load_key_i     (load_key_i     ),
        .key_i          (key_i          ),
        .keys_ready_o   (ready_key_o    ),
        .round_keys_o   (round_keys_flat)
    );

    // 初始置换 IP（纯位连线，与原版一致）
    wire [31:0] L_init = {
        data_i[6], data_i[14], data_i[22], data_i[30], data_i[38], data_i[46], data_i[54], data_i[62],
        data_i[4], data_i[12], data_i[20], data_i[28], data_i[36], data_i[44], data_i[52], data_i[60],
        data_i[2], data_i[10], data_i[18], data_i[26], data_i[34], data_i[42], data_i[50], data_i[58],
        data_i[0], data_i[8], data_i[16], data_i[24], data_i[32], data_i[40], data_i[48], data_i[56]
    };
    wire [31:0] R_init = {
        data_i[7], data_i[15], data_i[23], data_i[31], data_i[39], data_i[47], data_i[55], data_i[63],
        data_i[5], data_i[13], data_i[21], data_i[29], data_i[37], data_i[45], data_i[53], data_i[61],
        data_i[3], data_i[11], data_i[19], data_i[27], data_i[35], data_i[43], data_i[51], data_i[59],
        data_i[1], data_i[9], data_i[17], data_i[25], data_i[33], data_i[41], data_i[49], data_i[57]
    };

    // 数据 / 有效 / 反压 逐级链路。v[0]=valid_i；rd[0]=本模块 ready_o，rd[16]=ready_i。
    wire [31:0] L [0:16];
    wire [31:0] R [0:16];
    wire        v [0:16];
    wire        rd [0:16];

    assign L[0]  = L_init;
    assign R[0]  = R_init;
    assign v[0]  = valid_i;
    assign rd[16]= ready_i;             // 下游反压进入末级

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : pipe_stages
            wire [4:0]  key_idx     = !encrypt_i ? (15 - i) : i;
            wire [47:0] current_key = round_keys_flat[(key_idx*48) +: 48];

            des_pipe_round_fb u_round(
                .clk      (clk          ),
                .rst_n    (rst_n        ),
                .valid_i  (v[i]         ),
                .ready_i  (rd[i+1]      ),   // 本级的下游反压
                .L_i      (L[i]         ),
                .R_i      (R[i]         ),
                .subkey_i (current_key  ),
                .valid_o  (v[i+1]       ),
                .ready_o  (rd[i]        ),   // 反压传给上一级
                .L_o      (L[i+1]       ),
                .R_o      (R[i+1]       )
            );
        end
    endgenerate

    // 末置换 FP（纯位连线，与原版一致）
    wire [63:0] pre_out     = {R[16], L[16]};
    wire [63:0] data_o_wire = {
        pre_out[24], pre_out[56], pre_out[16], pre_out[48], pre_out[8], pre_out[40], pre_out[0], pre_out[32],
        pre_out[25], pre_out[57], pre_out[17], pre_out[49], pre_out[9], pre_out[41], pre_out[1], pre_out[33],
        pre_out[26], pre_out[58], pre_out[18], pre_out[50], pre_out[10], pre_out[42], pre_out[2], pre_out[34],
        pre_out[27], pre_out[59], pre_out[19], pre_out[51], pre_out[11], pre_out[43], pre_out[3], pre_out[35],
        pre_out[28], pre_out[60], pre_out[20], pre_out[52], pre_out[12], pre_out[44], pre_out[4], pre_out[36],
        pre_out[29], pre_out[61], pre_out[21], pre_out[53], pre_out[13], pre_out[45], pre_out[5], pre_out[37],
        pre_out[30], pre_out[62], pre_out[22], pre_out[54], pre_out[14], pre_out[46], pre_out[6], pre_out[38],
        pre_out[31], pre_out[63], pre_out[23], pre_out[55], pre_out[15], pre_out[47], pre_out[7], pre_out[39]
    };

    assign data_o   = data_o_wire;
    assign valid_o  = v[16];
    assign ready_o  = rd[0];            // 反压最终给上游

endmodule
