# 1. Get the absolute path of the executing script
set script_path [file normalize [info script]]
set tcl_dir [file dirname $script_path]
set vitis_bin_dir [file normalize $tcl_dir/../bin]
set viv_bin_dir [file normalize $tcl_dir/../../vivado/bin]

# Print out the discovered path to verify it works
puts "The bin directories are: "
puts "vitis bin: $vitis_bin_dir"
puts "vivado bin: $viv_bin_dir"


set bit_files [glob -nocomplain "$viv_bin_dir/*.bit"]
if {[llength $bit_files] > 0} {
    # Extract the first matching file path
    set full_bit_path [lindex $bit_files 0]

    # Get just the filename (e.g., "system.bit") without the full directory path
    set bit_filename [file tail $full_bit_path]

    puts "Found bitstream file: $bit_filename"
} else {
    error "Error: No .bit file found in $viv_bin_dir"
}

# 1. Connect to the local hardware server
connect
after 500

# 2. Dynamically find and select the first available JTAG cable target
set jtag_list [jtag targets]
if {[llength $jtag_list] > 0} {
    set cable_id [lindex [lindex $jtag_list 0] 0]
    jtag targets $cable_id
    jtag frequency 15000000
    puts "Configured JTAG cable target $cable_id frequency to 15MHz"
}

# 3. Halt the processor cores immediately to break the DAP APB error loop (FIXED)
targets -set -nocase -filter {name =~ "*cortex-a9*#0"}
stop
after 200

# 4. Select the physical Zynq chip target and shift the FPGA Bitstream
targets -set -nocase -filter {name =~ "*xc7z020*"}
fpga $viv_bin_dir/$bit_filename
after 500

# 5. Return to the core processor context to wipe registers
targets -set -nocase -filter {name =~ "*cortex-a9*#0"}
rst -processor
after 200

# 6. Source and execute your Vivado-generated hardware initialization script
source $tcl_dir/ps7_init.tcl
ps7_init
ps7_post_config
after 1000

# 7. Download your application binary into the now-active DDR RAM
dow $vitis_bin_dir/$app_name.elf

# 8. Run the application
con
puts "Zynq-7000 application successfully deployed via JTAG."
