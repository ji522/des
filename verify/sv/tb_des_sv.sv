`timescale 1ns / 1ps
// ============================================================================
// tb_des_sv.sv —— SystemVerilog 验证环境顶层
//   例化 interface -> 接 DUT -> 构建 des_env -> 跑序列
// ============================================================================
module tb_des_sv;
    import des_pkg::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;     // 100 MHz

    des_if dif (.clk(clk));

    des_pipeline_fb dut (
        .clk          (dif.clk),
        .rst_n        (dif.rst_n),
        .load_key_i   (dif.load_key_i),
        .key_i        (dif.key_i),
        .ready_key_o  (dif.ready_key_o),
        .encrypt_i    (dif.encrypt_i),
        .valid_i      (dif.valid_i),
        .data_i       (dif.data_i),
        .ready_i      (dif.ready_i),
        .valid_o      (dif.valid_o),
        .ready_o      (dif.ready_o),
        .data_o       (dif.data_o)
    );

    des_env env;

    initial begin
        env = new(dif);
        env.run();
    end

    initial begin
        #500000;
        $display("** SV ENV TIMEOUT **");
        $finish;
    end
endmodule
