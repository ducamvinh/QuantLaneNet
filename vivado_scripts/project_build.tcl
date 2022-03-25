############################################### Create project ###############################################
set project_dir [file join [file dirname $argv0] "../vivado_project"]
create_project LaneDetectionCNN $project_dir -part xc7vx485tffg1761-2
set_property board_part xilinx.com:vc707:part0:1.4 [current_project]

############################################### Create & edit IP ###############################################
puts "\n########################### Creating IP ###########################\n"
set ip_repo_dir [file join $project_dir "ip_repo"]
create_peripheral user.org user LaneDetectionCNN 1.0 -dir $ip_repo_dir
ipx::edit_ip_in_project -quiet -upgrade true -name edit_LaneDetectionCNN_v1_0 -directory $ip_repo_dir [file join $ip_repo_dir "LaneDetectionCNN_1.0/component.xml"]
add_files -norecurse -copy_to [file join $ip_repo_dir "LaneDetectionCNN_1.0/src"] [glob -directory [file join [file dirname $argv0] "../rtl_sources"] *.v]
set_property top LaneDetectionCNN_AXI_IP [current_fileset]
update_compile_order -fileset sources_1

# Infer AXI core from sources
ipx::infer_core -vendor user.org -library user -taxonomy /UserIP [file join $ip_repo_dir "LaneDetectionCNN_1.0/src"]

# Set parameters as un-editable
set_property widget {textEdit} [ipgui::get_guiparamspec -name "C_S00_AXI_DATA_WIDTH" -component [ipx::current_core] ]
set_property enablement_value false [ipx::get_user_parameters "C_S00_AXI_DATA_WIDTH" -of_objects [ipx::current_core]]
set_property widget {textEdit} [ipgui::get_guiparamspec -name "C_S00_AXI_ADDR_WIDTH" -component [ipx::current_core] ]
set_property enablement_value false [ipx::get_user_parameters "C_S00_AXI_ADDR_WIDTH" -of_objects [ipx::current_core]]
ipx::merge_project_changes files [ipx::current_core]

# Repackage and save IP
set_property previous_version_for_upgrade ::: [ipx::find_open_core user.org:user:LaneDetectionCNN_AXI_IP:1.0]
set_property core_revision 1 [ipx::find_open_core user.org:user:LaneDetectionCNN_AXI_IP:1.0]
ipx::create_xgui_files [ipx::find_open_core user.org:user:LaneDetectionCNN_AXI_IP:1.0]
ipx::update_checksums [ipx::find_open_core user.org:user:LaneDetectionCNN_AXI_IP:1.0]
ipx::check_integrity [ipx::find_open_core user.org:user:LaneDetectionCNN_AXI_IP:1.0]
ipx::save_core [ipx::find_open_core user.org:user:LaneDetectionCNN_AXI_IP:1.0]
close_project -delete
set_property ip_repo_paths [file join $ip_repo_dir "LaneDetectionCNN_1.0/src"] [current_project]
update_ip_catalog

############################################### Create block design ###############################################
puts "\n########################### Creating block design ###########################\n"
create_bd_design "design_1"

# XDMA
create_bd_cell -type ip -vlnv xilinx.com:ip:xdma:4.1 xdma_0
set_property -dict [list CONFIG.pl_link_cap_max_link_width {X2} CONFIG.pl_link_cap_max_link_speed {5.0_GT/s} CONFIG.axisten_freq {125} CONFIG.pf0_device_id {7022} CONFIG.plltype {QPLL1} CONFIG.PF0_DEVICE_ID_mqdma {9022} CONFIG.PF2_DEVICE_ID_mqdma {9022} CONFIG.PF3_DEVICE_ID_mqdma {9022}] [get_bd_cells xdma_0]

# Clock buffer
create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.1 util_ds_buf_0
set_property -dict [list CONFIG.C_BUF_TYPE {IBUFDSGTE}] [get_bd_cells util_ds_buf_0]

# Lane detection CNN IP
create_bd_cell -type ip -vlnv user.org:user:LaneDetectionCNN_AXI_IP:1.0 LaneDetectionCNN_AXI_0

# AXI interconnect
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property -dict [list CONFIG.NUM_MI {1}] [get_bd_cells axi_interconnect_0]

# Connect nets
connect_bd_net [get_bd_pins util_ds_buf_0/IBUF_OUT] [get_bd_pins xdma_0/sys_clk]
make_bd_pins_external  [get_bd_pins xdma_0/sys_rst_n]
set_property name sys_rst_n [get_bd_ports sys_rst_n_0]
make_bd_intf_pins_external  [get_bd_intf_pins util_ds_buf_0/CLK_IN_D]
set_property name pcie_diff [get_bd_intf_ports CLK_IN_D_0]
make_bd_intf_pins_external  [get_bd_intf_pins xdma_0/pcie_mgt]
set_property name pcie_mgt [get_bd_intf_ports pcie_mgt_0]

# Connect AXI interfaces
connect_bd_intf_net [get_bd_intf_pins xdma_0/M_AXI] -boundary_type upper [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_net [get_bd_pins xdma_0/axi_aclk] [get_bd_pins axi_interconnect_0/ACLK]
connect_bd_net [get_bd_pins axi_interconnect_0/S00_ACLK] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins axi_interconnect_0/M00_ACLK] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net [get_bd_pins axi_interconnect_0/S00_ARESETN] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_net [get_bd_pins axi_interconnect_0/M00_ARESETN] [get_bd_pins xdma_0/axi_aresetn]
connect_bd_intf_net -boundary_type upper [get_bd_intf_pins axi_interconnect_0/M00_AXI] [get_bd_intf_pins LaneDetectionCNN_AXI_0/s00_axi]
connect_bd_net [get_bd_pins LaneDetectionCNN_AXI_0/s00_axi_aclk] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins LaneDetectionCNN_AXI_0/s00_axi_aresetn] [get_bd_pins xdma_0/axi_aresetn]

# Set AXI address map
assign_bd_address -target_address_space /xdma_0/M_AXI [get_bd_addr_segs LaneDetectionCNN_AXI_0/s00_axi/reg0] -force
set_property offset 0x00000000C0000000 [get_bd_addr_segs {xdma_0/M_AXI/SEG_LaneDetectionCNN_AXI_0_reg0}]
set_property range 1M [get_bd_addr_segs {xdma_0/M_AXI/SEG_LaneDetectionCNN_AXI_0_reg0}]
set_property CONFIG.FREQ_HZ [get_property CONFIG.FREQ_HZ [get_bd_pins /xdma_0/axi_aclk]] [get_bd_pins /LaneDetectionCNN_AXI_0/s00_axi_aclk]

############################################### Create logic for signal leds ###############################################

# Create counters to make clock leds
for {set i 0} {$i < 2} {incr i} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:c_counter_binary:12.0 c_counter_binary_$i
    set_property -dict [list CONFIG.Output_Width {25}] [get_bd_cells c_counter_binary_$i]
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_$i
    set_property -dict [list CONFIG.DIN_TO {24} CONFIG.DIN_FROM {24} CONFIG.DIN_WIDTH {25} CONFIG.DOUT_WIDTH {1}] [get_bd_cells xlslice_$i]
    connect_bd_net [get_bd_pins c_counter_binary_$i/Q] [get_bd_pins xlslice_$i/Din]
}

# Connect clock sources
connect_bd_net [get_bd_pins c_counter_binary_0/CLK] [get_bd_pins util_ds_buf_0/IBUF_OUT]
connect_bd_net [get_bd_pins c_counter_binary_1/CLK] [get_bd_pins xdma_0/axi_aclk]

# Create concat block for leds
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0
set_property -dict [list CONFIG.NUM_PORTS {8}] [get_bd_cells xlconcat_0]

# Connect concat block's inputs
set led_signals {xlslice_0/Dout xlslice_1/Dout sys_rst_n xdma_0/axi_aresetn xdma_0/user_lnk_up LaneDetectionCNN_AXI_0/wr_led LaneDetectionCNN_AXI_0/rd_led LaneDetectionCNN_AXI_0/busy} 
for {set i 0} {$i < 8} {incr i} {
    connect_bd_net [get_bd_pins [lindex $led_signals $i]] [get_bd_pins xlconcat_0/In$i]  
}

# Make concat block's output external
make_bd_pins_external  [get_bd_pins xlconcat_0/dout]
set_property name leds [get_bd_ports dout_0]

############################################### Finish building project ###############################################
puts "\n########################### Validate and save block design ###########################\n"

# Validate and save block design
validate_bd_design
save_bd_design

# Create HDL wrapper
make_wrapper -files [get_files [file join $project_dir "LaneDetectionCNN.srcs/sources_1/bd/design_1/design_1.bd"]] -top
add_files -norecurse [file join $project_dir "LaneDetectionCNN.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v"]

# Add constraints
add_files -fileset constrs_1 -norecurse [file join [file dirname $argv0] "../rtl_sources/constraints.xdc"]
update_compile_order -fileset sources_1

puts "\n########################### Finished building project ###########################\n"

start_gui
# exit
