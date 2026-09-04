# This is a plugin for TaPaSCo, which effects the PE AXI4-Master connections.
# It will instantiate the V80 HBM-NoC and DDR-NoC and connect the PE as desired.
# How to use:
#   1. Copy this plugin file to $TAPASCO_HOME_TOOLFLOW/vivado/platform/v80/plugins/
#   2. Run `tapasco --jobsFile job.json` using the job.json file from this directory.

namespace eval aie_reconfig {
    proc join_small_and_bulk_ports { pe unused } {
        puts "aie_reconfig::join_small_and_bulk_ports"
        set pe [get_bd_cells $pe]
        set group [current_bd_instance .]

        puts "pe: $pe, group: $group, unused?: $unused"

        if {$pe == "/arch/target_ip_01_000/internal_target_ip_01_000"} {
            save_bd_design

            set found_cells [get_bd_cells]
            puts "$group found $found_cells"

            create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 join_bulk_and_small_ic

            save_bd_design

            delete_bd_objs [get_bd_intf_nets /arch/target_ip_01_000/internal_target_ip_01_000_bulk_axi]

            save_bd_design

            connect_bd_intf_net [get_bd_intf_pins /arch/target_ip_01_000/internal_target_ip_01_000/bulk_axi] [get_bd_intf_pins /arch/target_ip_01_000/join_bulk_and_small_ic/S00_AXI]
            connect_bd_intf_net [get_bd_intf_pins /arch/target_ip_01_000/internal_target_ip_01_000/small_axil] [get_bd_intf_pins /arch/target_ip_01_000/join_bulk_and_small_ic/S01_AXI]
            connect_bd_intf_net [get_bd_intf_pins /arch/target_ip_01_000/bulk_axi] [get_bd_intf_pins /arch/target_ip_01_000/join_bulk_and_small_ic/M00_AXI]

            puts "DID ADD SWITCH"
            save_bd_design
        }


    }
    proc setup_aie_noc_connection {} {
        puts "aie_reconfig::setup_aie_noc_connection"
        save_bd_design

        # Remove the offset thing
        delete_bd_objs [get_bd_intf_nets memory/arch_offset_0_M_AXI] [get_bd_intf_nets memory/S_MEM_0_1] [get_bd_nets memory/design_peripheral_aresetn_1] [get_bd_cells memory/arch_offset_0]
        connect_bd_intf_net -boundary_type upper [get_bd_intf_pins memory/S_MEM_0] [get_bd_intf_pins memory/axi_noc_0/S08_AXI]

        # And set up a connection to the AIE
        set_property -dict [list CONFIG.CONNECTIONS {M01_AXI {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4}} MC_1 {read_bw {1000} write_bw {1000} read_avg_burst {4} write_avg_burst {4}}}] [get_bd_intf_pins /memory/axi_noc_0/S08_AXI]

        assign_bd_address

        save_bd_design

        # Also add debug core here
        set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {/arch/target_ip_01_000/internal_target_ip_01_000_bulk_axi}]
        set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {/arch/target_ip_01_000/internal_target_ip_01_000_small_axil}]
        set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {/arch/target_ip_01_000/join_bulk_and_small_ic_M00_AXI}]

        apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
            [get_bd_intf_nets {/arch/target_ip_01_000/internal_target_ip_01_000_bulk_axi}] {AXI_R_ADDRESS "Data and Trigger" AXI_R_DATA "Data and Trigger" AXI_W_ADDRESS "Data and Trigger" AXI_W_DATA "Data and Trigger" AXI_W_RESPONSE "Data and Trigger" CLK_SRC "/clocks_and_resets/design_clk_wiz/clk_out1" AXIS_ILA "Auto" APC_EN "0" } \
            [get_bd_intf_nets {/arch/target_ip_01_000/internal_target_ip_01_000_small_axil}] {AXI_R_ADDRESS "Data and Trigger" AXI_R_DATA "Data and Trigger" AXI_W_ADDRESS "Data and Trigger" AXI_W_DATA "Data and Trigger" AXI_W_RESPONSE "Data and Trigger" CLK_SRC "/clocks_and_resets/design_clk_wiz/clk_out1" AXIS_ILA "Auto" APC_EN "0" } \
            [get_bd_intf_nets {/arch/target_ip_01_000/join_bulk_and_small_ic_M00_AXI}] {AXI_R_ADDRESS "Data and Trigger" AXI_R_DATA "Data and Trigger" AXI_W_ADDRESS "Data and Trigger" AXI_W_DATA "Data and Trigger" AXI_W_RESPONSE "Data and Trigger" CLK_SRC "/clocks_and_resets/design_clk_wiz/clk_out1" AXIS_ILA "Auto" APC_EN "0" } \
        ]

        set_property -dict [list \
            CONFIG.C_DATA_DEPTH {16384} \
            CONFIG.C_EN_STRG_QUAL {1} \
            CONFIG.C_INPUT_PIPE_STAGES {3} \
            CONFIG.C_MEMORY_TYPE {1} \
        ] [get_bd_cells axis_ila_0]
    }
    proc address_map {{args {}}} {
        puts "aie_reconfig::addressmap"
        save_bd_design

        assign_bd_address -target_address_space /arch/target_ip_01_000/internal_target_ip_01_000/bulk_axi [get_bd_addr_segs memory/arch_offset_0/S_AXI/reg0 /aie/ai_engine_0/S00_AXI/AIE_ARRAY_0] -force
        assign_bd_address -target_address_space /arch/target_ip_01_000/internal_target_ip_01_000/small_axil [get_bd_addr_segs memory/arch_offset_0/S_AXI/reg0 /aie/ai_engine_0/S00_AXI/AIE_ARRAY_0] -force

        save_bd_design
        
        # assign_bd_address -target_address_space /arch/target_ip_01_000/internal_target_ip_01_000/small_axil [get_bd_addr_segs memory/arch_offset_0/S_AXI/reg0] -force
        # set_property range 8T [get_bd_addr_segs {arch/target_ip_01_000/internal_target_ip_01_000/bulk_axi/AM_SEG_000}]
        # set_property range 8T [get_bd_addr_segs {arch/target_ip_01_000/internal_target_ip_01_000/small_axil/SEG_arch_offset_0_reg0}]
    }
    proc create_aie_reconfig_crossbar {} {
        # Join the bulk AXI4-Full and Small AXI4-Lite together, to expose a single interface
        # set_property -dict [list CONFIG.CONNECTIONS {M01_AXI {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4}} MC_1 {read_bw {1000} write_bw {1000} read_avg_burst {4} write_avg_burst {4}}}] [get_bd_intf_pins /memory/axi_noc_0/S08_AXI]
        # set_property -dict [list CONFIG.CONNECTIONS {MC_1 {read_bw {1000} write_bw {1000} read_avg_burst {4} write_avg_burst {4}}}] [get_bd_intf_pins /memory/axi_noc_0/S08_AXI]
        # create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0
        # move_bd_cells [get_bd_cells arch/target_ip_01_000] [get_bd_cells smartconnect_0]
        # delete_bd_objs [get_bd_intf_nets arch/target_ip_01_000/internal_target_ip_01_000_bulk_axi]
        # connect_bd_intf_net [get_bd_intf_pins arch/target_ip_01_000/smartconnect_0/S00_AXI] [get_bd_intf_pins arch/target_ip_01_000/internal_target_ip_01_000/bulk_axi]
        # connect_bd_intf_net [get_bd_intf_pins arch/target_ip_01_000/smartconnect_0/S01_AXI] [get_bd_intf_pins arch/target_ip_01_000/internal_target_ip_01_000/small_axil]
        # connect_bd_intf_net [get_bd_intf_pins arch/target_ip_01_000/bulk_axi] [get_bd_intf_pins arch/target_ip_01_000/smartconnect_0/M00_AXI]
        # connect_bd_net [get_bd_pins arch/target_ip_01_000/design_clk] [get_bd_pins arch/target_ip_01_000/smartconnect_0/aclk]
        # connect_bd_net [get_bd_pins arch/target_ip_01_000/design_peripheral_aresetn] [get_bd_pins arch/target_ip_01_000/smartconnect_0/aresetn]

        # Create some debug ILAs
        # set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {arch/target_ip_01_000/internal_target_ip_01_000_bulk_axi}]
        # set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {arch/target_ip_01_000/internal_target_ip_01_000_small_axil}]
        # apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
        #     [get_bd_intf_nets arch/target_ip_01_000/internal_target_ip_01_000_bulk_axi] {AXI_R_ADDRESS "Data and Trigger" AXI_R_DATA "Data and Trigger" AXI_W_ADDRESS "Data and Trigger" AXI_W_DATA "Data and Trigger" AXI_W_RESPONSE "Data and Trigger" CLK_SRC "/clocks_and_resets/design_clk_wiz/clk_out1" AXIS_ILA "Auto" APC_EN "0" } \
        #     [get_bd_intf_nets arch/target_ip_01_000/internal_target_ip_01_000_small_axil] {AXI_R_ADDRESS "Data and Trigger" AXI_R_DATA "Data and Trigger" AXI_W_ADDRESS "Data and Trigger" AXI_W_DATA "Data and Trigger" AXI_W_RESPONSE "Data and Trigger" CLK_SRC "/clocks_and_resets/design_clk_wiz/clk_out1" AXIS_ILA "Auto" APC_EN "0" } \
        # ]

        # set_property -dict [list CONFIG.CONNECTIONS {M01_AXI {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4}} M00_AXI {read_bw {500} write_bw {500} read_avg_burst {4} write_avg_burst {4}} MC_1 {read_bw {1000} write_bw {1000} read_avg_burst {4} write_avg_burst {4}}}] [get_bd_intf_pins /memory/axi_noc_0/S08_AXI]
    }

    proc create_ltx {} {
        write_debug_probes debug_probes.ltx -no_partial_ltxfile -verbose -force
    }
}


if {[tapasco::is_feature_enabled "aie_reconfig"]} {
    tapasco::register_plugin "platform::aie_reconfig::join_small_and_bulk_ports" "post-pe-create"
    tapasco::register_plugin "platform::aie_reconfig::setup_aie_noc_connection" "pre-wrapper"
    #tapasco::register_plugin "platform::aie_reconfig::address_map" "post-address-map"
    #tapasco::register_plugin "platform::aie_reconfig::create_aie_reconfig_crossbar" "post-platform"
    tapasco::register_plugin "platform::aie_reconfig::create_ltx" "post-bitstream"
}
