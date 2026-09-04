# Simulate with Vivado

start_gui

create_project -force fp_reduce_tests /tmp/fp_reduce_tests -part xcvc1902-vsva2197-2MP-e-S

add_files testbench.sv
add_files ../../VCK5000/reflasher_codegen.sv
add_files ../../ab_bitstream.sv

add_files aie.cdo.reset.bin
add_files aie.cdo.clock.gating.bin
add_files aie.cdo.error.handling.bin
add_files aie.cdo.init.bin
add_files aie.cdo.elfs.bin
add_files aie.cdo.enable.bin

# import_ip [glob -type f ../../sus-float/Versal/xci_files/*.xci]
# upgrade_ip -vlnv xilinx.com:ip:floating_point:7.1 [get_ips fp32_*_ip fp64_*_ip] -log ip_upgrade.log

update_compile_order -fileset sources_1

set_property top AIEngineReflasher_tb [get_filesets sim_1]

launch_simulation
