`timescale 1ns/1ps
// ============================================================================
// tb_des_uvm.sv —— UVM 验证平台顶层
//   例化 interface -> 接 DUT -> vif 进 config_db -> run_test
// ============================================================================
`include "uvm_macros.svh"

module tb_des_uvm;
    import uvm_pkg::*;
    import des_uvm_pkg::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

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

    initial begin
        uvm_config_db#(virtual des_if)::set(null, "uvm_test_top*", "vif", dif);
        run_test("des_rand_test");
    end

    initial begin
        #2000000;
        `uvm_fatal("TIMEOUT", "UVM 仿真超时")
        $finish;
    end
endmodule
