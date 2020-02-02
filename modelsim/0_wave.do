onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider usb_phy
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/rst_ni
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/clk_i
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/usb_tx_oe_o
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/usb_dp_pull_up_en_o
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/usb_dm_pull_up_en_o
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/usb_rx_dp_i
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/usb_rx_dm_i
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/usb_tx_dp_o
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/usb_tx_dm_o
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/rx_data_o
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/rx_den_o
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/rx_packet_st_o
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/rx_packet_ed_o
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/rx_se0_det_o
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/rx_se1_det_o
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/tx_data_i
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/tx_den_i
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/tx_busy_o
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_rx_clk_en
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_rx_clk_en_cntr
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_usb_rx_dp_d
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_usb_rx_dm_d
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_rx_chg_det
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_rx_chg_det_1d
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_rx_data
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_pre_rx_symbol_window
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_rx_symbol_window
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_sync_det
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_eop_det
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_rx_bit_window
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_rx_bit_stuff_den
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_tx_data_1d
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_tx_den_1d
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_tx_en
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_tx_next_state
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_tx_state
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_tx_buf_wait
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_tx_buf_den
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_tx_buf_data
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_tx_buf_empty
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_tx_attach_cntr
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_tx_bit_window
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_tx_ins_bit_stuff
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/u_usb_phy/s_tx_bus_data
add wave -noupdate -divider <NULL>
add wave -noupdate -divider <NULL>
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/rst_ni
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/clk_i
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/sim_en_i
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/usb_dp
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/usb_dm
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/s_data
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/s_den
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/s_sim_en_1d
add wave -noupdate /TB_USB1_IF_TOP/u_tb_usb_phy/s_sim_en_cntr
add wave -noupdate -divider <NULL>
add wave -noupdate -divider BENCH_TOP
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1157003469 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ps} {3675 us}
