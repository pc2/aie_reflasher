# Tapasco plugin: connect the AIEPdiLoader PE's ipi_lpd_interface straight to the CIPS
# S_AXI_LPD port (direct PL-to-LPD path, never through the NoC) and enable all IPI
# channels. The PE selects the channel per request (IPI_CONFIG[2:0]; host default IPI2,
# IPI5 is xsdb's), so psv_ipi_0..5 and psv_ipi_buffer must all be mapped into its address
# space; that is checked after assign_bd_address below.
#
# Why S_AXI_LPD: Vivado's CIPS model exposes the IPI message RAM (psv_ipi_buffer,
# 0xFF3F0000, 4 KiB) only on the direct PL-to-PS slave ports, never on the NoC-side
# NOC_PMC_AXI_0 port. A NoC output toward it would get a 1 GB PL_LO aperture that can
# never intersect the fixed LPD addresses (BD 41-1743).
#
# Address handling: S_AXI_LPD exposes ~100 fixed-address PS/PMC segments. Connecting the
# port in the "post-platform" hook (after Tapasco's own construct_address_map) and then
# calling assign_bd_address lets Vivado place them all at their fixed addresses.
#
# Enable with  { "Feature": "aie_reflasher_plugin", "Properties": { "ila": "false" } }.

namespace eval aie_reflasher_plugin {

  variable PE_SPACE /arch/target_ip_01_000/internal_target_ip_01_000/ipi_lpd_interface

  # "pre-platform": the PE's master was auto-connected to the memory subsystem by the
  # arch; remove that so it can go to the CIPS instead.
  proc delete_ipi_connection_to_mem {args} {
    save_bd_design
    delete_bd_objs [get_bd_intf_nets arch/out_0_M000_AXI] \
                   [get_bd_intf_nets arch/target_ip_01_000_ipi_lpd_interface] \
                   [get_bd_cells arch/out_0]
    delete_bd_objs [get_bd_intf_pins arch/M_MEM_0]
    return $args
  }

  # "pre-wiring": CIPS config + direct connection, and install the ignore-list override
  # (versal_base.tcl is certainly loaded by now; the override is consulted later by
  # addressmap::construct_address_map).
  proc connect_ipi_lpd_port {args} {
    save_bd_design
    puts "Running connect_ipi_lpd_port: $args"

    set cips      [get_bd_cells /host/versal_cips_0]
    set reflasher [get_bd_cells /arch/target_ip_01_000/internal_target_ip_01_000]

    # ALL IPI channels must exist in the design: the per-design 2023.1 PLM sizes its IPI
    # handling by XPAR_XIPIPSU_NUM_TARGETS (= IPI instances present) and its interrupt
    # handler only scans ISR bits 0..NUM_TARGETS-1. With IPI0-4 absent that is 0..3 and
    # IPI5 (bit 7) is masked and dropped silently (breaks xsdb plm commands too).
    set_property -dict [list CONFIG.PS_PMC_CONFIG { \
      PS_GEN_IPI0_ENABLE 1 PS_GEN_IPI0_MASTER S_AXI_GP4 \
      PS_GEN_IPI1_ENABLE 1 PS_GEN_IPI1_MASTER S_AXI_GP4 \
      PS_GEN_IPI2_ENABLE 1 PS_GEN_IPI2_MASTER S_AXI_GP4 \
      PS_GEN_IPI3_ENABLE 1 PS_GEN_IPI3_MASTER S_AXI_GP4 \
      PS_GEN_IPI4_ENABLE 1 PS_GEN_IPI4_MASTER S_AXI_GP4 \
      PS_GEN_IPI5_ENABLE 1 PS_GEN_IPI5_MASTER S_AXI_GP4 \
      PS_GEN_IPI6_ENABLE 1 PS_GEN_IPI6_MASTER S_AXI_GP4 \
      PS_USE_S_AXI_LPD 1 PS_S_AXI_LPD_DATA_WIDTH 32 \
    }] $cips
    puts "aie_reflasher_plugin: IPI0..6 + S_AXI_LPD enabled on CIPS"

    connect_bd_intf_net -boundary_type upper [get_bd_intf_pins $reflasher/ipi_lpd_interface] [get_bd_intf_pins $cips/S_AXI_LPD]

    save_bd_design
    set cips      [get_bd_cells /host/versal_cips_0]
    connect_bd_net [get_bd_pins $cips/s_axi_lpd_aclk] [get_bd_pins clocks_and_resets/design_clk]

    # Optional AXI ILA on the LPD port (Properties {"ila": "true"}); the probe file is written
    # next to the bitstream by write_ltx.
    if {[tapasco::get_feature_option "aie_reflasher_plugin" "ila" "false"] == "true"} {
      create_bd_cell -type ip -vlnv xilinx.com:ip:axis_ila:1.2 ipi_lpd_ila
      set_property -dict [list \
        CONFIG.C_DATA_DEPTH {32768} \
        CONFIG.C_MON_TYPE {Interface_Monitor} \
      ] [get_bd_cells ipi_lpd_ila]
      connect_bd_intf_net [get_bd_intf_pins ipi_lpd_ila/SLOT_0_AXI] -boundary_type upper [get_bd_intf_pins arch/ipi_lpd_interface]
      connect_bd_net [get_bd_pins ipi_lpd_ila/clk] [get_bd_pins clocks_and_resets/design_clk]
      connect_bd_net [get_bd_pins ipi_lpd_ila/resetn] [get_bd_pins clocks_and_resets/design_peripheral_aresetn]
      puts "aie_reflasher_plugin: ILA on ipi_lpd_interface added"
    }
    assign_bd_address
  }

  proc write_ltx {args} {
    if {[tapasco::get_feature_option "aie_reflasher_plugin" "ila" "false"] == "true"} {
      write_debug_probes debug_probes.ltx
    }
    return $args
  }
}

if {[tapasco::is_feature_enabled "aie_reflasher_plugin"]} {
  tapasco::register_plugin "platform::aie_reflasher_plugin::delete_ipi_connection_to_mem" "pre-platform"
  tapasco::register_plugin "platform::aie_reflasher_plugin::connect_ipi_lpd_port"         "post-platform"
  tapasco::register_plugin "platform::aie_reflasher_plugin::write_ltx"           "post-bitstream"
}
