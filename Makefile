# AI Engine reflasher for the VCK5000 under Tapasco. Everything is built from here.
#
#   make codegen     sus_compiler -> build/aie_pdi_loader.sv
#   make sim         Verilator run of the PE against the fake-PLM testbench
#   make sim-xsim    same testbench in Vivado xsim
#   make package     Vivado IP packaging of both PEs -> build/AIEPdiLoader.zip, build/DataStreamerVN.zip,
#                    each imported into Tapasco right after packaging (IDs $(PE_ID), $(VN_ID))
#   make link_plugin symlink tapasco/aie_reflasher_plugin.tcl into the Tapasco vck5000 plugin dir
#   make aie         aie/libadf_a.a and aie/libadf_b.a (-DDOUBLE_OUTPUT) from aie/src with aiecompiler
#   make jobfile     build/pdi-loader.json with ADF=$(ADF) substituted (builds the archive if needed)
#   make bitstream   tapasco --jobsFile build/pdi-loader.json; copies the PDI (and debug_probes.ltx
#                    if the plugin's ILA was enabled) to build/bitstream.pdi, build/debug_probes.ltx
#   make pdi         aie/libadf_{a,b}.pdi: AIE-only partial PDIs from the libadf archives, stamped with
#                    the IDCODE of build/bitstream.pdi
#   make check-pdi   structural check of the partial PDIs
#   make host        build/reflash-aie-loader and build/vector-norm
#   make all         codegen + host (everything that needs neither Vivado nor Vitis)
#
# Every target carries its full dependency chain, so nothing relies on checked-in build
# products: pdi -> bitstream -> IP zips + job file -> AIE archive -> aie/src, codegen -> sus/.
#
# Environment: `source <tapasco workspace>/tapasco-setup.sh` provides TAPASCO_WORK_DIR and
# TAPASCO_HOME_TOOLFLOW; vivado/bootgen/aiecompiler come from the Vitis 2023.1 settings script
# (XILINX_VITIS); PLATFORM_FILE is the VCK5000 .xpfm.
# On pc2: `source vck5000_modules.sh`.

SHELL := /bin/bash
BUILD ?= build
PART  ?= xcvc1902-vsvd1760-2MP-e-S

# Tapasco runtime install (tapasco-build-libs puts it under $TAPASCO_WORK_DIR/build/install;
# tapasco-setup.sh exports Tapasco_DIR = <prefix>/share/Tapasco/cmake). The library lands in
# lib or lib64 depending on the distribution, as .a or (with --shared) .so.
ifneq ($(Tapasco_DIR),)
TAPASCO_PREFIX     ?= $(abspath $(Tapasco_DIR)/../../..)
else
TAPASCO_PREFIX     ?= $(TAPASCO_WORK_DIR)/build/install/usr/local
endif
TAPASCO_LIB        ?= $(firstword $(wildcard $(TAPASCO_PREFIX)/lib64/libtapasco.a $(TAPASCO_PREFIX)/lib/libtapasco.a \
                                             $(TAPASCO_PREFIX)/lib64/libtapasco.so $(TAPASCO_PREFIX)/lib/libtapasco.so))
TAPASCO_PLUGIN_DIR ?= $(TAPASCO_HOME_TOOLFLOW)/vivado/platform/vck5000/plugins
# Tapasco kernel IDs: AIEPdiLoader, DataStreamerVN (the Bluespec original used 8847).
# No trailing comments here: make keeps the whitespace before them in the value.
PE_ID ?= 10203
VN_ID ?= 10204

# AIE graph archive the bitstream is built with (the running design must match aie/libadf_a.pdi
# or aie/libadf_b.pdi only in its PL interface; which one is loaded at boot does not matter).
ADF ?= aie/libadf_a.a

# Where Tapasco leaves the composed design, and the local copy `make bitstream` keeps. The
# partial PDIs copy their IDCODE from that copy: the PLM rejects a PDI whose IDCODE differs
# from the silicon, and a PDI that boots on the card is the authoritative source for it.
COMPOSE_DIR := $(TAPASCO_WORK_DIR)/compose/axi4mm/vck5000/DataStreamerVN__AIEPdiLoader/001_001/312.5+AI-Engine+DMA-Streaming+aie_reflasher_plugin
BITSTREAM   := $(BUILD)/bitstream.pdi

SUS_LIB      := sus-xrt/axi_stream.sus sus-xrt/axi_lite.sus sus-xrt/axi_memory.sus sus-tapasco/sus/tapasco_ctrl_slave.sus
SUS_FILES    := $(SUS_LIB) sus/aie_pdi_loader.sus
SUS_VN_FILES := sus-tapasco/sus/tapasco_ctrl_slave.sus sus/data_streamer_vn.sus
CODEGEN      := $(BUILD)/aie_pdi_loader.sv
CODEGEN_VN   := $(BUILD)/data_streamer_vn.sv

# AIE graph compile (Vitis 2023.1)
AIECC      ?= $(XILINX_VITIS)/aietools/bin/aiecompiler
AIE_FLAGS  := -v -Xchess=main:darts.xargs=-nb -target=hw -platform=$(PLATFORM_FILE) \
              -include=$(XILINX_VITIS)/aietools/include -include=$(abspath aie/src)

CXX      ?= g++
CXXFLAGS ?= -std=gnu++20 -O2 -Wall
TAPASCO_CXXFLAGS := -isystem $(TAPASCO_PREFIX)/include/tapasco
TAPASCO_LDLIBS   := $(TAPASCO_LIB) -lpthread -ldl -lm -lrt -lutil

.PHONY: all codegen sim sim-xsim package link_plugin aie jobfile bitstream pdi check-pdi host clean

all: codegen host

# ---------------------------------------------------------------- PE (SUS -> SystemVerilog)
codegen: $(CODEGEN) $(CODEGEN_VN)

$(CODEGEN): $(SUS_FILES)
	@mkdir -p $(BUILD)
	sus_compiler --nocolor $(SUS_FILES) -o $@ --top AIEPdiLoader --gen-tb > $(BUILD)/AIEPdiLoader_tb_stub.sv

$(CODEGEN_VN): $(SUS_VN_FILES)
	@mkdir -p $(BUILD)
	sus_compiler --nocolor $(SUS_VN_FILES) -o $@ --top DataStreamerVN

# ---------------------------------------------------------------- simulation
VERILATOR := verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -j 4

sim: $(CODEGEN) $(CODEGEN_VN)
	rm -rf $(BUILD)/obj_dir $(BUILD)/obj_dir_vn
	$(VERILATOR) --top-module AIEPdiLoader_tb --Mdir $(BUILD)/obj_dir \
	    $(CODEGEN) sus/tb/fake_plm_axil.sv sus/tb/AIEPdiLoader_tb.sv > $(BUILD)/verilator.log 2>&1
	$(BUILD)/obj_dir/VAIEPdiLoader_tb | grep -v 'READ  addr=00000000ff3.0004'
	$(VERILATOR) --top-module DataStreamerVN_tb --Mdir $(BUILD)/obj_dir_vn \
	    $(CODEGEN_VN) sus/tb/DataStreamerVN_tb.sv > $(BUILD)/verilator_vn.log 2>&1
	$(BUILD)/obj_dir_vn/VDataStreamerVN_tb

sim-xsim: $(CODEGEN)
	cd sus/tb && vivado -mode batch -source sim.tcl -tclargs $(abspath $(CODEGEN)) $(abspath $(BUILD))/xsim_prj

# ---------------------------------------------------------------- Tapasco IP + bitstream
package: $(BUILD)/AIEPdiLoader.zip $(BUILD)/DataStreamerVN.zip

$(BUILD)/AIEPdiLoader.zip: $(CODEGEN) tapasco/pack_pdi_loader_kernel.tcl
	rm -rf $(BUILD)/pack_prj && mkdir -p $(BUILD)/pack_prj
	cd $(BUILD)/pack_prj && vivado -mode batch -source $(abspath tapasco/pack_pdi_loader_kernel.tcl) -tclargs $(PART) $(abspath $(CODEGEN))
	rm -f $@
	cd $(BUILD)/pack_prj/AIEPdiLoader_ip && zip -qr $(abspath $@) .
	tapasco import $(BUILD)/AIEPdiLoader.zip as $(PE_ID) -p vck5000

$(BUILD)/DataStreamerVN.zip: $(CODEGEN_VN) tapasco/pack_data_streamer_vn.tcl
	rm -rf $(BUILD)/pack_prj_vn && mkdir -p $(BUILD)/pack_prj_vn
	cd $(BUILD)/pack_prj_vn && vivado -mode batch -source $(abspath tapasco/pack_data_streamer_vn.tcl) -tclargs $(PART) $(abspath $(CODEGEN_VN))
	rm -f $@
	cd $(BUILD)/pack_prj_vn/DataStreamerVN_ip && zip -qr $(abspath $@) .
	tapasco import $(BUILD)/DataStreamerVN.zip as $(VN_ID) -p vck5000

link_plugin: tapasco/aie_reflasher_plugin.tcl
	@test -d "$(TAPASCO_PLUGIN_DIR)" || { echo "TAPASCO_PLUGIN_DIR=$(TAPASCO_PLUGIN_DIR) does not exist (source tapasco-setup.sh?)"; exit 1; }
	ln -sfn $(abspath $<) $(TAPASCO_PLUGIN_DIR)/$(notdir $<)
	@echo "linked $(TAPASCO_PLUGIN_DIR)/$(notdir $<) -> $(abspath $<)"

jobfile: $(BUILD)/pdi-loader.json

$(BUILD)/pdi-loader.json: tapasco/pdi-loader.json $(ADF)
	@mkdir -p $(BUILD)
	sed 's,@ADF@,$(abspath $(ADF)),' $< > $@
	@echo "wrote $@ (adf = $(abspath $(ADF)))"

bitstream: $(BITSTREAM)

$(BITSTREAM): $(BUILD)/pdi-loader.json $(BUILD)/AIEPdiLoader.zip $(BUILD)/DataStreamerVN.zip
	tapasco --jobsFile $<
	cp "$$(ls -t $(COMPOSE_DIR)/*.pdi | head -1)" $(BITSTREAM)
	-cp $(COMPOSE_DIR)/debug_probes.ltx $(BUILD)/ 2>/dev/null
	@echo "bitstream: $(BITSTREAM)$$(test -f $(BUILD)/debug_probes.ltx && echo ', probes: $(BUILD)/debug_probes.ltx')"

# ---------------------------------------------------------------- AIE graphs
# One source tree; graph B is the same code built with -DDOUBLE_OUTPUT (sum_sqrt.cpp).
# Real file targets: anything that needs an archive (jobfile, pdi) builds it when it is
# missing or older than the sources.
AIE_SRC := $(wildcard aie/src/*)

aie: aie/libadf_a.a aie/libadf_b.a

# $(1) = variant letter, $(2) = extra aiecompiler flags
define AIE_BUILD
	@test -n "$(XILINX_VITIS)" -a -n "$(PLATFORM_FILE)" || { echo "set XILINX_VITIS and PLATFORM_FILE (VCK5000 .xpfm) for aiecompiler"; exit 1; }
	rm -rf $(BUILD)/aie_$(1) && mkdir -p $(BUILD)/aie_$(1)
	cd $(BUILD)/aie_$(1) && $(AIECC) $(AIE_FLAGS) $(2) -workdir=work $(abspath aie/src/graph.cpp)
	cp $(BUILD)/aie_$(1)/libadf.a $@
endef

aie/libadf_a.a: $(AIE_SRC)
	$(call AIE_BUILD,a,)
aie/libadf_b.a: $(AIE_SRC)
	$(call AIE_BUILD,b,-Xpreproc=-DDOUBLE_OUTPUT)

# ---------------------------------------------------------------- partial PDIs
pdi: aie/libadf_a.pdi aie/libadf_b.pdi

# A partial PDI depends on its archive and on the full bitstream (for the IDCODE): a missing
# archive runs aiecompiler, a missing build/bitstream.pdi runs the Tapasco build.
aie/%.pdi: aie/%.a $(BITSTREAM) tools/make_aie_pdi.sh
	tools/make_aie_pdi.sh $< $@ --like $(abspath $(BITSTREAM))

check-pdi: aie/libadf_a.pdi aie/libadf_b.pdi
	python3 tools/pdi_info.py aie/libadf_a.pdi
	python3 tools/pdi_info.py aie/libadf_b.pdi

# ---------------------------------------------------------------- host tools
host: $(BUILD)/reflash-aie-loader $(BUILD)/vector-norm

define HOST_BUILD
	@mkdir -p $(BUILD)
	@test -n "$(TAPASCO_LIB)" || { echo "libtapasco not found in $(TAPASCO_PREFIX)/lib{,64} (source tapasco-setup.sh and run tapasco-build-libs, or pass TAPASCO_LIB=/path/to/libtapasco.a)"; exit 1; }
	$(CXX) $(CXXFLAGS) $(TAPASCO_CXXFLAGS) $< -o $@ $(TAPASCO_LDLIBS)
endef

$(BUILD)/reflash-aie-loader: host/reflash_aie_loader.cpp
	$(HOST_BUILD)
$(BUILD)/vector-norm: host/vector_norm.cpp
	$(HOST_BUILD)

clean:
	rm -rf $(BUILD)
	