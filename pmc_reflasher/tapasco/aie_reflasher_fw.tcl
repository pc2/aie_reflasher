# TaPaSCo plugin for the PMC-based AI Engine reflasher.
# Copy to $TAPASCO_HOME_TOOLFLOW/vivado/platform/vck5000/plugins/ and enable with
#
#   { "Feature": "AIE-Reflasher",
#     "Properties": { "elf": "/path/to/aie_reflasher.elf",   # optional
#                     "enable_ipi": "false" } }               # optional
#
# What it does:
#   post-bitstream : exports tapasco_vck5000.xsa next to the project (input for
#                    firmware/build_arm.tcl) and, if "elf" is given, wraps the
#                    final PDI so the PLM boots the firmware on A72 #0.
#   pre-wiring     : (only with enable_ipi=true) explicitly assigns IPI0 to the
#                    A72 in the CIPS. The CIPS default already does this; use it
#                    only if the generated BSP has no XPAR_XIPIPSU_0_*.
#
# The NoC needs no change: Tapasco's base platform already connects the A72
# (ps_cci ports) to the DDR controllers and the PMC (ps_pmc port) to the AIE.

if {[tapasco::is_feature_enabled "AIE-Reflasher"]} {
  namespace eval aie_reflasher {

    proc enable_ipi {{args {}}} {
      if {[tapasco::get_feature_option "AIE-Reflasher" "enable_ipi" "false"] != "true"} {
        return $args
      }
      set cips [get_bd_cells /host/versal_cips_0]
      # PS_PMC_CONFIG merges with the existing dictionary (Tapasco relies on that too)
      set_property -dict [list CONFIG.PS_PMC_CONFIG { \
        PS_GEN_IPI0_ENABLE 1 PS_GEN_IPI0_MASTER A72 \
      }] $cips
      return $args
    }

    proc post_bitstream {{args {}}} {
      global bitstreamname
      set prjdir [get_property DIRECTORY [current_project]]

      set xsa "$prjdir/tapasco_vck5000.xsa"
      puts "AIE-Reflasher: exporting $xsa"
      write_hw_platform -fixed -force -file $xsa

      set elf [tapasco::get_feature_option "AIE-Reflasher" "elf" ""]
      if {$elf == ""} {
        puts "AIE-Reflasher: no elf given, PDI left without firmware (load it with xsdb)"
        return $args
      }
      if {![file exists $elf]} {
        error "AIE-Reflasher: elf not found: $elf"
      }
      exec mv ${bitstreamname}.pdi $prjdir/${bitstreamname}_nofw.pdi
      set bif [open "$prjdir/tapasco_aie_reflasher.bif" "w"]
      puts $bif "all: {"
      puts $bif " image { { type=bootimage, file=$prjdir/${bitstreamname}_nofw.pdi } }"
      puts $bif " image { name=default_subsys, id=0x1c000000 { core=a72-0, file=$elf } }"
      puts $bif "}"
      close $bif
      exec bootgen -arch versal -image $prjdir/tapasco_aie_reflasher.bif -w -o ${bitstreamname}.pdi
      puts "AIE-Reflasher: embedded $elf into ${bitstreamname}.pdi"
      return $args
    }
  }

  tapasco::register_plugin "platform::aie_reflasher::enable_ipi" "pre-wiring"
  tapasco::register_plugin "platform::aie_reflasher::post_bitstream" "post-bitstream"
}
