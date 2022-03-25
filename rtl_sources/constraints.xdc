###############################################################################
# User Physical Constraints
###############################################################################

# BPI
set_property BITSTREAM.CONFIG.BPI_SYNC_MODE Type1 [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN div-1 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design]
set_property CONFIG_MODE BPI16 [current_design]
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]

# Reset
set_property IOSTANDARD LVCMOS18 [get_ports sys_rst_n]
set_property PULLUP true [get_ports sys_rst_n]
set_property PACKAGE_PIN AV35 [get_ports sys_rst_n]

# Clock
set_property LOC IBUFDS_GTE2_X1Y5 [get_cells {design_1_i/util_ds_buf_0/U0/USE_IBUFDS_GTE2.GEN_IBUFDS_GTE2[0].IBUFDS_GTE2_I}]

# LEDs
set_property IOSTANDARD LVCMOS18 [get_ports {leds[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[7]}]
set_property PACKAGE_PIN AM39 [get_ports {leds[0]}]
set_property PACKAGE_PIN AN39 [get_ports {leds[1]}]
set_property PACKAGE_PIN AR37 [get_ports {leds[2]}]
set_property PACKAGE_PIN AT37 [get_ports {leds[3]}]
set_property PACKAGE_PIN AR35 [get_ports {leds[4]}]
set_property PACKAGE_PIN AP41 [get_ports {leds[5]}]
set_property PACKAGE_PIN AP42 [get_ports {leds[6]}]
set_property PACKAGE_PIN AU39 [get_ports {leds[7]}]

###############################################################################
# Timing Constraints
###############################################################################

# Clock
create_clock -period 10.000 -name sys_clk [get_ports pcie_diff_clk_p]

# Reset
set_false_path -from [get_ports sys_rst_n]
