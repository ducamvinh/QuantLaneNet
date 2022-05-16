# Process arguments
set gui_idx [lsearch -exact $argv "gui"]

# Check error
if {$argc > 2 || ($argc == 2 && $gui_idx < 0)} {
    puts "\[ERROR\] Invalid arguments. Expected project path and \"gui\"."
    exit
}

# Set project path
if {($gui_idx >= 0 && $argc == 1) || $argc == 0} {
    set project_dir [file join [file dirname $argv0] "../vivado_project"]
} else {
    set project_dir [lindex $argv [expr {$gui_idx < 0 ? 0 : (-$gui_idx + 1)}]]
}

# Set run mode
if {$gui_idx >= 0} {
    set run_mode "gui"
} else {
    set run_mode "terminal"
}

# Set other paths
set rtl_dir [file join [file dirname $argv0] "../rtl_sources"]
set ip_repo_dir [file join $project_dir "ip_repo"]

############################################### Create project ###############################################
create_project LaneDetectionCNN $project_dir -part xc7vx485tffg1761-2
set_property board_part xilinx.com:vc707:part0:1.4 [current_project]

if {$run_mode == "gui"} {
    start_gui
}

############################################### Create & edit IP ###############################################
puts "\n########################### Creating IP ###########################\n"
create_peripheral user.org user LaneDetectionCNN 1.0 -dir $ip_repo_dir
ipx::edit_ip_in_project -quiet -upgrade true -name edit_LaneDetectionCNN_v1_0 -directory $ip_repo_dir [file join $ip_repo_dir "LaneDetectionCNN_1.0/component.xml"]
add_files -force -norecurse -copy_to [file join $ip_repo_dir "LaneDetectionCNN_1.0/src"] [glob -directory $rtl_dir *.v]
set_property top LaneDetectionCNN_AXI_IP [current_fileset]
update_compile_order -fileset sources_1

# Infer AXI core from sources
ipx::infer_core -vendor user.org -library user -taxonomy /UserIP [file join $ip_repo_dir "LaneDetectionCNN_1.0/src"]

# Set parameters as un-editable
set_property widget {textEdit} [ipgui::get_guiparamspec -name "C_S00_AXI_DATA_WIDTH" -component [ipx::current_core] ]
set_property enablement_value false [ipx::get_user_parameters "C_S00_AXI_DATA_WIDTH" -of_objects [ipx::current_core]]
set_property widget {textEdit} [ipgui::get_guiparamspec -name "C_S00_AXI_ADDR_WIDTH" -component [ipx::current_core] ]
set_property enablement_value false [ipx::get_user_parameters "C_S00_AXI_ADDR_WIDTH" -of_objects [ipx::current_core]]

# Add bus interface parameters
ipx::add_bus_parameter "FREQ_HZ" [ipx::get_bus_interfaces s00_axi_aclk -of_objects [ipx::current_core]]
ipx::add_bus_parameter "PHASE" [ipx::get_bus_interfaces s00_axi_aclk -of_objects [ipx::current_core]]

# Repackage and save IP
ipx::merge_project_changes files [ipx::current_core]
set_property previous_version_for_upgrade ::: [ipx::find_open_core user.org:user:LaneDetectionCNN_AXI_IP:1.0]
set_property core_revision 1 [ipx::find_open_core user.org:user:LaneDetectionCNN_AXI_IP:1.0]
ipx::create_xgui_files [ipx::find_open_core user.org:user:LaneDetectionCNN_AXI_IP:1.0]
ipx::update_checksums [ipx::find_open_core user.org:user:LaneDetectionCNN_AXI_IP:1.0]
ipx::check_integrity [ipx::find_open_core user.org:user:LaneDetectionCNN_AXI_IP:1.0]
ipx::save_core [ipx::find_open_core user.org:user:LaneDetectionCNN_AXI_IP:1.0]

# Close edit_ip project and update IP catalog
close_project -delete
set_property ip_repo_paths [file join $ip_repo_dir "LaneDetectionCNN_1.0/src"] [current_project]
update_ip_catalog

############################################### Create block design ###############################################
puts "\n########################### Creating block design ###########################\n"
create_bd_design "design_1"

# XDMA
create_bd_cell -type ip -vlnv xilinx.com:ip:xdma xdma_0
set_property -dict [list CONFIG.pl_link_cap_max_link_width {X1} CONFIG.pl_link_cap_max_link_speed {5.0_GT/s} CONFIG.axisten_freq {250} CONFIG.pf0_device_id {7021} CONFIG.plltype {QPLL1} CONFIG.PF0_DEVICE_ID_mqdma {9021} CONFIG.PF2_DEVICE_ID_mqdma {9021} CONFIG.PF3_DEVICE_ID_mqdma {9021}] [get_bd_cells xdma_0]

# Clock buffer
create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf util_ds_buf_0
set_property -dict [list CONFIG.C_BUF_TYPE {IBUFDSGTE}] [get_bd_cells util_ds_buf_0]

# Lane detection CNN IP
create_bd_cell -type ip -vlnv user.org:user:LaneDetectionCNN_AXI_IP LaneDetectionCNN_AXI_0

# Connect nets
connect_bd_net [get_bd_pins util_ds_buf_0/IBUF_OUT] [get_bd_pins xdma_0/sys_clk]
make_bd_pins_external [get_bd_pins xdma_0/sys_rst_n]
set_property name pcie_perstn [get_bd_ports sys_rst_n_0]
make_bd_intf_pins_external [get_bd_intf_pins util_ds_buf_0/CLK_IN_D]
set_property name pcie_refclk [get_bd_intf_ports CLK_IN_D_0]
make_bd_intf_pins_external [get_bd_intf_pins xdma_0/pcie_mgt]
set_property name pci_express_x1 [get_bd_intf_ports pcie_mgt_0]

# FPGA 200 MHz clock
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clk_wiz_0
apply_board_connection -board_interface "sys_diff_clock" -ip_intf "clk_wiz_0/CLK_IN1_D" -diagram "design_1" 
set_property -dict [list CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000}] [get_bd_cells clk_wiz_0]

# Connect AXI interfaces
apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {reset ( FPGA Reset ) } Manual_Source {New External Port (ACTIVE_HIGH)}}  [get_bd_pins clk_wiz_0/reset]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {/xdma_0/axi_aclk (250 MHz)} Clk_slave {/clk_wiz_0/clk_out1 (200 MHz)} Clk_xbar {/xdma_0/axi_aclk (250 MHz)} Master {/xdma_0/M_AXI} Slave {/LaneDetectionCNN_AXI_0/s00_axi} ddr_seg {Auto} intc_ip {New AXI Interconnect} master_apm {0}}  [get_bd_intf_pins LaneDetectionCNN_AXI_0/s00_axi]

# Set AXI address map
set_property offset 0x00000000C0000000 [get_bd_addr_segs {xdma_0/M_AXI/SEG_LaneDetectionCNN_AXI_0_reg0}]
set_property range 1M [get_bd_addr_segs {xdma_0/M_AXI/SEG_LaneDetectionCNN_AXI_0_reg0}]

############################################### Create logic for signal leds ###############################################

create_bd_cell -type hier signal_leds
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant signal_leds/xlconstant_0
set_property -dict [list CONFIG.CONST_VAL {0}] [get_bd_cells signal_leds/xlconstant_0]

# Create counters to make clock leds
for {set i 0} {$i < 3} {incr i} {
    # Binary counter
    create_bd_cell -type ip -vlnv xilinx.com:ip:c_counter_binary signal_leds/c_counter_binary_$i
    set_property -dict [list CONFIG.Output_Width {25}] [get_bd_cells signal_leds/c_counter_binary_$i]

    # Slice block
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice signal_leds/xlslice_$i
    set_property -dict [list CONFIG.DIN_TO {24} CONFIG.DIN_FROM {24} CONFIG.DIN_WIDTH {25} CONFIG.DOUT_WIDTH {1}] [get_bd_cells signal_leds/xlslice_$i] 
    
    # Connect counter to slice block
    connect_bd_net [get_bd_pins signal_leds/c_counter_binary_$i/Q] [get_bd_pins signal_leds/xlslice_$i/Din]
}

# Connect counter clock sources
connect_bd_net [get_bd_pins signal_leds/c_counter_binary_0/CLK] [get_bd_pins util_ds_buf_0/IBUF_OUT]
connect_bd_net [get_bd_pins signal_leds/c_counter_binary_1/CLK] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins signal_leds/c_counter_binary_2/CLK] [get_bd_pins clk_wiz_0/clk_out1]

# Create concat block for leds
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat signal_leds/xlconcat_0
set_property -dict [list CONFIG.NUM_PORTS {8}] [get_bd_cells signal_leds/xlconcat_0]

# Connect concat block's inputs
set led_signals {
    signal_leds/xlslice_0/Dout
    signal_leds/xlslice_1/Dout
    signal_leds/xlslice_2/Dout
    xdma_0/user_lnk_up
    signal_leds/xlconstant_0/dout    
    LaneDetectionCNN_AXI_0/wr_led
    LaneDetectionCNN_AXI_0/rd_led
    LaneDetectionCNN_AXI_0/busy
}

for {set i 0} {$i < 8} {incr i} {
    connect_bd_net [get_bd_pins [lindex $led_signals $i]] [get_bd_pins signal_leds/xlconcat_0/In$i]  
}

# Make concat block's output external
make_bd_pins_external  [get_bd_pins signal_leds/xlconcat_0/dout]
set_property name led_8bits [get_bd_ports dout_0]

############################################### Finish building project ###############################################
puts "\n########################### Validate and save block design ###########################\n"

# Validate and save block design
validate_bd_design
save_bd_design

# Create HDL wrapper
make_wrapper -files [get_files [file join $project_dir "LaneDetectionCNN.srcs/sources_1/bd/design_1/design_1.bd"]] -top
add_files -norecurse [file join $project_dir "LaneDetectionCNN.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v"]

# Add constraints
add_files -fileset constrs_1 -force -norecurse -copy_to [file join $project_dir "LaneDetectionCNN.srcs/constrs_1/new"] [file join $rtl_dir "constraints.xdc"]
update_compile_order -fileset sources_1

# Change synthesis and implementation strategies
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_NetDelay_high [get_runs impl_1]

puts "\n########################### Finished building project ###########################\n"

if {$run_mode == "terminal"} {
    start_gui
    open_bd_design {[file join $project_dir "LaneDetectionCNN.srcs/sources_1/bd/design_1/design_1.bd"]}
}

regenerate_bd_layout
