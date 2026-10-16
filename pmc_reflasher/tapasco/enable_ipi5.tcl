# Enable IPI5 in the CIPS so that the PE's AXI-Lite master gets address segments
# for the IPI5 register block (psv_ipi_5, 0xFF380000) and the IPI message RAM
# (psv_ipi_buffer, 0xFF3F0000). Without this the NoC has nowhere to route them.
#
# Paste the body of this proc at the top of aie_reconfig::setup_aie_noc_connection
# (before its assign_bd_address), or register it as its own pre-wiring plugin:
#
#   tapasco::register_plugin "platform::aie_reflasher_ipi::enable" "pre-wiring"
#
# PS_PMC_CONFIG is a merge, so the other CIPS settings are kept.
# IPI5 is the channel the PLM reserves for the xsdb debug master; the "master"
# we give it here only affects BSP generation, nothing in hardware.

namespace eval aie_reflasher_ipi {
  proc enable {{args {}}} {
    set cips [get_bd_cells /host/versal_cips_0]
    set_property -dict [list CONFIG.PS_PMC_CONFIG { \
      PS_GEN_IPI5_ENABLE 1 PS_GEN_IPI5_MASTER A72 \
    }] $cips
    puts "aie_reflasher_ipi: IPI5 enabled on CIPS"
    return $args
  }
}
