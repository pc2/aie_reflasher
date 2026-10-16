# Load the firmware onto A72 #0 over JTAG without rebuilding the PDI.
#
#   xsdb load_firmware.tcl build/aie_reflasher/Debug/aie_reflasher.elf
#
# Needs the card's micro-USB (FT4232: JTAG + UART) connected to a machine
# running hw_server. The Tapasco PDI must already be running (the PLM in it
# has initialised FPD/OCM); the A72 is simply idle until we start it.

if {$argc != 1} {
    puts "usage: xsdb load_firmware.tcl <elf>"
    exit 1
}
set elf [lindex $argv 0]

connect
targets -set -nocase -filter {name =~ "*A72*#0"}
rst -processor
dow $elf
con
puts "firmware running"
