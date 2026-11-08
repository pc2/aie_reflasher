# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Runtime reconfiguration of only the AI Engine array on a VCK5000 under Tapasco. A PL processing
element (`AIEPdiLoader`, written in SUS) asks the Versal PLM firmware over IPI to load an
AIE-only partial PDI that the host has DMA'd into card DDR. The README is accurate and
detailed; read it first for the full build pipeline, the IPI handshake and the error codes.
`docs/aie_pdi_loader_design.md` has the step table and bring-up log, `docs/background.md`
explains why a PL-only reconfigurator did not work (NPI registers only the PMC may touch).

## Environment

Everything needs Vitis/Vivado 2023.1, a Tapasco vck5000 workspace (`tapasco-setup.sh`
sourced: provides `TAPASCO_WORK_DIR`, `TAPASCO_HOME_TOOLFLOW`, `Tapasco_DIR`), `sus_compiler`
0.4.0 and `verilator` 5.x. On pc2: `source vck5000_modules.sh`. Submodules `sus-xrt` and
`sus-tapasco` must be checked out (`git submodule update --init`); the Makefile and
`.vscode/settings.json` (sus-lsp) list the same `.sus` file set.

## Commands

All build steps are in the `Makefile`; everything generated goes to `build/` (gitignored).

| Command | Does | Cost |
|---|---|---|
| `make codegen` | `sus_compiler` → `build/aie_pdi_loader.sv`, `build/data_streamer_vn.sv` | seconds |
| `make sim` | Verilator: loader testbench against the fake PLM (8 cases) + streamer testbench against a behavioural AIE (5 cases). Every case must print `OK` | ~1 min |
| `make sim-xsim` | loader testbench in Vivado xsim (`sus/tb/sim.tcl`) | minutes |
| `make package` | Vivado IP packaging of both PEs, then `tapasco import` as IDs 10203 / 10204 | minutes |
| `make link_plugin` | symlink `tapasco/aie_reflasher_plugin.tcl` into the Tapasco vck5000 plugin dir | instant |
| `make aie` | `aiecompiler` → `build/libadf_a.a`, `build/libadf_b.a` (`-DDOUBLE_OUTPUT`) | tens of minutes |
| `make jobfile` / `make bitstream` | Tapasco compose from `build/pdi-loader.json`; copies result to `build/reconfigurable_bitstream.pdi` | **hours** |
| `make pdi` / `make check-pdi` | partial PDIs via `tools/make_aie_pdi.sh` (bootgen); needs the bitstream for its IDCODE | seconds |
| `make host` | `build/reflash-aie-loader`, `build/vector-norm` (g++ C++20 against libtapasco) | seconds |
| `make clean` | removes `build/` **including the bitstream copy** — never run casually | |

There is no single-test selector: the Verilator testbenches run all their scenarios in one
binary. To run one testbench only, run the corresponding `$(VERILATOR)` line from the
`sim` target by hand (`build/obj_dir/VAIEPdiLoader_tb` or `build/obj_dir_vn/VDataStreamerVN_tb`).

The bitstream has order-only prerequisites: changing the job file or IP zips does not
retrigger the multi-hour build; `make -B bitstream` does. Do not start a bitstream build or
`make package` (which does a `tapasco import` into the shared workspace) without being asked.

Runtime (needs the card with the bitstream loaded):
```
build/vector-norm                           # expects graph A
build/reflash-aie-loader build/libadf_b.pdi [--ipi N] [--ping]
build/vector-norm --expect-scale 2          # graph B doubles every output
```

## Architecture

Pipeline: `sus/*.sus` → (sus_compiler) SystemVerilog → (Vivado ipx, `tapasco/pack_*.tcl`)
IP zip → (`tapasco import`) → (`tapasco --jobsFile`, with the plugin) full PDI. Separately
`aie/` → (aiecompiler) `libadf_{a,b}.a` → (`tools/make_aie_pdi.sh`) partial PDIs. Host tools
drive the PEs through libtapasco.

The pieces that must stay consistent with each other:

- **Register map** of `AIEPdiLoader` is defined three times: in `sus/aie_pdi_loader.sus`
  (`tapasco_ctrl_slave` args), in `tapasco/pack_pdi_loader_kernel.tcl` (ipx registers:
  `PDI_ADDRESS` 0x20, `IPI_CONFIG` 0x30, return value at 0x10) and in
  `host/reflash_aie_loader.cpp` (argument order). Same for `DataStreamerVN`
  (`SAMPLES` 0x20) across `sus/data_streamer_vn.sus`, `tapasco/pack_data_streamer_vn.tcl`
  and `host/vector_norm.cpp`. Change all of them together.
- **Return word** encoding (`[31:0]` PLMI status or `0xFFFFFF00|local_error`, `[63:32]`
  XilLoader status / cycle count) is produced in the `.sus`, checked in
  `sus/tb/AIEPdiLoader_tb.sv` and decoded in the host tool and README error table.
- **IPI addresses** (`0xFF33xxxx` TRIG/OBS, `0xFF3F0xxx` message RAM, response at request
  slot `+0x20`) are computed per request from the channel in `pmc_pdi_loader`; the fake
  PLM in `sus/tb/fake_plm_axil.sv` models the same layout, and the plugin verifies that
  `psv_ipi_0..5` and `psv_ipi_buffer` end up in the PE's address space. The LPD port is
  reached via a direct `S_AXI_LPD` connection, not the NoC — the plugin's comments explain why.
- **PE names and the compose dir**: `COMPOSE_DIR` in the Makefile encodes the kernel names,
  count, frequency and feature list from `tapasco/pdi-loader.json`. Renaming a PE, changing
  the frequency or adding a feature changes that path.
- **Shim tile pinning** in `aie/graph.h` (PLIOs on tiles 12/13/14) is what makes graphs
  interchangeable at runtime; any new graph must keep it.
- **Tapasco kernel IDs** 10203 (`AIEPdiLoader`) and 10204 (`DataStreamerVN`) are set in the
  Makefile (`PE_ID`, `VN_ID`); `vector-norm` tries the SUS VLNV first, then the original
  Bluespec one (8847).

`pmc_pdi_loader` in `sus/aie_pdi_loader.sus` is the reusable core (AXI4-Lite master +
10-step sequencer); `AIEPdiLoader` is the Tapasco wrapper. `sus-xrt` provides the AXI
modules, `sus-tapasco` the `tapasco_ctrl_slave`.

## Conventions

- Dated notes (e.g. `(2026-10-20: ...)`) in comments and docs record bring-up findings; keep
  them when editing nearby and add one when a hardware observation changes a design decision.
- The README and `docs/` are kept in sync with behaviour changes (error codes, addresses,
  register map). Update them in the same change.
- Makefile variables with values used in paths carry no trailing comments (make keeps the
  whitespace).
