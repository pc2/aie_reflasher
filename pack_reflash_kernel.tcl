set PART [lindex $argv 0]
# set XO_FILE [lindex $argv 1]

# set PART xcvc1902-vsvd1760-2MP-e-S


set KERNEL_NAME AIEngineReflasher

create_project ${KERNEL_NAME} ./${KERNEL_NAME} -part $PART

add_files -norecurse \
{
    ../reflasher_codegen.sv \
}

set_property top ${KERNEL_NAME} [current_fileset]

update_compile_order -fileset sources_1

ipx::package_project -root_dir ./${KERNEL_NAME}_ip -vendor pc2-sus-experiments -library sus-xrt -taxonomy /UserIP -import_files

#                                ???
# ipx::infer_bus_interface aclk  xilinx.com:signal:clock_rtl:1.0 [ipx::current_core]
# ipx::infer_bus_interface aresetn xilinx.com:signal:reset_rtl:1.0 [ipx::current_core]
# ipx::associate_bus_interfaces -clock aclk -reset aresetn [ipx::current_core]
# ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces aclk -of_objects [ipx::current_core]]

set_property ipi_drc {ignore_freq_hz false} [ipx::current_core]
set_property sdx_kernel true [ipx::current_core]
set_property sdx_kernel_type rtl [ipx::current_core]
set_property vitis_drc {ctrl_protocol ap_ctrl_hs} [ipx::current_core]
set_property ipi_drc {ignore_freq_hz true} [ipx::current_core]

# s_axi_control MUST be named as such
# ipx::associate_bus_interfaces -busif s_axi_control -clock aclk [ipx::current_core]
#ipx::associate_bus_interfaces -busif outstream -clock aclk [ipx::current_core]
# ipx::associate_bus_interfaces -busif m_axi -clock aclk [ipx::current_core]


set CTRL_ADDR_BLOCK [ipx::get_address_blocks reg0 -of_objects [ipx::get_memory_maps s_axi_control -of_objects [ipx::current_core]]]

# Address offset in bytes???
ipx::add_register CTRL $CTRL_ADDR_BLOCK
set_property description    {Control Signals} [ipx::get_registers CTRL -of_objects $CTRL_ADDR_BLOCK]
set_property address_offset {0x00}            [ipx::get_registers CTRL -of_objects $CTRL_ADDR_BLOCK]
set_property size           {32}              [ipx::get_registers CTRL -of_objects $CTRL_ADDR_BLOCK]

ipx::add_register COMMANDS_ADDRESS $CTRL_ADDR_BLOCK
set_property description    {command buffer address}  [ipx::get_registers COMMANDS_ADDRESS  -of_objects $CTRL_ADDR_BLOCK]
set_property address_offset {0x020}                   [ipx::get_registers COMMANDS_ADDRESS  -of_objects $CTRL_ADDR_BLOCK]
set_property size           {64}                      [ipx::get_registers COMMANDS_ADDRESS  -of_objects $CTRL_ADDR_BLOCK]

ipx::add_register COMMAND_MEM_LENGTH $CTRL_ADDR_BLOCK
set_property description    {number of 32bit elements}      [ipx::get_registers COMMAND_MEM_LENGTH  -of_objects $CTRL_ADDR_BLOCK]
set_property address_offset {0x030}                         [ipx::get_registers COMMAND_MEM_LENGTH  -of_objects $CTRL_ADDR_BLOCK]
set_property size           {32}                            [ipx::get_registers COMMAND_MEM_LENGTH  -of_objects $CTRL_ADDR_BLOCK]

ipx::add_register AXI_CONFIG_LINES $CTRL_ADDR_BLOCK
set_property description    {aw and ar axi config params}   [ipx::get_registers AXI_CONFIG_LINES  -of_objects $CTRL_ADDR_BLOCK]
set_property address_offset {0x040}                         [ipx::get_registers AXI_CONFIG_LINES  -of_objects $CTRL_ADDR_BLOCK]
set_property size           {64}                            [ipx::get_registers AXI_CONFIG_LINES  -of_objects $CTRL_ADDR_BLOCK]

ipx::add_register_parameter ASSOCIATED_BUSIF [ipx::get_registers COMMANDS_ADDRESS -of_objects $CTRL_ADDR_BLOCK]
set_property value          {bulk_axi}          [ipx::get_register_parameters ASSOCIATED_BUSIF -of_objects [ipx::get_registers COMMANDS_ADDRESS -of_objects $CTRL_ADDR_BLOCK]]
ipx::add_register_parameter ASSOCIATED_BUSIF [ipx::get_registers COMMANDS_ADDRESS -of_objects $CTRL_ADDR_BLOCK]
set_property value          {small_axil}          [ipx::get_register_parameters ASSOCIATED_BUSIF -of_objects [ipx::get_registers COMMANDS_ADDRESS -of_objects $CTRL_ADDR_BLOCK]]

set BULK_AXI_BUSIF [ipx::get_bus_interfaces bulk_axi -of_objects [ipx::current_core]]
set_property value           32 [ipx::add_bus_parameter DATA_WIDTH $BULK_AXI_BUSIF]

set SMALL_AXIL_BUSIF [ipx::get_bus_interfaces small_axil -of_objects [ipx::current_core]]
set_property value           32 [ipx::add_bus_parameter DATA_WIDTH $SMALL_AXIL_BUSIF]

set_property core_revision 2 [ipx::current_core]
ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
# ipx::check_integrity -kernel -xrt [ipx::current_core]
ipx::save_core [ipx::current_core]

# package_xo -xo_path $XO_FILE -kernel_name ${KERNEL_NAME} -ctrl_protocol ap_ctrl_hs -ip_directory ./${KERNEL_NAME}_ip
 # -output_kernel_xml ../../${KERNEL_NAME}.xml
