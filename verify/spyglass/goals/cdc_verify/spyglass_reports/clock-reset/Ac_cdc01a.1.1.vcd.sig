verification_cycle
des_cdc_top.wclk
wf_signal_group -name "Destination Clock" -signals {des_cdc_top.wclk}
des_cdc_top.ready_key_o
wf_signal_group -name "Destination Input" -signals {des_cdc_top.ready_key_o}
des_cdc_top.clk
wf_signal_group -name "Source Clock" -signals {des_cdc_top.clk}
des_cdc_top.u_sync_rdykey_wclk.ff1
wf_signal_group -name "Destination Output" -signals {des_cdc_top.u_sync_rdykey_wclk.ff1}
