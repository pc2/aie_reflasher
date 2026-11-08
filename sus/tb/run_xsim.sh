#!/bin/bash
# Headless xsim run of AIEPdiLoader_tb (Makefile target sim-xsim): the PE, Tapasco's PDILoader core and the
# fake PLM. Prints ALL OK at the end on success.
#   sus/tb/run_xsim.sh <aie_pdi_loader.sv> <PDILoader.sv> <work dir>
set -e
PE_SV="$(realpath "$1")"
LOADER_SV="$(realpath "$2")"
WORK="$3"
TB_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$WORK" && cd "$WORK"
xvlog -sv "$PE_SV" "$LOADER_SV" "$TB_DIR/fake_plm_axil.sv" "$TB_DIR/AIEPdiLoader_tb.sv" > xvlog.log
xelab -timescale 1ns/1ps AIEPdiLoader_tb -s tb_snapshot > xelab.log
xsim tb_snapshot -runall | grep -v 'READ  addr=00000000ff3.0004' | tee xsim.log
grep -q 'ALL OK' xsim.log
