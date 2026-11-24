`timescale 1ns / 1ps

module des_pipe_round(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_i,
    input  wire [31:0] L_i,
    input  wire [31:0] R_i,
    input  wire [47:0] subkey_i,
    output reg         valid_o,
    output reg  [31:0] L_o,
    output reg  [31:0] R_o
);

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_o <= 1'b0;
            L_o     <= 32'd0;
            R_o     <= 32'd0;
        end else begin
            valid_o <= valid_i;
            if (valid_i) begin
                L_o <= R_i;       
                R_o <= next_R;    
            end
        end
    end

    function [3:0] s1_func;
        input [5:0] in;
           case(in)
	    0: s1_func = (14); 
        1: s1_func = (0); 
        2: s1_func = (4); 
        3: s1_func = (15); 
        4: s1_func = (13); 
        5: s1_func = (7); 
        6: s1_func = (1); 
        7: s1_func = (4); 
        8: s1_func = (2); 
        9: s1_func = (14); 
        10: s1_func = (15); 
        11: s1_func = (2); 
        12: s1_func = (11); 
        13: s1_func = (13); 
        14: s1_func = (8); 
        15: s1_func = (1); 
        16: s1_func = (3); 
        17: s1_func = (10); 
        18: s1_func = (10); 
        19: s1_func = (6); 
        20: s1_func = (6); 
        21: s1_func = (12); 
        22: s1_func = (12); 
        23: s1_func = (11); 
        24: s1_func = (5); 
        25: s1_func = (9); 
        26: s1_func = (9); 
        27: s1_func = (5); 
        28: s1_func = (0); 
        29: s1_func = (3); 
        30: s1_func = (7); 
        31: s1_func = (8); 
        32: s1_func = (4); 
        33: s1_func = (15); 
        34: s1_func = (1); 
        35: s1_func = (12); 
        36: s1_func = (14); 
        37: s1_func = (8); 
        38: s1_func = (8); 
        39: s1_func = (2); 
        40: s1_func = (13); 
        41: s1_func = (4); 
        42: s1_func = (6); 
        43: s1_func = (9); 
        44: s1_func = (2); 
        45: s1_func = (1); 
        46: s1_func = (11); 
        47: s1_func = (7); 
        48: s1_func = (15); 
        49: s1_func = (5); 
        50: s1_func = (12); 
        51: s1_func = (11); 
        52: s1_func = (9); 
        53: s1_func = (3); 
        54: s1_func = (7); 
        55: s1_func = (14); 
        56: s1_func = (3); 
        57: s1_func = (10); 
        58: s1_func = (10); 
        59: s1_func = (0); 
        60: s1_func = (5); 
        61: s1_func = (6); 
        62: s1_func = (0); 
        63: s1_func = (13); 
    
   endcase
    endfunction

    function [3:0] s2_func;
        input [5:0] in;
           case(in)
        0: s2_func = (15); 
        1: s2_func = (3); 
        2: s2_func = (1); 
        3: s2_func = (13); 
        4: s2_func = (8); 
        5: s2_func = (4); 
        6: s2_func = (14); 
        7: s2_func = (7); 
        8: s2_func = (6); 
        9: s2_func = (15); 
        10: s2_func = (11); 
        11: s2_func = (2); 
        12: s2_func = (3); 
        13: s2_func = (8); 
        14: s2_func = (4); 
        15: s2_func = (14); 
        16: s2_func = (9); 
        17: s2_func = (12); 
        18: s2_func = (7); 
        19: s2_func = (0); 
        20: s2_func = (2); 
        21: s2_func = (1); 
        22: s2_func = (13); 
        23: s2_func = (10); 
        24: s2_func = (12); 
        25: s2_func = (6); 
        26: s2_func = (0); 
        27: s2_func = (9); 
        28: s2_func = (5); 
        29: s2_func = (11); 
        30: s2_func = (10); 
        31: s2_func = (5); 
        32: s2_func = (0); 
        33: s2_func = (13); 
        34: s2_func = (14); 
        35: s2_func = (8); 
        36: s2_func = (7); 
        37: s2_func = (10); 
        38: s2_func = (11); 
        39: s2_func = (1); 
        40: s2_func = (10); 
        41: s2_func = (3); 
        42: s2_func = (4); 
        43: s2_func = (15); 
        44: s2_func = (13); 
        45: s2_func = (4); 
        46: s2_func = (1); 
        47: s2_func = (2); 
        48: s2_func = (5); 
        49: s2_func = (11); 
        50: s2_func = (8); 
        51: s2_func = (6); 
        52: s2_func = (12); 
        53: s2_func = (7); 
        54: s2_func = (6); 
        55: s2_func = (12); 
        56: s2_func = (9); 
        57: s2_func = (0); 
        58: s2_func = (3); 
        59: s2_func = (5); 
        60: s2_func = (2); 
        61: s2_func = (14); 
        62: s2_func = (15); 
        63: s2_func = (9); 
   
  endcase
    endfunction

    function [3:0] s3_func;
        input [5:0] in;
           case(in)

        0: s3_func = (10); 
        1: s3_func = (13); 
        2: s3_func = (0); 
        3: s3_func = (7); 
        4: s3_func = (9); 
        5: s3_func = (0); 
        6: s3_func = (14); 
        7: s3_func = (9); 
        8: s3_func = (6); 
        9: s3_func = (3); 
        10: s3_func = (3); 
        11: s3_func = (4); 
        12: s3_func = (15); 
        13: s3_func = (6); 
        14: s3_func = (5); 
        15: s3_func = (10); 
        16: s3_func = (1); 
        17: s3_func = (2); 
        18: s3_func = (13); 
        19: s3_func = (8); 
        20: s3_func = (12); 
        21: s3_func = (5); 
        22: s3_func = (7); 
        23: s3_func = (14); 
        24: s3_func = (11); 
        25: s3_func = (12); 
        26: s3_func = (4); 
        27: s3_func = (11); 
        28: s3_func = (2); 
        29: s3_func = (15); 
        30: s3_func = (8); 
        31: s3_func = (1); 
        32: s3_func = (13); 
        33: s3_func = (1); 
        34: s3_func = (6); 
        35: s3_func = (10); 
        36: s3_func = (4); 
        37: s3_func = (13); 
        38: s3_func = (9); 
        39: s3_func = (0); 
        40: s3_func = (8); 
        41: s3_func = (6); 
        42: s3_func = (15); 
        43: s3_func = (9); 
        44: s3_func = (3); 
        45: s3_func = (8); 
        46: s3_func = (0); 
        47: s3_func = (7); 
        48: s3_func = (11); 
        49: s3_func = (4); 
        50: s3_func = (1); 
        51: s3_func = (15); 
        52: s3_func = (2); 
        53: s3_func = (14); 
        54: s3_func = (12); 
        55: s3_func = (3); 
        56: s3_func = (5); 
        57: s3_func = (11); 
        58: s3_func = (10); 
        59: s3_func = (5); 
        60: s3_func = (14); 
        61: s3_func = (2); 
        62: s3_func = (7); 
        63: s3_func = (12); 
  
   endcase
    endfunction

    function [3:0] s4_func;
        input [5:0] in;
           case(in)

        0: s4_func = (7); 
        1: s4_func = (13); 
        2: s4_func = (13); 
        3: s4_func = (8); 
        4: s4_func = (14); 
        5: s4_func = (11); 
        6: s4_func = (3); 
        7: s4_func = (5); 
        8: s4_func = (0); 
        9: s4_func = (6); 
        10: s4_func = (6); 
        11: s4_func = (15); 
        12: s4_func = (9); 
        13: s4_func = (0); 
        14: s4_func = (10); 
        15: s4_func = (3); 
        16: s4_func = (1); 
        17: s4_func = (4); 
        18: s4_func = (2); 
        19: s4_func = (7); 
        20: s4_func = (8); 
        21: s4_func = (2); 
        22: s4_func = (5); 
        23: s4_func = (12); 
        24: s4_func = (11); 
        25: s4_func = (1); 
        26: s4_func = (12); 
        27: s4_func = (10); 
        28: s4_func = (4); 
        29: s4_func = (14); 
        30: s4_func = (15); 
        31: s4_func = (9); 
        32: s4_func = (10); 
        33: s4_func = (3); 
        34: s4_func = (6); 
        35: s4_func = (15); 
        36: s4_func = (9); 
        37: s4_func = (0); 
        38: s4_func = (0); 
        39: s4_func = (6); 
        40: s4_func = (12); 
        41: s4_func = (10); 
        42: s4_func = (11); 
        43: s4_func = (1); 
        44: s4_func = (7); 
        45: s4_func = (13); 
        46: s4_func = (13); 
        47: s4_func = (8); 
        48: s4_func = (15); 
        49: s4_func = (9); 
        50: s4_func = (1); 
        51: s4_func = (4); 
        52: s4_func = (3); 
        53: s4_func = (5); 
        54: s4_func = (14); 
        55: s4_func = (11); 
        56: s4_func = (5); 
        57: s4_func = (12); 
        58: s4_func = (2); 
        59: s4_func = (7); 
        60: s4_func = (8); 
        61: s4_func = (2); 
        62: s4_func = (4); 
        63: s4_func = (14); 

   endcase
    endfunction

    function [3:0] s5_func;
        input [5:0] in;
           case(in)

        0: s5_func = (2); 
        1: s5_func = (14); 
        2: s5_func = (12); 
        3: s5_func = (11); 
        4: s5_func = (4); 
        5:s5_func = (2); 
        6: s5_func = (1); 
        7: s5_func = (12); 
        8: s5_func = (7); 
        9: s5_func = (4); 
        10: s5_func = (10); 
        11: s5_func = (7); 
        12: s5_func = (11); 
        13: s5_func = (13); 
        14: s5_func = (6); 
        15: s5_func= (1); 
        16: s5_func = (8); 
        17: s5_func = (5); 
        18: s5_func = (5); 
        19: s5_func = (0); 
        20: s5_func = (3); 
        21: s5_func = (15); 
        22: s5_func = (15); 
        23: s5_func = (10); 
        24: s5_func = (13); 
        25: s5_func = (3); 
        26: s5_func = (0); 
        27: s5_func = (9); 
        28: s5_func = (14); 
        29: s5_func = (8); 
        30: s5_func = (9); 
        31: s5_func = (6); 
        32: s5_func= (4); 
        33: s5_func = (11); 
        34: s5_func = (2); 
        35: s5_func = (8); 
        36: s5_func = (1); 
        37: s5_func = (12); 
        38: s5_func = (11); 
        39: s5_func = (7); 
        40: s5_func = (10); 
        41: s5_func = (1); 
        42: s5_func = (13); 
        43: s5_func = (14); 
        44: s5_func = (7); 
        45: s5_func = (2); 
        46: s5_func = (8); 
        47: s5_func = (13); 
        48: s5_func= (15); 
        49: s5_func = (6); 
        50: s5_func = (9); 
        51: s5_func= (15); 
        52: s5_func = (12); 
        53: s5_func = (0); 
        54: s5_func = (5); 
        55: s5_func = (9); 
        56: s5_func = (6); 
        57: s5_func = (10); 
        58: s5_func = (3); 
        59: s5_func = (4); 
        60: s5_func = (0); 
        61: s5_func = (5); 
        62: s5_func = (14); 
        63: s5_func = (3); 

   endcase
    endfunction

    function [3:0] s6_func;
        input [5:0] in;
           case(in)

        0: s6_func = (12); 
        1: s6_func = (10); 
        2: s6_func = (1); 
        3: s6_func = (15); 
        4: s6_func = (10); 
        5: s6_func = (4); 
        6: s6_func = (15); 
        7: s6_func = (2); 
        8: s6_func = (9); 
        9: s6_func = (7); 
        10: s6_func = (2); 
        11: s6_func = (12); 
        12: s6_func = (6); 
        13: s6_func = (9); 
        14: s6_func = (8); 
        15: s6_func = (5); 
        16: s6_func = (0); 
        17: s6_func = (6); 
        18: s6_func = (13); 
        19: s6_func = (1); 
        20: s6_func = (3); 
        21: s6_func = (13); 
        22: s6_func = (4); 
        23: s6_func = (14); 
        24: s6_func = (14); 
        25: s6_func = (0); 
        26: s6_func = (7); 
        27: s6_func = (11); 
        28: s6_func = (5); 
        29: s6_func = (3); 
        30: s6_func = (11); 
        31: s6_func = (8); 
        32: s6_func = (9); 
        33: s6_func = (4); 
        34: s6_func = (14); 
        35: s6_func = (3); 
        36: s6_func = (15); 
        37: s6_func = (2); 
        38: s6_func = (5); 
        39: s6_func = (12); 
        40: s6_func = (2); 
        41: s6_func = (9); 
        42: s6_func = (8); 
        43: s6_func = (5); 
        44: s6_func = (12); 
        45: s6_func = (15); 
        46: s6_func = (3); 
        47: s6_func = (10); 
        48: s6_func = (7); 
        49: s6_func = (11); 
        50: s6_func = (0); 
        51: s6_func = (14); 
        52: s6_func = (4); 
        53: s6_func = (1); 
        54: s6_func = (10); 
        55: s6_func = (7); 
        56: s6_func = (1); 
        57: s6_func = (6); 
        58: s6_func = (13); 
        59: s6_func = (0); 
        60: s6_func = (11); 
        61: s6_func = (8); 
        62: s6_func = (6); 
        63: s6_func = (13); 

   endcase
    endfunction

    function [3:0] s7_func;
        input [5:0] in;
           case(in)

        0: s7_func = (4); 
        1: s7_func = (13); 
        2: s7_func = (11); 
        3: s7_func = (0); 
        4: s7_func = (2); 
        5: s7_func = (11); 
        6: s7_func = (14); 
        7: s7_func = (7); 
        8: s7_func = (15); 
        9: s7_func = (4); 
        10: s7_func = (0); 
        11: s7_func = (9); 
        12: s7_func = (8); 
        13: s7_func = (1); 
        14: s7_func = (13); 
        15: s7_func = (10); 
        16: s7_func = (3); 
        17: s7_func = (14); 
        18: s7_func = (12); 
        19: s7_func = (3); 
        20: s7_func = (9); 
        21: s7_func = (5); 
        22: s7_func = (7); 
        23: s7_func = (12); 
        24: s7_func = (5); 
        25: s7_func = (2); 
        26: s7_func = (10); 
        27: s7_func = (15); 
        28: s7_func = (6); 
        29: s7_func = (8); 
        30: s7_func = (1); 
        31: s7_func = (6); 
        32: s7_func = (1); 
        33: s7_func = (6); 
        34: s7_func = (4); 
        35: s7_func = (11); 
        36: s7_func = (11); 
        37: s7_func = (13); 
        38: s7_func = (13); 
        39: s7_func = (8); 
        40: s7_func = (12); 
        41: s7_func = (1); 
        42: s7_func = (3); 
        43: s7_func = (4); 
        44: s7_func = (7); 
        45: s7_func = (10); 
        46: s7_func = (14); 
        47: s7_func = (7); 
        48: s7_func = (10); 
        49: s7_func = (9); 
        50: s7_func = (15); 
        51: s7_func = (5); 
        52: s7_func = (6); 
        53: s7_func = (0); 
        54: s7_func = (8); 
        55: s7_func = (15); 
        56: s7_func = (0); 
        57: s7_func = (14); 
        58: s7_func = (5); 
        59: s7_func = (2); 
        60: s7_func = (9); 
        61: s7_func = (3); 
        62: s7_func = (2); 
        63: s7_func = (12); 

   endcase
    endfunction

    function [3:0] s8_func;
        input [5:0] in;
           case(in)

        0: s8_func = (13); 
        1: s8_func = (1); 
        2: s8_func = (2); 
        3: s8_func = (15); 
        4: s8_func = (8); 
        5: s8_func = (13); 
        6: s8_func = (4); 
        7: s8_func = (8); 
        8: s8_func = (6); 
        9: s8_func = (10); 
        10: s8_func = (15); 
        11: s8_func = (3); 
        12: s8_func = (11); 
        13: s8_func = (7); 
        14: s8_func = (1); 
        15: s8_func = (4); 
        16: s8_func = (10); 
        17: s8_func = (12); 
        18: s8_func = (9); 
        19: s8_func = (5); 
        20: s8_func = (3); 
        21: s8_func = (6); 
        22: s8_func = (14); 
        23: s8_func = (11); 
        24: s8_func = (5); 
        25: s8_func = (0); 
        26: s8_func = (0); 
        27: s8_func = (14); 
        28: s8_func = (12); 
        29: s8_func = (9); 
        30: s8_func = (7); 
        31: s8_func = (2); 
        32: s8_func = (7); 
        33: s8_func = (2); 
        34: s8_func = (11); 
        35: s8_func = (1); 
        36: s8_func = (4); 
        37: s8_func = (14); 
        38: s8_func = (1); 
        39: s8_func = (7); 
        40: s8_func = (9); 
        41: s8_func = (4); 
        42: s8_func = (12); 
        43: s8_func = (10); 
        44: s8_func = (14); 
        45: s8_func = (8); 
        46: s8_func = (2); 
        47: s8_func = (13); 
        48: s8_func = (0); 
        49: s8_func = (15); 
        50: s8_func = (6); 
        51: s8_func = (12); 
        52: s8_func = (10); 
        53: s8_func = (9); 
        54: s8_func = (13); 
        55: s8_func = (0); 
        56: s8_func = (15); 
        57: s8_func = (3); 
        58: s8_func = (3); 
        59: s8_func = (5); 
        60: s8_func = (5); 
        61: s8_func = (6); 
        62: s8_func = (8); 
        63: s8_func = (11); 

   endcase
    endfunction


endmodule
