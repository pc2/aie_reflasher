# Tapasco plugin: connect the AIEPdiLoader PE's ipi_lpd_interface straight to the CIPS
# S_AXI_LPD port (direct PL-to-LPD path, never through the NoC) and enable IPI5.
#
# Why S_AXI_LPD: Vivado's CIPS model exposes the IPI message RAM (psv_ipi_buffer,
# 0xFF3F0000, 4 KiB) only on the direct PL-to-PS slave ports, never on the NoC-side
# NOC_PMC_AXI_0 port. A NoC output toward it would get a 1 GB PL_LO aperture that can
# never intersect the fixed LPD addresses (BD 41-1743).
#
# Address handling: S_AXI_LPD exposes ~100 fixed-address PS/PMC segments. Tapasco's
# addressmap::construct_address_map (runs between "pre-wiring" and validate) tries to
# place every segment a PE master can reach, starting at offset 0, which Vivado rejects
# for fixed-address slaves (BD 41-1075 on psv_pmc_qspi_ospi_flash_0). So:
#   1. extend platform::get_ignored_segments with every S_AXI_LPD segment, and
#   2. in the "post-address-map" hook (called inside construct_address_map, before its
#      segment loop) assign the two segments we need at their fixed addresses and
#      exclude all the others from the PE's address space.
#
# Enable with  { "Feature": "aie_reflasher_ipi", "Properties": {} }.

namespace eval aie_reflasher_ipi {

  variable PE_SPACE /arch/target_ip_01_000/internal_target_ip_01_000/ipi_lpd_interface
  variable WANTED   {pspmc_0_psv_ipi_5 pspmc_0_psv_ipi_buffer}

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

    # ALL IPI channels must be enabled, not just IPI5. The 2023.1 PLM is compiled per
    # design and sizes its IPI handling by XPAR_XIPIPSU_NUM_TARGETS (= number of IPI
    # instances in the design). Its interrupt handler loops over ISR bit indices
    # 0..NUM_TARGETS-1; with IPI0-4 disabled that is 0..3, so bit 7 (IPI5) is masked
    # and silently dropped: no task, no ack, no log line (also breaks xsdb's plm cmds).
    set_property -dict [list CONFIG.PS_PMC_CONFIG { \
      PS_GEN_IPI0_ENABLE 1 PS_GEN_IPI0_MASTER A72 \
      PS_GEN_IPI1_ENABLE 1 PS_GEN_IPI1_MASTER A72 \
      PS_GEN_IPI2_ENABLE 1 PS_GEN_IPI2_MASTER A72 \
      PS_GEN_IPI3_ENABLE 1 PS_GEN_IPI3_MASTER A72 \
      PS_GEN_IPI4_ENABLE 1 PS_GEN_IPI4_MASTER A72 \
      PS_GEN_IPI5_ENABLE 1 PS_GEN_IPI5_MASTER A72 \
      PS_GEN_IPI6_ENABLE 1 PS_GEN_IPI6_MASTER A72 \
      PS_USE_S_AXI_LPD 1 PS_S_AXI_LPD_DATA_WIDTH 32 \
    }] $cips
    puts "aie_reflasher_ipi: IPI0..6 + S_AXI_LPD enabled on CIPS"

    connect_bd_intf_net -boundary_type upper [get_bd_intf_pins $reflasher/ipi_lpd_interface] \
                                             [get_bd_intf_pins $cips/S_AXI_LPD]
    connect_bd_net [get_bd_pins $cips/s_axi_lpd_aclk] [get_bd_pins arch/design_clk]

    if {[llength [info procs ::platform::get_ignored_segments_base]] == 0} {
      rename ::platform::get_ignored_segments ::platform::get_ignored_segments_base
      proc ::platform::get_ignored_segments {} {
        set ignored [::platform::get_ignored_segments_base]
        foreach seg [get_bd_addr_segs -quiet /host/versal_cips_0/S_AXI_LPD/*] {
          lappend ignored $seg
        }
        return $ignored
      }
      puts "aie_reflasher_ipi: S_AXI_LPD segments added to Tapasco's ignore list"
    }

    save_bd_design
    return $args
  }

  # "post-address-map": runs inside construct_address_map before its segment loop.
  # Assign psv_ipi_5 and psv_ipi_buffer at their fixed addresses, exclude the rest.
  proc assign_ipi_segments {args} {
    variable PE_SPACE
    variable WANTED
    set space [get_bd_addr_spaces $PE_SPACE]
    foreach seg [get_bd_addr_segs -quiet /host/versal_cips_0/S_AXI_LPD/*] {
      set name [get_property NAME $seg]
      if {[lsearch $WANTED $name] >= 0} {
        assign_bd_address -target_address_space $space $seg
        puts "aie_reflasher_ipi: assigned $seg -> [get_property OFFSET $seg] [get_property RANGE $seg]"
      } else {
        catch {exclude_bd_addr_seg -target_address_space $space $seg}
      }
    }
    return $args
  }

  proc write_debug_probes {} {
    write_debug_probes debug_probes.ltx
  }
}

if {[tapasco::is_feature_enabled "aie_reflasher_ipi"]} {
  tapasco::register_plugin "platform::aie_reflasher_ipi::delete_ipi_connection_to_mem" "pre-platform"
  tapasco::register_plugin "platform::aie_reflasher_ipi::connect_ipi_lpd_port"         "pre-wiring"
  tapasco::register_plugin "platform::aie_reflasher_ipi::assign_ipi_segments"          "post-address-map"
  tapasco::register_plugin "platform::aie_reflasher_ipi::write_debug_probes"           "post-bitstream"
}
