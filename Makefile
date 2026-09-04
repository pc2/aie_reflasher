# You may override $(BIN_DIR) to a directory of your liking. For instance for parallel builds, you can `make U280/overlay_hw.xclbin BIN_DIR=U280_test` 

SHELL := /bin/bash
TMPDIR := /tmp/vivado_$(USER)

$(TMPDIR):
	mkdir -p $(TMPDIR)

# Configurations that change based on the platform
VCK5000/%: BIN_DIR ?= VCK5000
VCK5000/%: PART := xcvc1902-vsvd1760-2MP-e-S
VCK5000/%: PLATFORM := xilinx_vck5000_gen4x8_qdma_2_202220_1
VCK5000/%: SUS_FLOAT_LIB_PATH := sus-float/Versal

# either hw or x86
AIE_TARGET = hw
ifeq ($(AIE_TARGET), x86)
MAKE_AIE_TARGET = "$(AIE_TARGET)sim"
else
MAKE_AIE_TARGET = $(AIE_TARGET)
endif
SIMULATION_TARGET := $(AIE_TARGET)
$(info "MAKE_AIE_TARGET = $(MAKE_AIE_TARGET)")

#either vrr, hrr, or eri
ERI_PROGRAM=vrr
ERI_TARGET = ddpp
ERI_TARGET_AB = $(shell TMP=$(ERI_TARGET); echo "$${TMP:0:2}")

NUM_RINGS = 1
NUM_ENGINES_PER_RING = 1

VECTORIZATION_FACTOR=0
ENGINE_SIZE=0
ENABLE_PROFILING=0

VPP_ARGS := -g
CXX_ARGS := -O3 -march=native --std=c++20

BUILD_DIR_PREFIX=.
BUILD_DIR := build/$(shell date "+%Y-%m-%d")
BUILD_SUBDIR := $(shell date "+%H-%M-%S")
BASE_DIR := $(shell pwd)
LIBINT_BUILDS_DIR := /scratch/pc2-mitarbeiter/jmenzel/FCCM25/libint_builds

REFLASH_FILES := 
REFLASH_FILES += sus-xrt/axi_stream.sus
REFLASH_FILES += sus-xrt/axi_lite.sus
REFLASH_FILES += sus-xrt/axi_memory.sus
REFLASH_FILES += sus-tapasco/sus/tapasco_ctrl_slave.sus
REFLASH_FILES += ai_engine_reflash.sus

VCK5000/reflasher_codegen.sv: $(REFLASH_FILES)
	mkdir -p $(BIN_DIR)
	sus_compiler $(REFLASH_FILES) -o VCK5000/reflasher_codegen.sv --top AIEngineReflasher --gen-tb

VCK5000/reflasher.zip: pack_reflash_kernel.tcl VCK5000/reflasher_codegen.sv
	rm -rf $(BIN_DIR)/pack_prj_reflash
	mkdir $(BIN_DIR)/pack_prj_reflash
	cd $(BIN_DIR)/pack_prj_reflash;\
	vivado -mode batch -source ../../pack_reflash_kernel.tcl -tclargs $(PART)
	rm -f $(BIN_DIR)/reflasher.zip
	cd $(BIN_DIR)/pack_prj_reflash && zip -r ../reflasher.zip AIEngineReflasher_ip
	tapasco import $(BIN_DIR)/reflasher.zip as 8848 -p vck5000


main.x: main.cpp
	g++ -g -O3 -std=c++17 -I$(XILINX_XRT)/include -L$(XILINX_XRT)/lib -lxrt_coreutil -pthread main.cpp -o main.x

.PHONY: _emu
_emu: main.x | $(TMPDIR)
# It appears that the emulation creates .runs in the directory that holds main.x, so we copy it over to /tmp such that the .runs can be safely dropped there. 
# While the temporary directory doesn't seem to improve performance, it does appear that it's less "sticky" than the $PC2HOME filesystem. IE, it's less likely to get stuck undeletable due to xsim and xsimk not dieing
	cp main.x $(TMPDIR)
	cp extra_waves.tcl $(BIN_DIR)/
	cp $(XRT_INI) $(BIN_DIR)/xrt.ini
	cd $(BIN_DIR) &&\
	emconfigutil --platform $(PLATFORM) &&\
	XCL_EMULATION_MODE=hw_emu $(TMPDIR)/main.x u

_run: main.x
	cd $(BIN_DIR) && ../main.x $(ARGS)

.PHONY: VCK5000/emulate VCK5000/emulate_batch VCK5000/run
VCK5000/emulate: XRT_INI := xrt_gui.ini
VCK5000/emulate: _emu
VCK5000/emulate_batch: XRT_INI := xrt_batch.ini
VCK5000/emulate_batch: _emu
VCK5000/run: ARGS := e
VCK5000/run: _run

.PHONY: clean cleantmp
clean: cleantmp
	rm -rf VCK5000
	rm -f reflasher_codegen.sv
	
testReflasher: VCK5000/reflasher_codegen.sv
	cd tests/AIEngineReflasher && vivado -mode batch -source sim.tcl

# ---------------------------- AIE --------------------------------

.PHONY: $(ERI_PROGRAM)_aie
$(ERI_PROGRAM)_aie: set_eri_vars
	mkdir -p $(BUILD_DIR_PREFIX)/$(BUILD_DIR)/$(BUILD_SUBDIR)
	cp -a ./src/aie $(BUILD_DIR_PREFIX)/$(BUILD_DIR)/$(BUILD_SUBDIR)
	cp "./data/vectorization/$(ERI_TARGET_AB)/quad_vectorized.h" $(BUILD_DIR_PREFIX)/$(BUILD_DIR)/$(BUILD_SUBDIR)/aie/
	cp "./data/vectorization/$(ERI_TARGET_AB)/quad_v1_idx_buffers.h" $(BUILD_DIR_PREFIX)/$(BUILD_DIR)/$(BUILD_SUBDIR)/aie/
	make -C $(BUILD_DIR_PREFIX)/$(BUILD_DIR)/$(BUILD_SUBDIR)/aie compile_$(ERI_PROGRAM) ERI_PROGRAM=$(ERI_PROGRAM) AIE_TARGET=$(MAKE_AIE_TARGET)

.PHONY: $(ERI_PROGRAM)_simulate_aie
$(ERI_PROGRAM)_simulate_aie:
	make -C $(BUILD_DIR_PREFIX)/$(BUILD_DIR)/$(BUILD_SUBDIR)/aie simulate_$(SIMULATION_TARGET) BASE_DIR=$(BASE_DIR) ERI_PROGRAM=$(ERI_PROGRAM)

.PHONY: set_eri_vars
set_eri_vars:
	mkdir -p $(BUILD_DIR_PREFIX)/$(BUILD_DIR)/$(BUILD_SUBDIR)
	cp -a ./src/common $(BUILD_DIR_PREFIX)/$(BUILD_DIR)/$(BUILD_SUBDIR)
	cp $(BUILD_DIR_PREFIX)/$(BUILD_DIR)/$(BUILD_SUBDIR)/common/aie_config.h.tmpl $(BUILD_DIR_PREFIX)/$(BUILD_DIR)/$(BUILD_SUBDIR)/common/aie_config.h
	sed -i 's/__ERI_PROGRAM__/eri_program::$(ERI_PROGRAM)/g' $(BUILD_DIR_PREFIX)/$(BUILD_DIR)/$(BUILD_SUBDIR)/common/aie_config.h
	sed -i 's/__TARGET__/hardware_target::$(TARGET)/g' $(BUILD_DIR_PREFIX)/$(BUILD_DIR)/$(BUILD_SUBDIR)/common/aie_config.h
	sed -i 's/__ENABLE_PROFILING__/$(ENABLE_PROFILING)/g' $(BUILD_DIR_PREFIX)/$(BUILD_DIR)/$(BUILD_SUBDIR)/common/aie_config.h
	python scripts/aie-utils/determine_engine_size.py --quartet_type=$(ERI_TARGET) --vectorization=$(VECTORIZATION_FACTOR) --engine_size=$(ENGINE_SIZE) \
												      --num_rings=$(NUM_RINGS) --num_engines_per_ring=$(NUM_ENGINES_PER_RING) \
	                                                  --config_template_path=$(BUILD_DIR_PREFIX)/$(BUILD_DIR)/$(BUILD_SUBDIR)/common/aie_config.h

# ----------------------- EVALUATION ----------------------------

bin/benchmark_host.x: src/host/benchmark_host.cpp src/common/eri_input.* libcint_rtwt/build/libcintroots.so
	g++ $(CXX_ARGS) -I"src/common/" -I"src/host/" -I"libcint_rtwt/include/" -I$(XILINX_XRT)/include -I$(XILINX_HLS)/include \
	    -o bin/benchmark_host.x src/host/benchmark_host.cpp src/common/eri_input.cpp \
		-L$(XILINX_XRT)/lib -L"libcint_rtwt/build" -Wl,-rpath="libcint_rtwt/build" -lxrt_coreutil -lcintroots -lquadmath

bin/verification_host.x: src/host/verification_host.cpp src/common/eri_input.* libcint_rtwt/build/libcintroots.so
	g++ $(CXX_ARGS) -I"src/common/" -I"src/host/" -I"libcint_rtwt/include/" -I$(XILINX_XRT)/include -I$(XILINX_HLS)/include \
	    -o bin/verification_host.x src/host/verification_host.cpp src/common/eri_input.cpp \
		-L$(XILINX_XRT)/lib -L"libcint_rtwt/build" -Wl,-rpath="libcint_rtwt/build" -lxrt_coreutil -lcintroots -lquadmath

bin/generate_eri_engine_input.x: src/host/generate_eri_engine_input.cpp src/common/eri_input.* libcint_rtwt/build/libcintroots.so
	g++ $(CXX_ARGS) -I"src/common/" -I"src/host/" -I"libcint_rtwt/include/" \
	    -o bin/generate_eri_engine_input.x src/host/generate_eri_engine_input.cpp src/common/eri_input.cpp \
		-L"libcint_rtwt/build" -Wl,-rpath="libcint_rtwt/build" -lcintroots -lquadmath

bin/generate_ref_values.x: src/host/generate_ref_values.cpp src/common/eri_input.* src/common/rys_quadrature.* libcint_rtwt/build/libcintroots.so
	g++ $(CXX_ARGS) -I"src/common/" -I"src/host/" -I"libcint_rtwt/include/" \
	    -o bin/generate_ref_values.x src/host/generate_ref_values.cpp src/common/eri_input.cpp src/common/rys_quadrature.cpp \
		-L"libcint_rtwt/build" -Wl,-rpath="libcint_rtwt/build" -lcintroots -lquadmath

bin/generate_libint_ref_values.x: src/host/generate_libint_ref_values.cpp src/common/eri_input.* libcint_rtwt/build/libcintroots.so
	g++ $(CXX_ARGS) -I"src/common/" -I"src/host/" -I"libcint_rtwt/include/" -I"$(LIBINT_BUILDS_DIR)/default_complete/libint-2.9.0/build/include" \
	    -o bin/generate_libint_ref_values.x src/host/generate_libint_ref_values.cpp src/common/eri_input.cpp \
		-L"$(LIBINT_BUILDS_DIR)/default_complete/libint-2.9.0/build/lib" -L"libcint_rtwt/build" -Wl,-rpath="libcint_rtwt/build" -lint2 -lcintroots -lquadmath

# --------------------------------- RYS ROOTS ----------------------------------
libcint_rtwt/build/libcintroots.so: libcint_rtwt/src/* libcint_rtwt/include/* libcint_rtwt/tests/*
	cmake -B libcint_rtwt/build -S libcint_rtwt
	cmake --build libcint_rtwt/build

