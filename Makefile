# AI Engine reflasher for the VCK5000 under Tapasco. Everything is built from here.
#
#   make codegen     sus_compiler -> build/aie_pdi_loader.sv
#   make sim         Verilator run of the PE against the fake-PLM testbench
#   make sim-xsim    same testbench in Vivado xsim
#   make package     Vivado IP packaging -> build/AIEPdiLoader.zip
#   make import      tapasco import of that zip (ID $(PE_ID))
#   make plugin      copy tapasco/aie_reflasher_ipi.tcl into the Tapasco vck5000 plugin dir
#   make jobfile     build/pdi-loader.json with ADF=$(ADF) substituted
#   make bitstream   tapasco --jobsFile build/pdi-loader.json
#   make pdi         aie/libadf_{a,b}.pdi: AIE-only partial PDIs from the libadf archives
#   make check-pdi   structural check of the partial PDIs
#   make host        bin/reflash-aie-loader and bin/vector-norm (prebuilt copies are checked in)
#   make all         codegen + host (everything that needs neither Vivado nor bootgen)
#
# Environment: `source <tapasco workspace>/tapasco-setup.sh` provides TAPASCO_WORK_DIR and
# TAPASCO_HOME_TOOLFLOW; vivado/bootgen come from the Vitis/Vivado 2023.1 settings script.
# On pc2: `source vck5000_modules.sh`.

SHELL := /bin/bash
BUILD ?= build
BIN   ?= bin
PART  ?= xcvc1902-vsvd1760-2MP-e-S

# Tapasco runtime install (tapasco-build-libs) and plugin directory
TAPASCO_PREFIX     ?= $(TAPASCO_WORK_DIR)/build/install/usr/local
TAPASCO_PLUGIN_DIR ?= $(TAPASCO_HOME_TOOLFLOW)/vivado/platform/vck5000/plugins
PE_ID ?= 10203

# AIE graph archive the bitstream is built with (the running design must match aie/libadf_a.pdi
# or aie/libadf_b.pdi only in its PL interface; which one is loaded at boot does not matter).
ADF ?= $(abspath aie/libadf_a.a)

# IDCODE stamped into the partial PDIs. The PLM rejects a PDI whose IDCODE differs from the
# silicon. 0x14ca8093 / 1 is the production VCK5000; set REF_PDI=<pdi that boots on your card>
# to copy the values from there instead.
ID_CODE     ?= 0x14ca8093
EXT_ID_CODE ?= 0x1
REF_PDI     ?=
ifneq ($(REF_PDI),)
PDI_ID_ARGS := --like $(abspath $(REF_PDI))
else
PDI_ID_ARGS := --id-code $(ID_CODE) --ext-id-code $(EXT_ID_CODE)
endif

SUS_FILES := sus-xrt/axi_stream.sus sus-xrt/axi_lite.sus sus-xrt/axi_memory.sus \
             sus-tapasco/sus/tapasco_ctrl_slave.sus sus/aie_pdi_loader.sus
CODEGEN   := $(BUILD)/aie_pdi_loader.sv

CXX      ?= g++
CXXFLAGS ?= -std=gnu++20 -O2 -Wall
TAPASCO_CXXFLAGS := -isystem $(TAPASCO_PREFIX)/include/tapasco
TAPASCO_LDLIBS   := $(TAPASCO_PREFIX)/lib/libtapasco.a -lpthread -ldl -lm -lrt -lutil

.PHONY: all codegen sim sim-xsim package import plugin jobfile bitstream pdi check-pdi host clean

all: codegen host

# ---------------------------------------------------------------- PE (SUS -> SystemVerilog)
codegen: $(CODEGEN)

$(CODEGEN): $(SUS_FILES)
	@mkdir -p $(BUILD)
	sus_compiler --nocolor $(SUS_FILES) -o $@ --top AIEPdiLoader --gen-tb > $(BUILD)/AIEPdiLoader_tb_stub.sv

# ---------------------------------------------------------------- simulation
sim: $(CODEGEN)
	rm -rf $(BUILD)/obj_dir
	verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module AIEPdiLoader_tb -j 4 \
	    --Mdir $(BUILD)/obj_dir $(CODEGEN) sus/tb/fake_plm_axil.sv sus/tb/AIEPdiLoader_tb.sv > $(BUILD)/verilator.log 2>&1
	$(BUILD)/obj_dir/VAIEPdiLoader_tb | grep -v 'READ  addr=00000000ff3.0004'

sim-xsim: $(CODEGEN)
	cd sus/tb && vivado -mode batch -source sim.tcl -tclargs $(abspath $(CODEGEN)) $(abspath $(BUILD))/xsim_prj

# ---------------------------------------------------------------- Tapasco IP + bitstream
package: $(BUILD)/AIEPdiLoader.zip

$(BUILD)/AIEPdiLoader.zip: $(CODEGEN) tapasco/pack_pdi_loader_kernel.tcl
	rm -rf $(BUILD)/pack_prj && mkdir -p $(BUILD)/pack_prj
	cd $(BUILD)/pack_prj && vivado -mode batch -source $(abspath tapasco/pack_pdi_loader_kernel.tcl) -tclargs $(PART) $(abspath $(CODEGEN))
	rm -f $@
	cd $(BUILD)/pack_prj/AIEPdiLoader_ip && zip -qr $(abspath $@) .

import: $(BUILD)/AIEPdiLoader.zip
	tapasco import $< as $(PE_ID) -p vck5000

plugin: tapasco/aie_reflasher_ipi.tcl
	@test -d "$(TAPASCO_PLUGIN_DIR)" || { echo "TAPASCO_PLUGIN_DIR=$(TAPASCO_PLUGIN_DIR) does not exist (source tapasco-setup.sh?)"; exit 1; }
	cp $< $(TAPASCO_PLUGIN_DIR)/
	@echo "installed $< -> $(TAPASCO_PLUGIN_DIR)/"

jobfile: $(BUILD)/pdi-loader.json

$(BUILD)/pdi-loader.json: tapasco/pdi-loader.json
	@mkdir -p $(BUILD)
	@test -f "$(ADF)" || { echo "ADF=$(ADF) not found"; exit 1; }
	sed 's,@ADF@,$(ADF),' $< > $@
	@echo "wrote $@ (adf = $(ADF))"

bitstream: $(BUILD)/pdi-loader.json
	tapasco --jobsFile $<

# ---------------------------------------------------------------- partial PDIs
pdi: aie/libadf_a.pdi aie/libadf_b.pdi

aie/%.pdi: aie/%.a
	tools/make_aie_pdi.sh $< $@ $(PDI_ID_ARGS)

check-pdi: aie/libadf_a.pdi aie/libadf_b.pdi
	python3 tools/pdi_info.py aie/libadf_a.pdi
	python3 tools/pdi_info.py aie/libadf_b.pdi

# ---------------------------------------------------------------- host tools
host: $(BIN)/reflash-aie-loader $(BIN)/vector-norm

define HOST_BUILD
	@mkdir -p $(BIN)
	@test -f "$(TAPASCO_PREFIX)/lib/libtapasco.a" || { echo "libtapasco.a not found under TAPASCO_PREFIX=$(TAPASCO_PREFIX) (source tapasco-setup.sh and run tapasco-build-libs)"; exit 1; }
	$(CXX) $(CXXFLAGS) $(TAPASCO_CXXFLAGS) $< -o $@ $(TAPASCO_LDLIBS)
endef

$(BIN)/reflash-aie-loader: host/reflash_aie_loader.cpp
	$(HOST_BUILD)
$(BIN)/vector-norm: host/vector_norm.cpp
	$(HOST_BUILD)

clean:
	rm -rf $(BUILD)
