##################################################################
# Process arguments 
##################################################################
 
set script_dir [file dirname [info script]]
set valid_args [list gui launch_run debug ]

foreach arg $argv {
    if {$arg ni $valid_args} {
        if {[info exists project_dir]} {
            puts "\[ERROR\] Unrecognized argument: \"${arg}\""
            puts "\tExpected: ?gui ?launch_run ?debug ?<Project directory path>\n"
            exit
        } else {
            set project_dir $arg
        }
    }
}

if {![info exists project_dir]} {
    set project_dir "${script_dir}/../vivado_project"
}
  
# Set other paths and normalize
set project_dir [file normalize "${project_dir}"              ]
set sources_dir [file normalize "${script_dir}/../vivado_sources"]
set ip_repo_dir [file normalize "${project_dir}/ip_repo"      ]
 
# Source procs
source "${script_dir}/procs.tcl"

# Check Vivado version
vivadoVersionCheck "2020.2.2"

##################################################################
# Create project 
##################################################################
 
puts "\n########################### Creating project in ${project_dir} ###########################\n"
create_project LaneDetectionCNN $project_dir -part xc7vx485tffg1761-2
set_property board_part [lindex [lsort [get_board_parts *xilinx.com:vc707:part0*]] end] [current_project]

if {"gui" in $argv} {
    start_gui
}

##################################################################
# Create AXI IP 
##################################################################

puts "\n########################### Creating IP ###########################\n"
create_peripheral user.org user LaneDetectionCNN 1.0 -dir $ip_repo_dir

ipx::edit_ip_in_project                                 \
    -quiet                                              \
    -upgrade       true                                 \
    -name          edit_LaneDetectionCNN_v1_0           \
    -directory     $ip_repo_dir                         \
    "${ip_repo_dir}/LaneDetectionCNN_1.0/component.xml" \

add_files                                               \
    -force                                              \
    -norecurse                                          \
    -copy_to "${ip_repo_dir}/LaneDetectionCNN_1.0/src"  \
    [glob -directory "${sources_dir}/rtl" "*.v"]        \

set_property top LaneDetectionCNN_AXI_IP [current_fileset]
update_compile_order -fileset sources_1

# Infer AXI core from sources
ipx::infer_core -vendor user.org -library user -taxonomy /UserIP "${ip_repo_dir}/LaneDetectionCNN_1.0/src"

# Repackage and save IP
set_property previous_version_for_upgrade ::: [ipx::current_core]
set_property core_revision 1 [ipx::current_core]
ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::check_integrity [ipx::current_core]
ipx::save_core [ipx::current_core]

# Close edit_ip project and update IP catalog
close_project -delete
set_property ip_repo_paths $ip_repo_dir [current_project]
update_ip_catalog

##################################################################
# Create block design in Vivado 
##################################################################

puts "\n########################### Creating block design ###########################\n"
create_bd_design "design_1"

# XDMA
create_bd_cell -type ip -vlnv xilinx.com:ip:xdma xdma_0

set_property -dict [list                            \
    CONFIG.pl_link_cap_max_link_width   "X1"        \
    CONFIG.pl_link_cap_max_link_speed   "5.0_GT/s"  \
    CONFIG.axisten_freq                 "250"       \
    CONFIG.pf0_device_id                "7021"      \
    CONFIG.plltype                      "QPLL1"     \
    CONFIG.PF0_DEVICE_ID_mqdma          "9021"      \
    CONFIG.PF2_DEVICE_ID_mqdma          "9021"      \
    CONFIG.PF3_DEVICE_ID_mqdma          "9021"      \
] [get_bd_cells xdma_0]

# Clock buffer
create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf util_ds_buf_0
set_property -dict [list CONFIG.C_BUF_TYPE "IBUFDSGTE"] [get_bd_cells util_ds_buf_0]

# Lane detection CNN IP
create_bd_cell -type ip -vlnv user.org:user:LaneDetectionCNN_AXI_IP LaneDetectionCNN_AXI_0

# Connect PCIe nets
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
set_property -dict [list CONFIG.CLKOUT1_REQUESTED_OUT_FREQ "200.000"] [get_bd_cells clk_wiz_0]

# Connect AXI interfaces
apply_bd_automation -rule xilinx.com:bd_rule:board -config { \
    Board_Interface "reset (FPGA Reset)"                     \
    Manual_Source   "New External Port (ACTIVE_HIGH)"        \
} [get_bd_pins clk_wiz_0/reset]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Clk_master   "/xdma_0/axi_aclk"                         \
    Clk_slave    "/clk_wiz_0/clk_out1"                      \
    Clk_xbar     "Auto"                                     \
    Master       "/xdma_0/M_AXI"                            \
    Slave        "/LaneDetectionCNN_AXI_0/s00_axi"          \
    ddr_seg      "Auto"                                     \
    intc_ip      "New AXI SmartConnect"                     \
    master_apm   "0"                                        \
} [get_bd_intf_pins LaneDetectionCNN_AXI_0/s00_axi]

# Set AXI address map
set_property offset 0x0 [get_bd_addr_segs "xdma_0/M_AXI/SEG_LaneDetectionCNN_AXI_0_reg0"]
set_property range 1M [get_bd_addr_segs "xdma_0/M_AXI/SEG_LaneDetectionCNN_AXI_0_reg0"]

############################################### Create logic for signal leds ###############################################

create_bd_cell -type hier signal_leds
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant signal_leds/xlconstant_0
set_property -dict [list CONFIG.CONST_VAL "0"] [get_bd_cells signal_leds/xlconstant_0]

# Create counters to make clock leds
for {set i 0} {$i < 3} {incr i} {
    # Binary counter
    create_bd_cell -type ip -vlnv xilinx.com:ip:c_counter_binary "signal_leds/c_counter_binary_${i}"
    set_property -dict [list CONFIG.Output_Width "25"] [get_bd_cells "signal_leds/c_counter_binary_${i}"]

    # Slice block
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice "signal_leds/xlslice_${i}"
    set_property -dict [list     \
        CONFIG.DIN_TO      "24"  \
        CONFIG.DIN_FROM    "24"  \
        CONFIG.DIN_WIDTH   "25"  \
        CONFIG.DOUT_WIDTH  "1"   \
    ] [get_bd_cells "signal_leds/xlslice_${i}"]
    
    # Connect counter to slice block
    connect_bd_net [get_bd_pins "signal_leds/c_counter_binary_${i}/Q"] [get_bd_pins "signal_leds/xlslice_${i}/Din"]
}

# Connect counter clock sources
connect_bd_net [get_bd_pins signal_leds/c_counter_binary_0/CLK] [get_bd_pins util_ds_buf_0/IBUF_OUT]
connect_bd_net [get_bd_pins signal_leds/c_counter_binary_1/CLK] [get_bd_pins xdma_0/axi_aclk]
connect_bd_net [get_bd_pins signal_leds/c_counter_binary_2/CLK] [get_bd_pins clk_wiz_0/clk_out1]

# Create concat block for leds
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat signal_leds/xlconcat_0
set_property -dict [list CONFIG.NUM_PORTS "8"] [get_bd_cells signal_leds/xlconcat_0]

# Connect concat block's inputs
set led_signals [list              \
    signal_leds/xlslice_0/Dout     \
    signal_leds/xlslice_1/Dout     \
    signal_leds/xlslice_2/Dout     \
    xdma_0/user_lnk_up             \
    signal_leds/xlconstant_0/dout  \
    LaneDetectionCNN_AXI_0/wr_led  \
    LaneDetectionCNN_AXI_0/rd_led  \
    LaneDetectionCNN_AXI_0/busy    \
]

for {set i 0} {$i < 8} {incr i} {
    connect_bd_net [get_bd_pins [lindex $led_signals $i]] [get_bd_pins "signal_leds/xlconcat_0/In${i}"]  
}

# Make concat block's output external
make_bd_pins_external  [get_bd_pins signal_leds/xlconcat_0/dout]
set_property name led_8bits [get_bd_ports dout_0]

##################################################################
# Validate and save block design 
##################################################################

puts "\n########################### Validate and save block design ###########################\n"

# Validate and save block design
validate_bd_design
save_bd_design

# Create HDL wrapper
make_wrapper -files [get_files "${project_dir}/LaneDetectionCNN.srcs/sources_1/bd/design_1/design_1.bd"] -top
add_files -norecurse "${project_dir}/LaneDetectionCNN.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v"
set_property top design_1_wrapper [current_fileset]

# Add constraints
add_files                                                         \
    -fileset constrs_1                                            \
    -force                                                        \
    -norecurse                                                    \
    -copy_to "${project_dir}/LaneDetectionCNN.srcs/constrs_1/new" \
    [glob -directory "${sources_dir}/constraints" "*.xdc"]        \

# Comment out constraint file for debug if not required
if {"debug" ni $argv} {
    commentFile "${project_dir}/LaneDetectionCNN.srcs/constrs_1/new/debug.xdc" "#"
}

# Change synthesis and implementation strategies
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_NetDelay_high [get_runs impl_1]

# Generate output products
set_property synth_checkpoint_mode None [get_files "${project_dir}/LaneDetectionCNN.srcs/sources_1/bd/design_1/design_1.bd"]
generate_target all [get_files "${project_dir}/LaneDetectionCNN.srcs/sources_1/bd/design_1/design_1.bd"]
export_ip_user_files -of_objects [get_files "${project_dir}/LaneDetectionCNN.srcs/sources_1/bd/design_1/design_1.bd"] -no_script -sync -force -quiet

puts "\n########################### Finished building project ###########################\n"

if {"launch_run" in $argv} {
    launch_runs impl_1 -to_step write_bitstream -jobs [numberOfCPUs]

    if {"gui" ni $argv} {
        puts "\n########################## Running Synthesis ##########################\n"
        wait_on_run -verbose synth_1
        puts "\n########################## Running Implementation ##########################\n"
        wait_on_run -verbose impl_1
    }
}

if {"gui" in $argv} {
    regenerate_bd_layout
} else {
    exit
}
