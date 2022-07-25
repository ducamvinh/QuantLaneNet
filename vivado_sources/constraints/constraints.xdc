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

# PCIe reset
set_property IOSTANDARD LVCMOS18 [get_ports pcie_perstn]
set_property PULLUP true [get_ports pcie_perstn]
set_property PACKAGE_PIN AV35 [get_ports pcie_perstn]

# PCIe clock
set_property PACKAGE_PIN AB8 [get_ports {pcie_refclk_clk_p}]
set_property PACKAGE_PIN AB7 [get_ports {pcie_refclk_clk_n}]

# LEDs
set_property IOSTANDARD LVCMOS18 [get_ports {led_8bits[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_8bits[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_8bits[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_8bits[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_8bits[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_8bits[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_8bits[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_8bits[7]}]
set_property PACKAGE_PIN AM39 [get_ports {led_8bits[0]}]
set_property PACKAGE_PIN AN39 [get_ports {led_8bits[1]}]
set_property PACKAGE_PIN AR37 [get_ports {led_8bits[2]}]
set_property PACKAGE_PIN AT37 [get_ports {led_8bits[3]}]
set_property PACKAGE_PIN AR35 [get_ports {led_8bits[4]}]
set_property PACKAGE_PIN AP41 [get_ports {led_8bits[5]}]
set_property PACKAGE_PIN AP42 [get_ports {led_8bits[6]}]
set_property PACKAGE_PIN AU39 [get_ports {led_8bits[7]}]

###############################################################################
# Timing Constraints
###############################################################################

# PCIe clock
create_clock -period 10.000 -name pcie_refclk_clk_p [get_ports pcie_refclk_clk_p]

# PCIe reset
set_false_path -from [get_ports pcie_perstn]
