# Source procs
set script_dir [file dirname [info script]]
source "${script_dir}/procs.tcl"

# Check Vivado version
vivadoVersionCheck "2020.2.2"

# Process arguments
switch [llength $argv] {
    0 { set bitstream_path "[file dirname [info script]]/../vivado_project/LaneDetectionCNN.runs/impl_1/design_1_wrapper.bit" }
    1 { set bitstream_path [lindex $argv 0] }
    default {
        puts "\[ERROR\] Too many arguments. Expected: ?<Bitstream (.bit) path>\n"
        exit    
    }
}

set bitstream_path [file normalize $bitstream_path]
regsub {\.bit$} $bitstream_path {.mcs} mcs_path
regsub {\.bit$} $bitstream_path {.ltx} ltx_path

if {![file exists $bitstream_path]} {
    puts "\[ERROR\] Bitstream not found: ${bitstream_path}\n"
    exit
}

# Write configuration file
write_cfgmem                                        \
    -force                                          \
    -format       MCS                               \
    -size         128                               \
    -interface    BPIx16                            \
    -loadbit      "up 0x00000000 ${bitstream_path}" \
    $mcs_path

# Open hardware manager
open_hw_manager
connect_hw_server -url localhost:3121
current_hw_target                     [get_hw_targets */xilinx_tcf/Digilent/*]
set_property PARAM.FREQUENCY 15000000 [get_hw_targets */xilinx_tcf/Digilent/*]

# Connect to FPGA
open_hw_target

# Check for debug probes
if {[file exists $ltx_path]} {
    puts "INFO: Found debug probe at ${ltx_path}"
    set_property PROBES.FILE      $ltx_path [lindex [get_hw_devices] 0]
    set_property FULL_PROBES.FILE $ltx_path [lindex [get_hw_devices] 0]
}

current_hw_device [lindex [get_hw_devices] 0]
refresh_hw_device [lindex [get_hw_devices] 0]

# Add Configuration Memory Device
create_hw_cfgmem                            \
    -hw_device  [lindex [get_hw_devices] 0] \
    -mem_dev    [lindex [get_cfgmem_parts {mt28gu01gaax1e-bpi-x16}] 0]

set_property PROGRAM.BLANK_CHECK             0           [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices] 0]]
set_property PROGRAM.ERASE                   1           [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices] 0]]
set_property PROGRAM.CFG_PROGRAM             1           [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices] 0]]
set_property PROGRAM.VERIFY                  1           [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices] 0]]
set_property PROGRAM.ADDRESS_RANGE           {use_file}  [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices] 0]]
set_property PROGRAM.FILES                   $mcs_path   [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices] 0]]
set_property PROGRAM.UNUSED_PIN_TERMINATION  {pull-none} [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices] 0]]
set_property PROGRAM.BPI_RS_PINS             {25:24}     [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices] 0]]
set_property PROGRAM.BLANK_CHECK             0           [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices] 0]]
set_property PROGRAM.ERASE                   1           [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices] 0]]
set_property PROGRAM.CFG_PROGRAM             1           [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices] 0]]
set_property PROGRAM.VERIFY                  1           [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices] 0]]

# Program device
set HW_CFGMEM_TYPE [get_property PROGRAM.HW_CFGMEM_TYPE  [lindex [get_hw_devices] 0]]
set CFGMEM_PART    [get_property CFGMEM_PART             [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices] 0 ]]]
set MEM_TYPE       [get_property MEM_TYPE                $CFGMEM_PART]

if {$HW_CFGMEM_TYPE ne $MEM_TYPE} {
    create_hw_bitstream -hw_device [lindex [get_hw_devices] 0] [get_property PROGRAM.HW_CFGMEM_BITFILE [lindex [get_hw_devices] 0]]
    program_hw_devices [lindex [get_hw_devices] 0]
}

# Program flash
program_hw_cfgmem -hw_cfgmem [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices] 0]]

# Reprogram FPGA to refresh
# Otherwise FPGA's power would need to be disconnected and reconnected to work
set_property PROGRAM.FILE $bitstream_path [lindex [get_hw_devices] 0]
program_hw_devices [lindex [get_hw_devices] 0]

# Disconnect and exit
disconnect_hw_server localhost:3121
close_hw_manager
exit
