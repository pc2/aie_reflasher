# Build the AIEPdiLoader PE.
#   make codegen                      -> build/aie_pdi_loader.sv, build/AIEPdiLoader_tb.sv
#   make package PART=<part>          -> build/AIEPdiLoader.zip (needs vivado on PATH)
#   make sim                          -> xsim of the fake-PLM testbench (needs vivado)
ROOT   := $(abspath ../..)
BUILD  := build
PART   ?= xcvc1902-vsvd1760-2MP-e-S

SUS_FILES := $(ROOT)/sus-xrt/axi_stream.sus $(ROOT)/sus-xrt/axi_lite.sus $(ROOT)/sus-xrt/axi_memory.sus \
             $(ROOT)/sus-tapasco/sus/tapasco_ctrl_slave.sus aie_pdi_loader.sus

.PHONY: codegen package sim sim-verilator clean

codegen: $(BUILD)/aie_pdi_loader.sv

$(BUILD)/aie_pdi_loader.sv: $(SUS_FILES)
	mkdir -p $(BUILD)
	sus_compiler --nocolor $(SUS_FILES) -o $@ --top AIEPdiLoader --gen-tb > $(BUILD)/AIEPdiLoader_tb_stub.sv

package: $(BUILD)/AIEPdiLoader.zip

$(BUILD)/AIEPdiLoader.zip: $(BUILD)/aie_pdi_loader.sv pack_pdi_loader_kernel.tcl
	rm -rf $(BUILD)/pack_prj && mkdir -p $(BUILD)/pack_prj
	cd $(BUILD)/pack_prj && vivado -mode batch -source ../../pack_pdi_loader_kernel.tcl -tclargs $(PART) ../aie_pdi_loader.sv
	cd $(BUILD)/pack_prj/AIEPdiLoader_ip && zip -r ../../AIEPdiLoader.zip .

sim: $(BUILD)/aie_pdi_loader.sv
	cd tb && vivado -mode batch -source sim.tcl -tclargs ../$(BUILD)/aie_pdi_loader.sv

sim-verilator: $(BUILD)/aie_pdi_loader.sv
	rm -rf obj_dir && verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module AIEPdiLoader_tb -j 4 \
	    $(BUILD)/aie_pdi_loader.sv tb/fake_plm_axil.sv tb/AIEPdiLoader_tb.sv > $(BUILD)/verilator.log 2>&1
	obj_dir/VAIEPdiLoader_tb | grep -v 'READ  addr=00000000ff380004'

clean:
	rm -rf obj_dir
	rm -rf $(BUILD)

tapasco_import: $(BUILD)/AIEPdiLoader.zip
	tapasco import $(BUILD)/AIEPdiLoader.zip as 10203 -p vck5000
