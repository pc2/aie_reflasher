# Package the AIEPdiLoader PE as an IP-XACT core for Tapasco.
#   vivado -mode batch -source pack_pdi_loader_kernel.tcl -tclargs <part> <codegen.sv> <tapasco common ip dir>
# The third argument is $TAPASCO_HOME_TCL/common/ip: it holds the PDILoad interface definition, which the
# packager needs in its IP repository to infer the PE's M_PDI_LOAD master from the port names.
# Registers: CTRL 0x00, return value 0x10, PDI_ADDRESS 0x20 (64).
# Return register: [31:0] PLMI status or 0xFFFFFF00|loader error, [63:32] XilLoader status on PLM error,
# otherwise handshake length in design clock cycles.

set PART      [lindex $argv 0]
set SV        [lindex $argv 1]
set COMMON_IP [lindex $argv 2]
set KERNEL_NAME AIEPdiLoader
set PDI_LOAD_RTL pc2.uni-paderborn.de:lennart:PDILoad_rtl:1.0

create_project ${KERNEL_NAME} ./${KERNEL_NAME} -part $PART
set_property ip_repo_paths $COMMON_IP [current_project]
update_ip_catalog
add_files -norecurse [list $SV]
set_property top ${KERNEL_NAME} [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir ./${KERNEL_NAME}_ip -vendor pc2-sus-experiments -library sus-xrt -taxonomy /UserIP -import_files
set_property ipi_drc {ignore_freq_hz false} [ipx::current_core]
set_property sdx_kernel true [ipx::current_core]
set_property sdx_kernel_type rtl [ipx::current_core]
set_property vitis_drc {ctrl_protocol ap_ctrl_hs} [ipx::current_core]
set_property ipi_drc {ignore_freq_hz true} [ipx::current_core]
set_property supported_families {versal Production} [ipx::current_core]

foreach busif {s_axi_control M_PDI_LOAD} {
  if {[llength [ipx::get_bus_interfaces $busif -of_objects [ipx::current_core]]] == 0} {
    error "pack_pdi_loader_kernel: bus interface $busif was not inferred from the port names"
  }
}
set pdi_load [ipx::get_bus_interfaces M_PDI_LOAD -of_objects [ipx::current_core]]
if {[get_property abstraction_type_vlnv $pdi_load] != $PDI_LOAD_RTL || [get_property interface_mode $pdi_load] != "master"} {
  error "pack_pdi_loader_kernel: M_PDI_LOAD is [get_property interface_mode $pdi_load] [get_property abstraction_type_vlnv $pdi_load], expected master $PDI_LOAD_RTL"
}
set_property value {s_axi_control:M_PDI_LOAD} [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects [ipx::get_bus_interfaces aclk -of_objects [ipx::current_core]]]

set CTRL_ADDR_BLOCK [ipx::get_address_blocks reg0 -of_objects [ipx::get_memory_maps s_axi_control -of_objects [ipx::current_core]]]

ipx::add_register CTRL $CTRL_ADDR_BLOCK
set_property description    {Control Signals} [ipx::get_registers CTRL -of_objects $CTRL_ADDR_BLOCK]
set_property address_offset {0x00}            [ipx::get_registers CTRL -of_objects $CTRL_ADDR_BLOCK]
set_property size           {32}              [ipx::get_registers CTRL -of_objects $CTRL_ADDR_BLOCK]

ipx::add_register PDI_ADDRESS $CTRL_ADDR_BLOCK
set_property description    {PS physical address of the partial PDI in card DDR (0x100_0000_0000 + device offset)} [ipx::get_registers PDI_ADDRESS -of_objects $CTRL_ADDR_BLOCK]
set_property address_offset {0x020}           [ipx::get_registers PDI_ADDRESS -of_objects $CTRL_ADDR_BLOCK]
set_property size           {64}              [ipx::get_registers PDI_ADDRESS -of_objects $CTRL_ADDR_BLOCK]

# PDI_ADDRESS is a PS address, not a Tapasco buffer handle: no ASSOCIATED_BUSIF, so
# Tapasco does not try to allocate/translate it.

set_property core_revision 2 [ipx::current_core]
ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::save_core [ipx::current_core]
puts "PACKAGED ${KERNEL_NAME}"
