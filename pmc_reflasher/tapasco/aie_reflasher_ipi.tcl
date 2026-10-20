# Tapasco plugin: connect the AIEPdiLoader PE's ipi_lpd_interface straight to the CIPS
# S_AXI_LPD port (direct PL-to-LPD path, never through the NoC) and enable all IPI
# channels. The PE selects the channel per request (AXI_CONFIG[18:16]), so psv_ipi_0..5
# and psv_ipi_buffer must all be mapped into its address space; that is checked below.
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

    # ALL IPI channels must exist in the design: the per-design 2023.1 PLM sizes its IPI
    # handling by XPAR_XIPIPSU_NUM_TARGETS (= IPI instances present) and its interrupt
    # handler only scans ISR bits 0..NUM_TARGETS-1. With IPI0-4 absent that is 0..3 and
    # IPI5 (bit 7) is masked and dropped silently (breaks xsdb plm commands too).
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

    connect_bd_intf_net -boundary_type upper [get_bd_intf_pins $reflasher/ipi_lpd_interface] [get_bd_intf_pins $cips/S_AXI_LPD]

    save_bd_design
    set cips      [get_bd_cells /host/versal_cips_0]
    connect_bd_net [get_bd_pins $cips/s_axi_lpd_aclk] [get_bd_pins clocks_and_resets/design_clk]

    # Also add an ILA
    create_bd_cell -type ip -vlnv xilinx.com:ip:axis_ila:1.2 ipi_lpd_ila
    set_property -dict [list \
      CONFIG.C_DATA_DEPTH {32768} \
      CONFIG.C_MON_TYPE {Interface_Monitor} \
    ] [get_bd_cells ipi_lpd_ila]
    connect_bd_intf_net [get_bd_intf_pins ipi_lpd_ila/SLOT_0_AXI] -boundary_type upper [get_bd_intf_pins arch/ipi_lpd_interface]
    connect_bd_net [get_bd_pins ipi_lpd_ila/clk] [get_bd_pins clocks_and_resets/design_clk]
    connect_bd_net [get_bd_pins ipi_lpd_ila/resetn] [get_bd_pins clocks_and_resets/design_peripheral_aresetn]
    assign_bd_address

    # The PE picks the IPI channel at runtime: every channel with a message buffer
    # (IPI0..5) plus the message RAM must be mapped at its fixed LPD address. IPI5 and
    # the buffer are mandatory (default path); the others only matter for --ipi N.
    set space [get_bd_addr_spaces $PE_SPACE]
    foreach name {psv_ipi_0 psv_ipi_1 psv_ipi_2 psv_ipi_3 psv_ipi_4 psv_ipi_5 psv_ipi_buffer} {
      set segs [get_bd_addr_segs -quiet -of_objects $space -filter "NAME =~ *_${name}"]
      if {[llength $segs] == 0} {
        if {$name eq "psv_ipi_5" || $name eq "psv_ipi_buffer"} {
          error "aie_reflasher_ipi: $name is not mapped in $PE_SPACE"
        }
        puts "WARNING aie_reflasher_ipi: $name not mapped in $PE_SPACE (only --ipi N needs it)"
      } else {
        puts "aie_reflasher_ipi: $name -> [get_property OFFSET $segs] ([get_property RANGE $segs])"
      }
    }
  }

  proc write_ltx {} {
    write_debug_probes debug_probes.ltx
  }
}

if {[tapasco::is_feature_enabled "aie_reflasher_ipi"]} {
  tapasco::register_plugin "platform::aie_reflasher_ipi::delete_ipi_connection_to_mem" "pre-platform"
  tapasco::register_plugin "platform::aie_reflasher_ipi::connect_ipi_lpd_port"         "post-platform"
  tapasco::register_plugin "platform::aie_reflasher_ipi::write_ltx"           "post-bitstream"
}
