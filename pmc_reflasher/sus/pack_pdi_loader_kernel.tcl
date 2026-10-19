# Package the AIEPdiLoader PE as an IP-XACT core for Tapasco.
#   vivado -mode batch -source pack_pdi_loader_kernel.tcl -tclargs <part> <codegen.sv>
# Derived from ../../pack_reflash_kernel.tcl; only the register map and the bus
# interfaces differ (no bulk port).

set PART [lindex $argv 0]
set SV   [lindex $argv 1]
set KERNEL_NAME AIEPdiLoader

create_project ${KERNEL_NAME} ./${KERNEL_NAME} -part $PART
add_files -norecurse [list $SV]
set_property top ${KERNEL_NAME} [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir ./${KERNEL_NAME}_ip -vendor pc2-sus-experiments -library sus-xrt -taxonomy /UserIP -import_files
set_property ipi_drc {ignore_freq_hz false} [ipx::current_core]
set_property sdx_kernel true [ipx::current_core]
set_property sdx_kernel_type rtl [ipx::current_core]
set_property vitis_drc {ctrl_protocol ap_ctrl_hs} [ipx::current_core]
set_property ipi_drc {ignore_freq_hz true} [ipx::current_core]

set CTRL_ADDR_BLOCK [ipx::get_address_blocks reg0 -of_objects [ipx::get_memory_maps s_axi_control -of_objects [ipx::current_core]]]

ipx::add_register CTRL $CTRL_ADDR_BLOCK
set_property description    {Control Signals} [ipx::get_registers CTRL -of_objects $CTRL_ADDR_BLOCK]
set_property address_offset {0x00}            [ipx::get_registers CTRL -of_objects $CTRL_ADDR_BLOCK]
set_property size           {32}              [ipx::get_registers CTRL -of_objects $CTRL_ADDR_BLOCK]

ipx::add_register PDI_ADDRESS $CTRL_ADDR_BLOCK
set_property description    {PS physical address of the partial PDI in card DDR (0x100_0000_0000 + device offset)} [ipx::get_registers PDI_ADDRESS -of_objects $CTRL_ADDR_BLOCK]
set_property address_offset {0x020}           [ipx::get_registers PDI_ADDRESS -of_objects $CTRL_ADDR_BLOCK]
set_property size           {64}              [ipx::get_registers PDI_ADDRESS -of_objects $CTRL_ADDR_BLOCK]

ipx::add_register AXI_CONFIG $CTRL_ADDR_BLOCK
set_property description    {AxPROT bits: [2:0] write, [6:4] read} [ipx::get_registers AXI_CONFIG -of_objects $CTRL_ADDR_BLOCK]
set_property address_offset {0x030}           [ipx::get_registers AXI_CONFIG -of_objects $CTRL_ADDR_BLOCK]
set_property size           {64}              [ipx::get_registers AXI_CONFIG -of_objects $CTRL_ADDR_BLOCK]

# PDI_ADDRESS is a PS address, not a Tapasco buffer handle: no ASSOCIATED_BUSIF, so
# Tapasco does not try to allocate/translate it.

set SMALL_AXIL_BUSIF [ipx::get_bus_interfaces small_axil -of_objects [ipx::current_core]]
set_property value 32 [ipx::add_bus_parameter DATA_WIDTH $SMALL_AXIL_BUSIF]

set_property core_revision 1 [ipx::current_core]
ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::save_core [ipx::current_core]
