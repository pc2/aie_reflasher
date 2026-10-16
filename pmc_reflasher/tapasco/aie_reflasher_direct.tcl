# TaPaSCo plugin sketch for the direct-from-host AI Engine reflasher.
# Copy to $TAPASCO_HOME_TOOLFLOW/vivado/platform/vck5000/plugins/ and enable with
#
#   { "Feature": "AIE-Reflasher-Direct", "Properties": {} }
#
# Goal: let the x86 host reach the Versal IPI block (AXI 0xFF300000, 1 MiB) so it
# can send the PLM the LOAD_SUBSYSTEM_PDI command itself. Two things are needed:
#
#   1. A PCIe window onto AXI 0xFF300000. Done here with a new 64-bit PF0 BAR4
#      (AXI_Bridge_Master, 1 MiB, PCIEBAR2AXIBAR index 2). BAR0/BAR2 stay as
#      Tapasco configured them, so tlkm is unaffected.
#      Alternative without a new BAR: NoC address remap of a 1 MiB window inside
#      BAR0, e.g. on S06_AXI
#        CONFIG.REMAPS {M<nn>_AXI {{0x20103000000 0xFF300000 0x100000}}}
#      (syntax as in Xilinx/AVED create_bd_design.tcl) and run the host tool with
#      --bar 0 --bar-offset 0x3000000.
#
#   2. A NoC path from the CPM ports (S06/S07, category ps_pcie) to the PMC NoC
#      slave (NOC_PMC_AXI_0, category ps_pmc). The PMC NSU forwards to the whole
#      PS address space, LPD included (your address-editor screenshot shows OCM,
#      TCM, PSM and ADMA segments behind NOC_PMC_AXI_0, so the IPI block at
#      0xFF3xxxxx should be there too).
#
# UNVERIFIED pin/parameter names are marked below; check them against the CIPS
# and NoC GUIs once (you already built this path by hand for the PL variant).

if {[tapasco::is_feature_enabled "AIE-Reflasher-Direct"]} {
  namespace eval aie_reflasher_direct {

    proc add_path {{args {}}} {
      set old_inst [current_bd_instance .]
      set cips [get_bd_cells /host/versal_cips_0]
      current_bd_instance "/memory"
      set noc [get_bd_cells axi_noc_0]

      # --- 1. PF0 BAR4 -> AXI 0xFF300000 (1 MiB) -------------------------------
      # CPM_CONFIG merges with what Tapasco already set (versal_base.tcl relies on that).
      set_property -dict [list CONFIG.CPM_CONFIG [list \
        CPM_PCIE0_PF0_BAR4_QDMA_ENABLED {1} \
        CPM_PCIE0_PF0_BAR4_QDMA_TYPE {AXI_Bridge_Master} \
        CPM_PCIE0_PF0_BAR4_QDMA_64BIT {1} \
        CPM_PCIE0_PF0_BAR4_QDMA_PREFETCHABLE {0} \
        CPM_PCIE0_PF0_BAR4_QDMA_SCALE {Megabytes} \
        CPM_PCIE0_PF0_BAR4_QDMA_SIZE {1} \
        CPM_PCIE0_PF0_PCIEBAR2AXIBAR_QDMA_2 {0x00000000FF300000} \
      ]] $cips
      # VERIFY: index _2 is the AXI base of the BAR4/5 pair (Tapasco uses _0 for BAR0/1).

      # --- 2. NoC output to the PMC and connection from the CPM ports -----------
      # VERIFY: PS_PMC_CONFIG key enabling the NoC->PMC slave; ROCm-air's design dumps
      # it as PMC_USE_NOC_PMC_AXI0 (there set to 0).
      set_property -dict [list CONFIG.PS_PMC_CONFIG {PMC_USE_NOC_PMC_AXI0 1}] $cips

      set mi_num [get_property CONFIG.NUM_MI $noc]
      set mi [format "M%02s_AXI" $mi_num]
      set clk_num [get_property CONFIG.NUM_CLKS $noc]
      set_property CONFIG.NUM_MI [expr $mi_num + 1] $noc
      set_property CONFIG.NUM_CLKS [expr $clk_num + 1] $noc
      set_property CONFIG.CATEGORY {ps_pmc} [get_bd_intf_pins $noc/$mi]

      foreach si {S06_AXI S07_AXI} {
        set conns [get_property CONFIG.CONNECTIONS [get_bd_intf_pins $noc/$si]]
        lappend conns $mi {read_bw {5} write_bw {5} read_avg_burst {4} write_avg_burst {4}}
        set_property CONFIG.CONNECTIONS $conns [get_bd_intf_pins $noc/$si]
      }

      # VERIFY pin names on the CIPS: NOC_PMC_AXI_0 and its clock.
      connect_bd_intf_net [get_bd_intf_pins $noc/$mi] [get_bd_intf_pins $cips/NOC_PMC_AXI_0]
      connect_bd_net [get_bd_pins $cips/noc_pmc_axi_axi0_clk] [get_bd_pins $noc/aclk$clk_num]
      set_property CONFIG.ASSOCIATED_BUSIF $mi [get_bd_pins $noc/aclk$clk_num]

      current_bd_instance $old_inst
      return $args
    }

    proc assign_pmc_segments {{args {}}} {
      # The PS slaves have fixed addresses; let Vivado place them in the CPM
      # master address spaces so the NoC routes 0xFF3xxxxx to the PMC output.
      assign_bd_address -quiet
      return $args
    }
  }

  tapasco::register_plugin "platform::aie_reflasher_direct::add_path" "pre-wiring"
  tapasco::register_plugin "platform::aie_reflasher_direct::assign_pmc_segments" "post-address-map"
}
