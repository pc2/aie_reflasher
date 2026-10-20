# vivado -mode batch -source sim.tcl -tclargs <codegen.sv> <project dir>
set SV  [lindex $argv 0]
set PRJ [lindex $argv 1]
create_project -force aie_pdi_loader_sim $PRJ -part xcvc1902-vsvd1760-2MP-e-S
add_files $SV
add_files fake_plm_axil.sv
add_files AIEPdiLoader_tb.sv
update_compile_order -fileset sources_1
set_property top AIEPdiLoader_tb [get_filesets sim_1]
launch_simulation
run all
