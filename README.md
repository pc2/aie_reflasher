# AI Engine reflasher for the VCK5000 under Tapasco

Reconfigure **only the AI Engine array** of a running Tapasco VCK5000 design, in a few tens of
milliseconds end to end, without touching the PL, the NoC, the DDR contents or the PCIe link.

Tapasco's `PDI-Loader` platform feature (Versal, in `toolflow/vivado/platform/versal/plugins/pdi_loader.tcl`
of Tapasco) lets a PE load a PDI at runtime: the PE exposes a master of the `PDILoad` interface (a start
handshake with the PDI's DDR address, a finish handshake with the verdict), and for every such interface
the feature instantiates a `PDILoader` core (`toolflow/vivado/common/ip/PDILoader`, written in
[SUS](https://github.com/pc2/sus-compiler)) that hands the PDI to the Platform Loader and Manager
(PLM, the firmware running on the Versal PMC) over an Inter-Processor Interrupt (IPI). The PLM
then does exactly what it did for the AIE image at boot: parse the PDI, run the CDOs, load the
tile ELFs, release the cores. The feature and the core were developed here; this repository is now
their test case and example: the `AIEPdiLoader` PE just forwards a Tapasco job to the loader, so the
host side is one job: DMA the PDI, launch the PE, read back the PLM's verdict.

```
host                         card DDR                        PL                                PS / PMC
reflash-aie-loader --DMA-->  aie_partial.pdi
                   --launch----------------------------->  AIEPdiLoader PE
                                                             | PDILoad start (PDI address)
                                                             v
                                                           PDILoader (PDI-Loader feature)
                                                             | 4-word IPI request + TRIG
                                                             |  (S_AXI_LPD, 0xFF33xxxx / 0xFF3F0xxx)
                                                             v
                                                           PLM on the PMC: XLoader_LoadSubsystemPdi
                                                             |  PMC DMA reads the PDI from DDR,
                                                             |  executes the AIE CDOs (incl. NPI)
                                                             v
                                                           AIE array reconfigured, OBS cleared,
                                                             status in the IPI response buffer
                                                           PDILoader --PDILoad finish (error, status)--> PE
                   <--return value (PLMI status, cycles)--  PE
```

This repository contains everything needed to reproduce the setup: the `AIEPdiLoader` PE, the
`DataStreamerVN` example PE that feeds the AI Engine (a SUS port of the Bluespec PE from
esa-tu-darmstadt/tapasco-examples, so no Bluespec compiler is needed), simulation testbenches
for both (the loader one simulates the PE together with Tapasco's `PDILoader` core against a model
of the IPI block and the PLM), the host tools, the partial-PDI builder and the Vector-Norm AIE graph. The graph is compiled twice (`build/libadf_a.a`, `build/libadf_b.a`); the
variants differ only in a `* 2.0` on the output, so a successful reflash is visible from the
host.

## Repository layout

| Path | Contents |
|---|---|
| `Makefile` | every build step (see below); no CMake. `make clean` removes all generated files, the bitstream copy included |
| `sus/aie_pdi_loader.sus` | the `AIEPdiLoader` PE: a Tapasco control slave in front of a `PDILoad` master interface |
| `sus/data_streamer_vn.sus` | the `DataStreamerVN` PE: DMA stream in, x/y streams to the AIE, z stream back, DMA stream out |
| `sus/tb/` | SystemVerilog testbenches (Verilator or xsim): fake IPI block + PLM for the PE + loader core, behavioural AIE for the streamer; `run_xsim.sh` runs the loader one headless in xsim |
| `tapasco/pack_pdi_loader_kernel.tcl`, `tapasco/pack_data_streamer_vn.tcl` | Vivado IP packaging of the two PEs (register maps; the loader PE's `M_PDI_LOAD` interface is inferred from the `PDILoad` definition in Tapasco's `common/ip`) |
| `tapasco/pdi-loader.json` | Tapasco job file (`@ADF@` is filled in by `make jobfile`) (`DataStreamerVN` + `AIEPdiLoader` + AI-Engine + DMA-Streaming + PDI-Loader) |
| `host/reflash_aie_loader.cpp` | host tool that performs a reflash |
| `host/vector_norm.cpp` | host tool that runs the vector-norm example to check which AIE graph is live |
| `tools/make_aie_pdi.sh` | `libadf.a` to AIE-only partial PDI (bootgen) |
| `tools/pdi_info.py` | dumps and sanity-checks a PDI; `tools/cdo_parser.py`, `tools/cdo_decode.py` decode CDO streams |
| `aie/` | the Vector-Norm AIE graph (from tapasco-examples, PLIOs pinned to fixed shim tiles); `-DDOUBLE_OUTPUT` gives graph B |
| `build/` | every generated file: SystemVerilog, IP zips, AIE archives, partial PDIs, the bitstream copy, host tools |
| `docs/` | design notes, background on the PMC/IPI path, CDO format reference |
| `img/` | block-design and address-map screenshots from the development, referenced from `docs/background.md` |
| `sus-xrt/`, `sus-tapasco/` | submodules with the SUS AXI and Tapasco control-slave libraries |
| `vck5000_modules.sh` | pc2-specific environment (modules, licenses, Tapasco workspace) |

## Prerequisites

- Vivado/Vitis 2023.1 (`vivado`, `bootgen`, `aiecompiler`). `aiecompiler` is only needed to
  rebuild the AIE graphs; it reads `XILINX_VITIS` and `PLATFORM_FILE` (the VCK5000 `.xpfm`).
- A Tapasco checkout with the `PDI-Loader` feature (the PDILoad interface definition and the
  PDILoader core in `toolflow/vivado/common/ip`) and a workspace for the `vck5000` platform with the
  runtime built (`tapasco-build-libs`) and `tapasco-setup.sh` sourced. The Makefile reads
  `TAPASCO_WORK_DIR` and `TAPASCO_HOME_TCL` from it.
- `sus_compiler` 0.6.0 (`cargo install sus_compiler`; the `sus-0.5.0` tag marks the last version for SUS 0.5.0), `verilator` 5.x for simulation.
- `g++` with C++20, `python3`, `zip`.
- Clone with submodules: `git clone --recursive <this repo>`.

On pc2: `source vck5000_modules.sh`.

## Reproducing the setup

### 1. Build and simulate the PEs

```
make codegen      # sus_compiler -> build/aie_pdi_loader.sv, build/data_streamer_vn.sv
make sim          # Verilator: 13 loader scenarios (PE + Tapasco's PDILoader core) against the fake PLM,
                  # 5 streamer scenarios against a behavioural AIE (random stalls, scale 1 and 2);
                  # the loader testbench prints ALL OK, every streamer scenario OK
```

`make sim-xsim` runs the loader testbench headless in Vivado's simulator (`sus/tb/run_xsim.sh`).
Both take the loader core from `$TAPASCO_HOME_TCL/common/ip/PDILoader/src/PDILoader.sv`.

### 2. Package the PEs and import them into Tapasco

```
make package      # Vivado ipx -> build/AIEPdiLoader.zip, build/DataStreamerVN.zip, each followed by
                  # tapasco import ... as 10203 (AIEPdiLoader) / 10204 (DataStreamerVN)
```

### 3. The PDI-Loader feature

Nothing to install: the feature ships with Tapasco (`documentation/tapasco-features.md` there).
The job file enables it with

```
{ "Feature": "PDI-Loader", "Properties": { "ipi_channel": "2", "ila": "false" } }
```

For every `PDILoad` master interface of a PE it

- instantiates a `PDILoader` core in the host subsystem and connects the PE's interface to it;
  the core's `IPI_CHANNEL` and `TIMEOUT_CYCLES` parameters come from the `ipi_channel` (further loaders
  take the next channels) and `timeout_cycles` (default 2^30) properties;
- enables IPI0..IPI6 on the CIPS. All of them are required: the per-design 2023.1 PLM only
  scans as many IPI interrupt bits as there are IPI instances in the design, so with fewer
  channels present a request on a high channel is dropped silently;
- enables `S_AXI_LPD` and connects the loader's `M_AXI_LPD` master to it (through a SmartConnect
  when there are several loaders), since the IPI message RAM is only reachable over the direct
  PL-to-PS slave ports, not over the NoC;
- after Tapasco's address map is built, lets Vivado assign the fixed LPD addresses and checks
  that the loader reaches its `psv_ipi_<n>` block and `psv_ipi_buffer`.

Set `"ila": "true"` in the feature properties to add an AXI ILA on the LPD port (needs the Debug
feature); the probe file is written next to the bitstream.

### 4. AIE graphs

```
make aie          # aiecompiler: aie/ -> build/libadf_a.a, and with -DDOUBLE_OUTPUT -> build/libadf_b.a
```

Both archives come from the same tree; `sum_sqrt.cpp` multiplies the norm by 2.0 under
`#ifdef DOUBLE_OUTPUT`. The archives are ordinary make targets, so the job file and the
partial PDIs build them on demand when they are missing or older than the sources in `aie/`.
`graph.h` pins the three PLIOs to shim tiles 12, 13 and 14. That pinning is what makes the graphs
interchangeable at runtime: the PL side of the design is built once against those tiles,
and any graph that keeps them can be loaded by the reflasher.

### 5. Build the bitstream

```
make jobfile ADF=build/libadf_a.a    # build/pdi-loader.json (the default)
make bitstream                         # tapasco --jobsFile build/pdi-loader.json
```

Tapasco composes the design under `$TAPASCO_WORK_DIR/compose/axi4mm/vck5000/`; the target
copies the resulting PDI to `build/reconfigurable_bitstream.pdi`, plus `build/debug_probes.ltx`
when the feature's ILA was enabled. Load it with
`tapasco-load-bitstream build/reconfigurable_bitstream.pdi`. The IP zips and the job file are
order-only prerequisites: a missing bitstream is built, but changing them later does not
restart the multi-hour build on its own (`make -B bitstream` does).

### 6. Build the partial PDIs

```
make pdi          # build/libadf_a.pdi, build/libadf_b.pdi (bootgen)
make check-pdi    # structure and IDCODE check
```

`tools/make_aie_pdi.sh` extracts the six `aie.cdo.*.bin` sections from the archive and wraps
them into a partial PDI with one `aie_image` (id `0x1c000000`), the same image Tapasco appends
to the boot PDI. The IDCODE in its header must match the silicon or the PLM refuses the
image, so it is copied from `build/reconfigurable_bitstream.pdi`, the full PDI from the previous step. The
partial PDIs depend on it, so `make pdi` runs the bitstream build first if that file is
missing.

### 7. Build the host tools

```
make host         # build/reflash-aie-loader, build/vector-norm
```

### 8. Reflash

```
build/vector-norm                      # design A: SUCCESS
build/reflash-aie-loader build/libadf_b.pdi
build/vector-norm --expect-scale 2     # design B: SUCCESS (every output doubled)
build/reflash-aie-loader build/libadf_a.pdi
build/vector-norm                      # back to A
```

A successful run prints the PLMI status (`lo=0x0`) and the handshake length in design clock
cycles and microseconds. The IPI channel is fixed in the design (`ipi_channel` of the feature,
2 here; 5 is the channel xsdb uses, avoid it while a JTAG session is open).

### Return value and errors

The PE returns one 64-bit word: `[31:0]` is the PLMI status (0 = success) or
`0xFFFFFF00 | code` for a loader error (`FINISH_ERROR` of the PDILoad interface), `[63:32]` is
the XilLoader status when the PLM reported an error and the cycle count otherwise.

| code | meaning |
|---|---|
| 1 / 2 | AXI write / read response error: the LPD port is not reachable from the PE |
| 3 | timeout, the PLM never acknowledged: usually a channel the PLM is not servicing |
| 4 | PLM reported a non-zero status; decode `[63:32]` with `xloader.h` of embeddedsw 2023.1 |
| 5 | the channel still holds an unacknowledged earlier request |

The PLM's own log is visible from xsdb (`plm log` on the DPC target) if the micro-USB cable
is connected.

## How the handshake works

For channel n the loader uses the IPI registers at `0xFF330000 + n * 0x10000` and the message RAM
slot `0xFF3F0000 + (2 + n) * 0x200 + 0x40` (request to the PMC) with the response in the
same slot at `+0x20`. It writes the four request words `{0x030701, 0xF, addr_hi, addr_lo}`
(XilLoader `LOAD_SUBSYSTEM_PDI`, source DDR, PDI address as the PMC sees it:
`0x100_0000_0000 + Tapasco device offset`), reads the first word back to prove the RAM is
reachable, plants a sentinel in the response slot, writes the PMC bit into TRIG, polls OBS until the
PLM clears it, then polls the response slot until the sentinel has been replaced by the
PLMI status (the PLM acks before it has finished the load). The second word is the
XilLoader status. The `PDILoad` interface and the core are documented in Tapasco's
`toolflow/vivado/common/ip/PDILoader/README.md`; the step table and the bring-up log are in
[docs/aie_pdi_loader_design.md](docs/aie_pdi_loader_design.md); why the PMC has to do this and
why the earlier PL-only attempt could not are in [docs/background.md](docs/background.md).

## The DataStreamerVN PE

`sus/data_streamer_vn.sus` is a port of the Bluespec `DataStreamerVN` from
esa-tu-darmstadt/tapasco-examples (Vector-Norm), with the same ports, register map and data
layout, so Tapasco's DMA-Streaming and AI-Engine features connect it exactly like the
original and `vector-norm` accepts either (it tries the SUS VLNV first, then the Bluespec one).

- `S_AXIS_DMA` (512 bit): 8 interleaved (x, y) float pairs per beat. Each 256-bit half becomes
  one beat on `M_AXIS_AIE_X` (x0..x3) and one on `M_AXIS_AIE_Y` (y0..y3), sent together.
- `S_AXIS_AIE` (128 bit): z0..z3 from the graph; four beats are packed into one 512-bit beat
  on `M_AXIS_DMA`, with `tlast` on the final one.
- Registers: `SAMPLES` at 0x20 (number of pairs, a multiple of 16); the return value at 0x10
  is the cycle count from start to the last result beat. The PE raises its interrupt when
  `SAMPLES / 16` result beats have been sent.

The SUS PE is verified in simulation (`make sim`) against a behavioural AIE and on the card
(2026-10-21: bitstream with both SUS PEs, reflash A -> B -> A with correct Vector-Norm
results).

## TODO

- The default timeout of the loader (`timeout_cycles` = 2^30, about 3.4 s at 312.5 MHz) has only
  been exercised with 100 KB PDIs; multi-MB AIE images may need a larger value in the job file.
