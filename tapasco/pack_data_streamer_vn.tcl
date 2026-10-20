# Package the DataStreamerVN PE (SUS version) as an IP-XACT core for Tapasco.
#   vivado -mode batch -source pack_data_streamer_vn.tcl -tclargs <part> <codegen.sv>
# Bus interfaces are inferred from the port names: s_axi_control (AXI4-Lite slave),
# S_AXIS_DMA / M_AXIS_DMA (512-bit streams to the QDMA, DMA-Streaming feature),
# M_AXIS_AIE_X / M_AXIS_AIE_Y / S_AXIS_AIE (128-bit streams to the AI Engine PLIOs,
# AI-Engine feature matches them by name and TDATA_NUM_BYTES = 16).
# Registers: CTRL 0x00, return value 0x10 (cycles), SAMPLES 0x20 (64 bit).

set PART [lindex $argv 0]
set SV   [lindex $argv 1]
set KERNEL_NAME DataStreamerVN

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

foreach busif {s_axi_control S_AXIS_DMA M_AXIS_DMA M_AXIS_AIE_X M_AXIS_AIE_Y S_AXIS_AIE} {
  if {[llength [ipx::get_bus_interfaces $busif -of_objects [ipx::current_core]]] == 0} {
    error "pack_data_streamer_vn: bus interface $busif was not inferred from the port names"
  }
}

set CTRL_ADDR_BLOCK [ipx::get_address_blocks reg0 -of_objects [ipx::get_memory_maps s_axi_control -of_objects [ipx::current_core]]]

ipx::add_register CTRL $CTRL_ADDR_BLOCK
set_property description    {Control Signals} [ipx::get_registers CTRL -of_objects $CTRL_ADDR_BLOCK]
set_property address_offset {0x00}            [ipx::get_registers CTRL -of_objects $CTRL_ADDR_BLOCK]
set_property size           {32}              [ipx::get_registers CTRL -of_objects $CTRL_ADDR_BLOCK]

ipx::add_register SAMPLES $CTRL_ADDR_BLOCK
set_property description    {Number of (x, y) sample pairs; a multiple of 16. Result beats = SAMPLES / 16.} [ipx::get_registers SAMPLES -of_objects $CTRL_ADDR_BLOCK]
set_property address_offset {0x020}           [ipx::get_registers SAMPLES -of_objects $CTRL_ADDR_BLOCK]
set_property size           {64}              [ipx::get_registers SAMPLES -of_objects $CTRL_ADDR_BLOCK]

set_property core_revision 1 [ipx::current_core]
ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::save_core [ipx::current_core]
