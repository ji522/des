`timescale 1ns / 1ps

module key_ram_gen(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         load_key_i,      
    input  wire [63:0]  key_i,           
    output reg          keys_ready_o,    
    output wire [767:0] round_keys_o     
);

    localparam IDLE  = 2'd0;
    localparam CALC  = 2'd1;
    localparam READY = 2'd2;

    reg [1:0] state, next_state;
    reg [3:0] round_cnt;               

    (* rom_style = "distributed" *)
    reg [47:0] key_ram [0:15];

    reg [27:0] C_reg, D_reg;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_round_keys
            assign round_keys_o[(i*48)+:48] = key_ram[i];
        end
    endgenerate

    wire [1:0] shift_amt;
    assign shift_amt = (round_cnt == 0 || round_cnt == 1 || round_cnt == 8 || round_cnt == 15) ? 2'd1 : 2'd2;

    wire [27:0] pc1_C = {
        key_i[7], key_i[15], key_i[23], key_i[31], key_i[39], key_i[47], key_i[55], key_i[63],
        key_i[6], key_i[14], key_i[22], key_i[30], key_i[38], key_i[46], key_i[54], key_i[62],
        key_i[5], key_i[13], key_i[21], key_i[29], key_i[37], key_i[45], key_i[53], key_i[61],
        key_i[4], key_i[12], key_i[20], key_i[28]
    };
    wire [27:0] pc1_D = {
        key_i[1], key_i[9], key_i[17], key_i[25], key_i[33], key_i[41], key_i[49], key_i[57],
        key_i[2], key_i[10], key_i[18], key_i[26], key_i[34], key_i[42], key_i[50], key_i[58],
        key_i[3], key_i[11], key_i[19], key_i[27], key_i[35], key_i[43], key_i[51], key_i[59],
        key_i[36], key_i[44], key_i[52], key_i[60]
    };

    wire [27:0] next_C = (shift_amt == 2'd1) ? {C_reg[26:0], C_reg[27]} : {C_reg[25:0], C_reg[27:26]};
    wire [27:0] next_D = (shift_amt == 2'd1) ? {D_reg[26:0], D_reg[27]} : {D_reg[25:0], D_reg[27:26]};

    wire [55:0] cd_merged = {next_C, next_D};
    wire [47:0] pc2_out = {
        cd_merged[42], cd_merged[39], cd_merged[45], cd_merged[32], cd_merged[55], cd_merged[51], cd_merged[53], cd_merged[28],
        cd_merged[41], cd_merged[50], cd_merged[35], cd_merged[46], cd_merged[33], cd_merged[37], cd_merged[44], cd_merged[52],
        cd_merged[30], cd_merged[48], cd_merged[40], cd_merged[49], cd_merged[29], cd_merged[36], cd_merged[43], cd_merged[54],
        cd_merged[15], cd_merged[4], cd_merged[25], cd_merged[19], cd_merged[9], cd_merged[1], cd_merged[26], cd_merged[16],
        cd_merged[5], cd_merged[11], cd_merged[23], cd_merged[8], cd_merged[12], cd_merged[7], cd_merged[17], cd_merged[0],
        cd_merged[22], cd_merged[3], cd_merged[10], cd_merged[14], cd_merged[6], cd_merged[20], cd_merged[27], cd_merged[24]
    };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            round_cnt    <= 4'd0;
            keys_ready_o <= 1'b0;
            C_reg        <= 28'd0;
            D_reg        <= 28'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (load_key_i) begin
                        state        <= CALC;
                        round_cnt    <= 4'd0;
                        keys_ready_o <= 1'b0;
                        C_reg        <= pc1_C;
                        D_reg        <= pc1_D;
                    end
                end

                CALC: begin
                    C_reg <= next_C;
                    D_reg <= next_D;
                    key_ram[round_cnt] <= pc2_out;
                    if (round_cnt == 4'd15) begin
                        state        <= READY;
                        keys_ready_o <= 1'b1;
                    end else begin
                        round_cnt <= round_cnt + 1'b1;
                    end
                end

                READY: begin
                    if (load_key_i) begin
                        state        <= CALC;
                        round_cnt    <= 4'd0;
                        keys_ready_o <= 1'b0;
                        C_reg        <= pc1_C;
                        D_reg        <= pc1_D;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
