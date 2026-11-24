# ============================================================================
# des.sdc —— DES SoC 前端约束（2026-11-08 修订版）
#
# 相比 10-31 版的改动：
#   1. clock uncertainty 拆成 setup / hold 两档（原来 0.10 对 hold 也生效，
#      在理想零偏斜时钟下凭空造出 771 条 -3.8ps 的假 hold 违例）
#   2. rst_n 不再当作普通数据输入加 2ns input delay
#   3. 补输入驱动建模 set_driving_cell（原输入斜率是理想的 0）
#   4. 补 clock transition 与 design rule（max_transition 取库默认 0.1985ns）
# ============================================================================

set clk_period 10.0
create_clock -name clk -period $clk_period [get_ports clk]

# --- 时钟不确定度：setup 与 hold 分开 ---
# setup 0.10：目标偏斜 + 抖动预留（pre-CTS 经验值）
# hold  0.05：pre-CTS 保守值；CTS 后换成 set_propagated_clock 再收紧
set_clock_uncertainty -setup 0.10 [get_clocks clk]
set_clock_uncertainty -hold  0.05 [get_clocks clk]

# --- 时钟转换时间（pre-CTS 建模）---
set_clock_transition 0.05 [get_clocks clk]

# --- IO 时序预算 ---
# 注意：2.0ns 是占位假设（约 20% 周期），真实值应来自系统接口预算。
set clk_coll  [get_ports clk]
set rst_coll  [get_ports rst_n]
set data_in   [remove_from_collection [remove_from_collection [all_inputs] $clk_coll] $rst_coll]

set_input_delay  2.0 -clock clk $data_in
set_output_delay 2.0 -clock clk [all_outputs]
set_load 0.02 [all_outputs]

# --- 输入驱动建模 ---
# 原来所有输入斜率都是理想的 0，输入侧路径（含被当作"关键路径"的
# m_axis_tready -> s_axis_tready）因此偏乐观。用 Nangate45 的 BUF_X2 代表前级驱动。
set_driving_cell -lib_cell BUF_X2 -pin Z $data_in

# --- 设计规则 ---
# 0.198535ns 是库的 default_max_transition，直接沿用，不自己编。
set_max_transition 0.198535 [current_design]


# --- 复位 ---
# rst_n 只驱动 des_soc_top 内部两级复位同步器的异步复位端。
# 异步置位本身不需要时序检查；同步器输出 rst_n_sync 到下游 1200+ 个
# 异步清零端的 recovery / removal 走正常时序路径，会被检查。
set_false_path -from $rst_coll

# ----------------------------------------------------------------------------
# 关于 removal 报出的 243 条 -0.0998ns（刻意保留，不 waive）
#
# PrimeTime 对异步控制端默认做“同沿”recovery/removal 检查：
#   arrival  = rst_sync_r_reg CK->Q 0.2588 + 网络 0.0394 = 0.2982ns
#   required = hold uncertainty 0.05 + 库 removal time 0.3480 = 0.3980ns
#   slack    = -0.0998ns
# 同步释放的复位只能在时钟沿之后（CK->Q）才翻转，而同沿检查要求它在沿之前
# 0.348ns 就稳定，所以这个负值在拓扑上必然出现。物理上，下游触发器在那一拍
# 看到的仍是复位有效，复位撤销要到下一个时钟沿才被采样，实际余量约 9.3ns。
# PT O-2018.06 没有跨沿检查开关（timing_recovery_removal_checks_at_same_edge
# 不是该版本的应用变量），能“消掉”它的只有 set_false_path —— 但那等于把刚
# 检查起来的复位路径又关掉。这里选择保留可见、在报告里说明。
# ----------------------------------------------------------------------------

