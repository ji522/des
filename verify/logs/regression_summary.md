# DES Regression Summary

- 时间：2026-11-24 09:39:03 +08:00
- 结论：ALL PASS

| 用例 | 判定 | 证据 |
|---|---|---|
| 0 向量生成(gen_vectors) | PASS | 固定种子 20260926，vectors/*.mem |
| 1 Verilog 定向回归(42笔) | PASS | logs/tb_des_pipeline_fb_v2.log |
| 2 换钥hazard专项 | PASS | logs/tb_rekey_hazard.log : 不排空4/4错→排空0/4 |
| 3 SV约束随机(58笔) | PASS | logs/tb_des_sv.log : 58/58、覆盖率100% |
| 4 CDC多时钟(190笔) | PASS | logs/tb_des_cdc.log : 190/190、满节流期间零丢失 |
| 5 UVM回归(58笔) | PASS | logs/tb_des_uvm.log : 3 seeds、58/58、覆盖率100%（UVM 1.2） |
| 6 AXI4-Stream封装(42笔) | PASS | logs/tb_des_axis_wrap.log : 42/42、TLAST 0 错、175 拍 stall |
| 7 AXI4-Lite寄存器(23项) | PASS | logs/tb_des_axil.log : 23/23（含 AW/W 独立到达、WSTRB、换钥保护） |
| 8 SoC集成(控制面+数据面) | PASS | logs/tb_des_soc.log : 19 项检查、13/13 对拍、在途换钥被拒 |
| 9 SVA负向(断言非空过) | PASS | logs/tb_axis_sva_neg.log : 故意违约被 A10 捕获 |
| 10 SoC UVM(双agent+RAL) | PASS | logs/tb_des_soc_uvm.log : RAL 9项、双agent、vseq、override |
