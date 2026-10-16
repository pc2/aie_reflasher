# Build the aie_reflasher firmware with xsct (Vitis 2023.1 classic flow).
#
#   XSA=/path/to/tapasco_vck5000.xsa xsct build_arm.tcl
#
# The XSA only has to describe the CIPS (IPI, UART, A72); any Tapasco VCK5000
# build exported with write_hw_platform works, see ../tapasco/aie_reflasher_fw.tcl.
# Output: build/aie_reflasher/Debug/aie_reflasher.elf
#
# Modelled on Xilinx/ROCm-air-platforms firmware/build_arm.tcl.

set script_dir [file dirname [file normalize [info script]]]
set xsa [expr {[info exists ::env(XSA)] ? $::env(XSA) : "$script_dir/../tapasco_vck5000.xsa"}]
if {![file exists $xsa]} {
    puts "ERROR: XSA not found: $xsa (set XSA=...)"
    exit 1
}

setws $script_dir/build

platform create -name "reflasher_pfm" -hw $xsa -no-boot-bsp
domain create -name standalone_a72 -proc psv_cortexa72_0 -os standalone -arch {64-bit}
platform generate

app create -lang c -name aie_reflasher -platform reflasher_pfm -domain standalone_a72 -template "Empty Application(C)"

importsources -name aie_reflasher -soft-link -path $script_dir/main.c
importsources -name aie_reflasher -soft-link -path $script_dir/../common/reflash_proto.h

# --- Put the firmware into OCM instead of DDR -----------------------------
# Tapasco hands out DDR starting at device offset 0 and knows nothing about us,
# so we must not live in DDR. The generated lscript.ld picks the largest memory
# (DDR_LOW3); rewrite every "> <region>" to the OCM region. The firmware is tiny.
set ld "$script_dir/build/aie_reflasher/src/lscript.ld"
set fh [open $ld r]; set ls [read $fh]; close $fh
if {![regexp -nocase {(\w*ocm\w*)\s*:\s*ORIGIN} $ls -> ocm]} {
    puts "ERROR: no OCM region in $ld; map the firmware to a reserved DDR range instead"
    exit 1
}
set ls [regsub -all {>\s*[A-Za-z0-9_]+} $ls "> $ocm"]
# shrink the default heap, OCM is 256 KiB
set ls [regsub {_HEAP_SIZE\s*=\s*DEFINED\(_HEAP_SIZE\)\s*\?\s*_HEAP_SIZE\s*:\s*0x[0-9A-Fa-f]+} $ls {_HEAP_SIZE = DEFINED(_HEAP_SIZE) ? _HEAP_SIZE : 0x1000}]
set fh [open $ld w]; puts -nonewline $fh $ls; close $fh
puts "Linker script now targets region: $ocm"

app build -name aie_reflasher
puts "ELF: $script_dir/build/aie_reflasher/Debug/aie_reflasher.elf"
