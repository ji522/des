# =====================================================================
# cdc.xdc —— des_cdc_top 跨时钟域时序约束
# wclk / clk 为两个异步主时钟（真实集成中 clk 常来自 PLL，届时需按
# generated clock 调整约束对象）。CDC 签署语义：set_clock_groups 声明两域
# 异步，全部跨域路径退出建立/保持分析；同步器结构正确性由 report_cdc
# 结构检查 + RTL 内 ASYNC_REG 属性保证；s_key 准静态总线由源端保持协议
# 保证（见 des_cdc_top.v 头注释）。
# =====================================================================

create_clock -period 10.000 -name wclk [get_ports wclk]
create_clock -period 4.000  -name clk  [get_ports clk]

# 两域异步：跨域路径全部退出 STA（含格雷码指针、FIFO 存储、同步器第一级）
set_clock_groups -asynchronous -group [get_clocks wclk] -group [get_clocks clk]

# 备选语义（与 clock_groups 不混用）：跨域路径仅约束 datapath 延迟、豁免 hold，
# 适合需要限制同拍总线 skew 的场合：
# set_max_delay -datapath_only -from [get_clocks wclk] -to [get_clocks clk] 4.000
# set_max_delay -datapath_only -from [get_clocks clk] -to [get_clocks wclk] 4.000

# 同步器寄存器的 ASYNC_REG 属性已在 RTL 中声明（async_fifo.v / cdc_sync.v）
