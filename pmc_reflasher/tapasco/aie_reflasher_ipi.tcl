# CIPS / wiring changes for the PE-initiated IPI reflasher.
#
# 1. enable_ipi5: enable IPI5 in the CIPS. Gives the PE's masters the segment
#    psv_ipi_5 (0xFF380000). Already done in your build.
#
# 2. lpd_port: give the PE a direct PL-to-LPD slave port (S_AXI_LPD) and route
#    it from the existing join SmartConnect. Reason: Vivado's CIPS model exposes
#    the IPI message RAM (psv_ipi_buffer, 0xFF3F0000, 4 KiB) only on the direct
#    PL-to-PS slave ports (S_AXI_LPD / S_AXI_GP2), never on the NoC-side
#    NOC_PMC_AXI_0 port (checked against AMD's vck190_axi_cci_bd.tcl: 109
#    segments on S_AXI_LPD incl. psv_ipi_buffer; the NoC ports list psv_ipi_0..6
#    but no buffer). With S_AXI_LPD the SmartConnect decodes 0xFFxxxxxx to the
#    LPD port and everything else (DDR, AIE, PMC) to the NoC as before.
#
# Both procs merge into the existing PS_PMC_CONFIG dictionary. Register them in
# aie_reconfig.tcl or as their own plugin:
#
#   tapasco::register_plugin "platform::aie_reflasher_ipi::enable_ipi5" "pre-wiring"
#   tapasco::register_plugin "platform::aie_reflasher_ipi::lpd_port"    "pre-wrapper"
#
# lpd_port must run after your join_small_and_bulk_ports (post-pe-create) has
# created /arch/target_ip_01_000/join_bulk_and_small_ic, and before address
# assignment. Pin and parameter names marked VERIFY come from PG352 / the AMD
# reference design and were not checked against 2023.1 in this repo.

namespace eval aie_reflasher_ipi {

  proc delete_ipi_connection_to_mem {args} {
    save_bd_design
    
    delete_bd_objs [get_bd_intf_nets arch/out_0_M000_AXI] [get_bd_intf_nets arch/target_ip_01_000_ipi_lpd_interface] [get_bd_cells arch/out_0]
    delete_bd_objs [get_bd_intf_pins arch/M_MEM_0]
  }
  proc connect_ipi_lpd_port {args} {
    save_bd_design
    
    puts "Running connect_ipi_lpd_port: $args"

    set cips [get_bd_cells /host/versal_cips_0]
    # set ic   [get_bd_cells /arch/target_ip_01_000/join_bulk_and_small_ic]
    set reflasher [get_bd_cells /arch/target_ip_01_000/internal_target_ip_01_000]

    # S_AXI_LPD is a direct PL-to-PS port. Do NOT route it through the NoC: a NoC
    # output toward it gets a 1 GB PL_LO aperture (0x201_8000_0000) that can never
    # intersect the fixed LPD addresses, and the NoC decodes 0xFFxxxxxx to the PS
    # NSU in hardware anyway. Vivado then excludes every LPD segment (BD 41-1743).
    set_property -dict [list CONFIG.PS_PMC_CONFIG { \
      PS_GEN_IPI5_ENABLE 1 PS_GEN_IPI5_MASTER A72 \
      PS_USE_S_AXI_LPD 1 PS_S_AXI_LPD_DATA_WIDTH 32 \
    }] $cips
    puts "aie_reflasher_ipi: IPI5 enabled on CIPS"
    
    connect_bd_intf_net -boundary_type upper [get_bd_intf_pins $reflasher/ipi_lpd_interface] \
                                             [get_bd_intf_pins $cips/S_AXI_LPD]
    connect_bd_net [get_bd_pins $cips/s_axi_lpd_aclk] [get_bd_pins arch/design_clk]

    save_bd_design
  }
}

if {[tapasco::is_feature_enabled "aie_reflasher_ipi"]} {
  tapasco::register_plugin "platform::aie_reflasher_ipi::connect_ipi_lpd_port" "pre-wiring"
  tapasco::register_plugin "platform::aie_reflasher_ipi::delete_ipi_connection_to_mem" "pre-platform"
}
