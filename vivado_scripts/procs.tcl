#############################################################################################
# Find maximum number of CPUs on machine
# Written by: stephenm
# Source: https://support.xilinx.com/s/question/0D52E00006hpKAISA2/how-to-decide-the-number-of-jobs-in-run-settings-in-generate-output-products
#############################################################################################

proc numberOfCPUs {} {
    # Windows puts it in an environment variable
    global tcl_platform env
    if {$tcl_platform(platform) eq "windows"} {
        return $env(NUMBER_OF_PROCESSORS)
    }

    # Check for sysctl (OSX, BSD)
    set sysctl [auto_execok "sysctl"]
    if {[llength $sysctl]} {
        if {![catch {exec {*}$sysctl -n "hw.ncpu"} cores]} {
            return $cores
        }
    }

    # Assume Linux, which has /proc/cpuinfo, but be careful
    if {![catch {open "/proc/cpuinfo"} f]} {
        set cores [regexp -all -line {^processor\s} [read $f]]
        close $f
        if {$cores > 0} {
            return $cores
        }
    }

    # No idea what the actual number of cores is; exhausted all our options
    # Fall back to returning 1; there must be at least that because we're running on it!
    return 1
}

#############################################################################################
# Comment out every line in a file with the given comment character
#############################################################################################

proc commentFile {path comm_char} {
    set FIN  [open "${path}"      r]
    set FOUT [open "${path}.comm" w]

    while {[gets $FIN line] >= 0} {
        puts $FOUT "${comm_char} ${line}"
    }

    close $FIN
    close $FOUT

    file rename -force "${path}.comm" $path
}

#############################################################################################
# Replace a string $search from the file with another string $replace
#############################################################################################

proc replaceString {path search replace} {
    set FIN  [open "${path}"         r]
    set FOUT [open "${path}.replace" w]

    while {[gets $FIN line] >= 0} {
        regsub -all $search $line $replace line
        puts $FOUT $line
    }

    close $FIN
    close $FOUT

    file rename -force "${path}.replace" $path
}

#############################################################################################
# Check Vivado version
#############################################################################################

proc vivadoVersionCheck {expected} {
    if {[version -short] ne $expected} {
        puts "\[ERROR\] This script is expected to run on Vivado version ${expected}. If you still wish to run this script on a different version, modify \"vivadoVersionCheck\" call in [info script]"
        exit
    }
}
