# Source procs
set script_dir [file dirname [info script]]
source -notrace "${script_dir}/procs.tcl"

# Check Vivado version
vivadoVersionCheck "2020.2.2"

##################################################################
# Process arguments
##################################################################

set valid_args  [list gui launch_run debug no_exit close_project launch_both]
set project_dir ""

foreach arg $argv {
    if {$arg ni $valid_args} {
        if {$project_dir eq ""} {
            set project_dir $arg
        } else {
            puts "\[ERROR\] Unrecognized argument: \"${arg}\""
            puts "[string repeat " " 8 ]Expected: -tclargs ?<Project directory path>"
            puts "[string repeat " " 27]?[join $valid_args "\n[string repeat " " 27]?"]\n"
            exit
        }
    }
}

if {$project_dir eq ""} {
    set project_dir "${script_dir}/../vivado_project"
}

# Set other paths and normalize
set project_dir [file normalize "${project_dir}"                 ]
set sources_dir [file normalize "${script_dir}/../vivado_sources"]
set ip_repo_dir [file normalize "${project_dir}/ip_repo"         ]

# Start GUI
if {"gui" in $argv} {
    start_gui
}

##################################################################
# Create project
##################################################################

puts "\n##########################################\n# Creating project in ${project_dir}\n##########################################\n"
create_project QuantLaneNet $project_dir -part xc7vx485tffg1761-2
set_property board_part [lindex [lsort [get_board_parts *xilinx.com:vc707:part0*]] end] [current_project]

##################################################################
# Create AXI IP
##################################################################

puts "\n##########################################\n# Creating IP\n##########################################\n"
create_peripheral user.org user QuantLaneNet 1.0 -dir $ip_repo_dir

ipx::edit_ip_in_project                                 \
    -quiet                                              \
    -upgrade       true                                 \
    -name          edit_QuantLaneNet_v1_0               \
    -directory     $ip_repo_dir                         \
    "${ip_repo_dir}/QuantLaneNet_1.0/component.xml"     \

add_files                                               \
    -force                                              \
    -norecurse                                          \
    -copy_to "${ip_repo_dir}/QuantLaneNet_1.0/src"      \
    [glob -directory "${sources_dir}/rtl" "*.v"]        \

set_property top QuantLaneNet_AXI [current_fileset]
update_compile_order -fileset sources_1

# Infer AXI core from sources
ipx::infer_core -vendor user.org -library user -taxonomy /UserIP "${ip_repo_dir}/QuantLaneNet_1.0/src"

# Repackage and save IP
set_property previous_version_for_upgrade ::: [ipx::current_core]
set_property core_revision 1                  [ipx::current_core]
ipx::create_xgui_files                        [ipx::current_core]
ipx::update_checksums                         [ipx::current_core]
ipx::check_integrity                          [ipx::current_core]
ipx::save_core                                [ipx::current_core]

# Close edit_ip project and update IP catalog
close_project -delete
set_property ip_repo_paths $ip_repo_dir [current_project]
update_ip_catalog

##################################################################
# Create block design in Vivado
##################################################################

puts "\n##########################################\n# Creating block design\n##########################################\n"
create_bd_design "design_1"
set blink_counter_width 26

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
create_bd_cell -type ip -vlnv user.org:user:QuantLaneNet_AXI QuantLaneNet_AXI_0
set_property -dict [list CONFIG.LED_BLINK_COUNTER_WIDTH [expr $blink_counter_width - 1]] [get_bd_cells QuantLaneNet_AXI_0]

# Connect PCIe nets
connect_bd_net [get_bd_pins util_ds_buf_0/IBUF_OUT] [get_bd_pins xdma_0/sys_clk]

make_bd_pins_external      [get_bd_pins       xdma_0/sys_rst_n      ]
make_bd_intf_pins_external [get_bd_intf_pins  util_ds_buf_0/CLK_IN_D]
make_bd_intf_pins_external [get_bd_intf_pins  xdma_0/pcie_mgt       ]

set_property name "pcie_perstn"    [get_bd_ports      -of_objects [get_bd_nets      -of_objects [get_bd_pins       xdma_0/sys_rst_n      ]]]
set_property name "pcie_refclk"    [get_bd_intf_ports -of_objects [get_bd_intf_nets -of_objects [get_bd_intf_pins  util_ds_buf_0/CLK_IN_D]]]
set_property name "pci_express_x1" [get_bd_intf_ports -of_objects [get_bd_intf_nets -of_objects [get_bd_intf_pins  xdma_0/pcie_mgt       ]]]

# Connect AXI interfaces
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Clk_master   "/xdma_0/axi_aclk"                         \
    Clk_slave    "Auto"                                     \
    Clk_xbar     "Auto"                                     \
    Master       "/xdma_0/M_AXI"                            \
    Slave        "/QuantLaneNet_AXI_0/s00_axi"              \
    ddr_seg      "Auto"                                     \
    intc_ip      "New AXI SmartConnect"                     \
    master_apm   "0"                                        \
} [get_bd_intf_pins QuantLaneNet_AXI_0/s00_axi]

# Set AXI address map
set_property offset 0x0 [get_bd_addr_segs "xdma_0/M_AXI/SEG_QuantLaneNet_AXI_0_reg0"]
set_property range 1M [get_bd_addr_segs "xdma_0/M_AXI/SEG_QuantLaneNet_AXI_0_reg0"]

############################################### Create logic for signal leds ###############################################

create_bd_cell -type hier signal_leds
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant signal_leds/xlconstant_0
set_property -dict [list CONFIG.CONST_VAL "0"] [get_bd_cells signal_leds/xlconstant_0]

set clocks [list            \
    util_ds_buf_0/IBUF_OUT  \
    xdma_0/axi_aclk         \
]

# Create counters to make clock leds
for {set i 0} {$i < [llength $clocks]} {incr i} {
    # Binary counter
    create_bd_cell -type ip -vlnv xilinx.com:ip:c_counter_binary "signal_leds/c_counter_binary_${i}"
    set_property -dict [list                       \
        CONFIG.Output_Width   $blink_counter_width \
        CONFIG.AINIT_Value    0                    \
    ] [get_bd_cells "signal_leds/c_counter_binary_${i}"]

    # Slice block
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice "signal_leds/xlslice_${i}"
    set_property -dict [list                                   \
        CONFIG.DIN_TO         [expr $blink_counter_width - 1]  \
        CONFIG.DIN_FROM       [expr $blink_counter_width - 1]  \
        CONFIG.DIN_WIDTH      $blink_counter_width             \
        CONFIG.DOUT_WIDTH     1                                \
    ] [get_bd_cells "signal_leds/xlslice_${i}"]

    # Connect counter to clock source slice block
    connect_bd_net [get_bd_pins "signal_leds/c_counter_binary_${i}/CLK"] [get_bd_pins [lindex $clocks $i]]
    connect_bd_net [get_bd_pins "signal_leds/c_counter_binary_${i}/Q"  ] [get_bd_pins "signal_leds/xlslice_${i}/Din"]
}

# Create concat block for leds
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat signal_leds/xlconcat_0
set_property -dict [list CONFIG.NUM_PORTS "8"] [get_bd_cells signal_leds/xlconcat_0]

# Connect concat block's inputs
set led_signals [list              \
    signal_leds/xlslice_0/Dout     \
    signal_leds/xlslice_1/Dout     \
    xdma_0/user_lnk_up             \
    signal_leds/xlconstant_0/dout  \
    signal_leds/xlconstant_0/dout  \
    QuantLaneNet_AXI_0/wr_led      \
    QuantLaneNet_AXI_0/rd_led      \
    QuantLaneNet_AXI_0/busy        \
]

for {set i 0} {$i < 8} {incr i} {
    connect_bd_net [get_bd_pins [lindex $led_signals $i]] [get_bd_pins "signal_leds/xlconcat_0/In${i}"]
}

# Make concat block's output external
make_bd_pins_external [get_bd_pins signal_leds/xlconcat_0/dout]
set_property name "led_8bits" [get_bd_ports -of_objects [get_bd_nets -of_objects [get_bd_pins signal_leds/* -filter {DIR == O}]]]

##################################################################
# Validate and save block design
##################################################################

puts "\n##########################################\n# Validate and save block design\n##########################################\n"

# Validate and save block design
validate_bd_design
save_bd_design

if {"gui" ni $argv} {
    close_bd_design [get_bd_designs design_1]
}

# Create HDL wrapper
add_files -norecurse [make_wrapper -files [get_files *design_1.bd] -top]
set_property top design_1_wrapper [current_fileset]

# Add constraints
create_fileset -constrset "constrs_debug"

add_files                                                         \
    -fileset "constrs_1"                                          \
    -force                                                        \
    -norecurse                                                    \
    -copy_to "${project_dir}/QuantLaneNet.srcs/constrs_1/new"     \
    "${sources_dir}/constraints/constraints.xdc"                  \

add_files                                                         \
    -fileset "constrs_debug"                                      \
    -force                                                        \
    -norecurse                                                    \
    -copy_to "${project_dir}/QuantLaneNet.srcs/constrs_debug/new" \
    [glob -directory "${sources_dir}/constraints" "*.xdc"]        \

# Change strategies for main run
set_property strategy "Vivado Synthesis Defaults"           [get_runs synth_1]
set_property strategy "Performance_ExplorePostRoutePhysOpt" [get_runs impl_1 ]

# Create run for design with debug core
set release [lindex [split [version -short] "."] 0]

create_run synth_debug                        \
    -constrset  "constrs_debug"               \
    -flow       "Vivado Synthesis ${release}" \
    -strategy   "Flow_PerfOptimized_high"     \

create_run impl_debug                                  \
    -parent_run  "synth_debug"                         \
    -flow        "Vivado Implementation ${release}"    \
    -strategy    "Performance_ExplorePostRoutePhysOpt" \

# Generate output products
set_property synth_checkpoint_mode None                         [get_files *design_1.bd]
generate_target all                                             [get_files *design_1.bd]
export_ip_user_files -no_script -sync -force -quiet -of_objects [get_files *design_1.bd]

puts "\n##########################################\n# Finished building project\n##########################################\n"

if {"launch_run" in $argv && "launch_both" ni $argv} {
    if {"debug" in $argv} {
        set mode "debug"
        set name "With ILA debug core"
    } else {
        set mode "1"
        set name "Regular"
    }

    launch_runs "impl_${mode}" -to_step write_bitstream -jobs [numberOfCPUs]

    if {"gui" ni $argv} {
        puts "\n##########################################\n# Running Synthesis (${name})\n##########################################\n"
        wait_on_run -verbose "synth_${mode}"
        puts "\n##########################################\n# Running Implementation (${name})\n##########################################\n"
        wait_on_run -verbose "impl_${mode}"
    }

} elseif {"launch_both" in $argv} {
    foreach {mode name} {"1" "Regular" "debug" "With ILA debug core"} {
        launch_runs "impl_${mode}" -to_step write_bitstream -jobs [numberOfCPUs]

        if {"gui" ni $argv} {
            puts "\n##########################################\n# Running Synthesis (${name})\n##########################################\n"
            wait_on_run -verbose "synth_${mode}"
            puts "\n##########################################\n# Running Implementation (${name})\n##########################################\n"
            wait_on_run -verbose "impl_${mode}"
        }
    }
}

if {"gui" in $argv} {
    regenerate_bd_layout
} else {
    if {"close_project" in $argv || "no_exit" ni $argv} {
        close_project
    }

    if {"no_exit" ni $argv} {
        exit
    }
}
