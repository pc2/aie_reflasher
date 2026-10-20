# AI Engine reflasher for the VCK5000 under Tapasco

Reconfigure **only the AI Engine array** of a running Tapasco VCK5000 design, in a few tens of
milliseconds end to end, without touching the PL, the NoC, the DDR contents or the PCIe link.

A small PL processing element (`AIEPdiLoader`, written in [SUS](https://github.com/pc2/sus-compiler))
hands an AIE-only *partial PDI* that sits in card DDR to the Platform Loader and Manager
(PLM, the firmware running on the Versal PMC) over an Inter-Processor Interrupt (IPI). The PLM
then does exactly what it did for the AIE image at boot: parse the PDI, run the CDOs, load the
tile ELFs, release the cores. The host side is one Tapasco job: DMA the PDI, launch the PE,
read back the PLM's verdict.

```
host                         card DDR                        PL                        PS / PMC
reflash-aie-loader --DMA-->  aie_partial.pdi
                   --launch----------------------------->  AIEPdiLoader PE
                                                             | 4-word IPI request + TRIG
                                                             |  (S_AXI_LPD, 0xFF33xxxx / 0xFF3F0xxx)
                                                             v
                                                           PLM on the PMC: XLoader_LoadSubsystemPdi
                                                             |  PMC DMA reads the PDI from DDR,
                                                             |  executes the AIE CDOs (incl. NPI)
                                                             v
                                                           AIE array reconfigured, OBS cleared,
                                                             status in the IPI response buffer
                   <--return value (PLMI status, cycles)--  PE
```

This repository contains everything needed to reproduce the setup: the reflasher PE, the
`DataStreamerVN` example PE that feeds the AI Engine (a SUS port of the Bluespec PE from
esa-tu-darmstadt/tapasco-examples, so no Bluespec compiler is needed), simulation testbenches
for both, the Tapasco platform plugin, the host tools, the partial-PDI builder and the
Vector-Norm AIE graph. The graph is compiled twice (`aie/libadf_a.a`, `aie/libadf_b.a`); the
variants differ only in a `* 2.0` on the output, so a successful reflash is visible from the
host.

## Repository layout

| Path | Contents |
|---|---|
| `Makefile` | every build step (see below); no CMake |
| `sus/aie_pdi_loader.sus` | the `AIEPdiLoader` PE and its reusable core `pmc_pdi_loader` |
| `sus/data_streamer_vn.sus` | the `DataStreamerVN` PE: DMA stream in, x/y streams to the AIE, z stream back, DMA stream out |
| `sus/tb/` | SystemVerilog testbenches (Verilator or xsim): fake IPI block + PLM for the loader, behavioural AIE for the streamer |
| `tapasco/aie_reflasher_ipi.tcl` | Tapasco vck5000 plugin: enables IPI0..6 and `S_AXI_LPD` on the CIPS and wires the PE to it |
| `tapasco/pack_pdi_loader_kernel.tcl`, `tapasco/pack_data_streamer_vn.tcl` | Vivado IP packaging of the two PEs (register maps) |
| `tapasco/pdi-loader.json` | Tapasco job file (`@ADF@` is filled in by `make jobfile`) (`DataStreamerVN` + `AIEPdiLoader` + AI-Engine + DMA-Streaming) |
| `host/reflash_aie_loader.cpp` | host tool that performs a reflash |
| `host/vector_norm.cpp` | host tool that runs the vector-norm example to check which AIE graph is live |
| `bin/` | prebuilt copies of the two host tools (`make host` rebuilds them in place) |
| `tools/make_aie_pdi.sh` | `libadf.a` to AIE-only partial PDI (bootgen) |
| `tools/pdi_info.py` | dumps and sanity-checks a PDI; `tools/cdo_parser.py`, `tools/cdo_decode.py` decode CDO streams |
| `aie/src/` | the Vector-Norm AIE graph (from tapasco-examples, PLIOs pinned to fixed shim tiles); `-DDOUBLE_OUTPUT` gives graph B |
| `aie/` | the two compiled graphs `libadf_{a,b}.a` and the partial PDIs built from them |
| `docs/` | design notes, background on the PMC/IPI path, CDO format reference |
| `img/` | block-design and address-map screenshots from the development, referenced from `docs/background.md` |
| `sus-xrt/`, `sus-tapasco/` | submodules with the SUS AXI and Tapasco control-slave libraries |
| `vck5000_modules.sh` | pc2-specific environment (modules, licenses, Tapasco workspace) |

## Prerequisites

- Vivado/Vitis 2023.1 (`vivado`, `bootgen`, `aiecompiler`). `aiecompiler` is only needed to
  rebuild the AIE graphs; it reads `XILINX_VITIS` and `PLATFORM_FILE` (the VCK5000 `.xpfm`).
- A Tapasco checkout and workspace for the `vck5000` platform with the runtime built
  (`tapasco-build-libs`) and `tapasco-setup.sh` sourced. The Makefile reads
  `TAPASCO_WORK_DIR` and `TAPASCO_HOME_TOOLFLOW` from it.
- `sus_compiler` 0.4.0 (`cargo install sus_compiler`), `verilator` 5.x for simulation.
- `g++` with C++20, `python3`, `zip`.
- Clone with submodules: `git clone --recursive <this repo>`.

On pc2: `source vck5000_modules.sh`.

## Reproducing the setup

### 1. Build and simulate the PEs

```
make codegen      # sus_compiler -> build/aie_pdi_loader.sv, build/data_streamer_vn.sv
make sim          # Verilator: 8 loader scenarios against the fake PLM, 5 streamer scenarios
                  # against a behavioural AIE (random stalls, scale 1 and 2); all must print OK
```

`make sim-xsim` runs the loader testbench in Vivado's simulator.

### 2. Package the PEs and import them into Tapasco

```
make package      # Vivado ipx -> build/AIEPdiLoader.zip, build/DataStreamerVN.zip
make import       # tapasco import ... as 10203 (AIEPdiLoader) and 10204 (DataStreamerVN)
```

### 3. Install the platform plugin

```
make plugin       # copies tapasco/aie_reflasher_ipi.tcl to $TAPASCO_HOME_TOOLFLOW/vivado/platform/vck5000/plugins/
```

The plugin is activated by the `aie_reflasher_ipi` feature in the job file. It

- enables IPI0..IPI6 on the CIPS. All of them are required: the per-design 2023.1 PLM only
  scans as many IPI interrupt bits as there are IPI instances in the design, so with fewer
  channels present a request on a high channel is dropped silently;
- enables `S_AXI_LPD` and connects the PE's `ipi_lpd_interface` master to it, since the IPI
  message RAM is only reachable over the direct PL-to-PS slave ports, not over the NoC;
- after Tapasco's address map is built, lets Vivado assign the fixed LPD addresses and checks
  that `psv_ipi_0..5` and `psv_ipi_buffer` are mapped for the PE.

Set `"ila": "true"` in the feature properties to add an AXI ILA on the LPD port; the probe
file is written next to the bitstream.

### 4. AIE graphs (optional, the archives are checked in)

```
make aie          # aiecompiler: aie/src -> aie/libadf_a.a, and with -DDOUBLE_OUTPUT -> aie/libadf_b.a
```

Both archives come from the same tree; `sum_sqrt.cpp` multiplies the norm by 2.0 under
`#ifdef DOUBLE_OUTPUT`, which `make aie-b` defines (`make aie-a` builds the plain one).
`graph.h` pins the three PLIOs to shim tiles 12, 13 and 14. That pinning is what makes the graphs
interchangeable at runtime: the PL side of the design is built once against those tiles,
and any graph that keeps them can be loaded by the reflasher.

### 5. Build the bitstream

```
make jobfile ADF=$PWD/aie/libadf_a.a   # build/pdi-loader.json
make bitstream                         # tapasco --jobsFile build/pdi-loader.json
```

The PDI ends up under `$TAPASCO_WORK_DIR/compose/axi4mm/vck5000/` as
`axi4mm-vck5000--DataStreamerVN_1_AIEPdiLoader_1--313.pdi`. Load it with `tapasco-load-bitstream`.

### 6. Build the partial PDIs

```
make pdi          # aie/libadf_a.pdi, aie/libadf_b.pdi (bootgen)
make check-pdi    # structure and IDCODE check
```

`tools/make_aie_pdi.sh` extracts the six `aie.cdo.*.bin` sections from the archive and wraps
them into a partial PDI with one `aie_image` (id `0x1c000000`), the same image Tapasco appends
to the boot PDI. The IDCODE must match the silicon or the PLM refuses the image; the default
is the production VCK5000 (`0x14ca8093` / `1`). To copy it from a PDI that already boots on
your card instead: `make pdi REF_PDI=/path/to/full.pdi`.

### 7. Build the host tools

```
make host         # bin/reflash-aie-loader, bin/vector-norm
```

### 8. Reflash

```
bin/vector-norm                      # design A: SUCCESS
bin/reflash-aie-loader aie/libadf_b.pdi
bin/vector-norm --expect-scale 2     # design B: SUCCESS (every output doubled)
bin/reflash-aie-loader aie/libadf_a.pdi
bin/vector-norm                      # back to A
```

A successful run prints the IPI channel, the PLMI status (`lo=0x0`) and the handshake
length in design clock cycles and microseconds. `--ipi N` picks the IPI channel (default 2;
5 is the channel xsdb uses, avoid it while a JTAG session is open). `--ping` sends the
harmless XilPlmi FEATURES query instead of a load to prove the path.

### Return value and errors

The PE returns one 64-bit word: `[31:0]` is the PLMI status (0 = success) or
`0xFFFFFF00 | code` for a PE-local error, `[63:32]` is the XilLoader status when the PLM
reported an error and the cycle count otherwise.

| code | meaning |
|---|---|
| 1 / 2 | AXI write / read response error: the LPD port is not reachable from the PE |
| 3 | timeout, the PLM never acknowledged: usually a channel the PLM is not servicing |
| 4 | PLM reported a non-zero status; decode `[63:32]` with `xloader.h` of embeddedsw 2023.1 |
| 5 | the channel still holds an unacknowledged earlier request |
| 6 | IPI channel > 5 (IPI6 has no message buffer) |

The PLM's own log is visible from xsdb (`plm log` on the DPC target) if the micro-USB cable
is connected.

## How the handshake works

For channel n the PE uses the IPI registers at `0xFF330000 + n * 0x10000` and the message RAM
slot `0xFF3F0000 + (2 + n) * 0x200 + 0x40` (request to the PMC) with the response in the
same slot at `+0x20`. It writes the four request words `{0x030701, 0xF, addr_hi, addr_lo}`
(XilLoader `LOAD_SUBSYSTEM_PDI`, source DDR, PDI address as the PMC sees it:
`0x100_0000_0000 + Tapasco device offset`), reads the first word back to prove the RAM is
reachable, plants a sentinel in the response slot, writes the PMC bit into TRIG and polls OBS
until the PLM clears it. The response slot then holds the PLMI status and the XilLoader
status. Details, the step table and the bring-up log are in
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

The checked-in `libadf` archives were compiled from `aie/src` with the Bluespec PE still in
the design; the SUS PE is verified in simulation (`make sim`) against a behavioural AIE but
has not yet been run on hardware.

## TODO

- Run the SUS `DataStreamerVN` on the card (rebuild the bitstream with both PEs, then the
  reflash sequence above) and confirm the Vector-Norm results.
- The timeout of the loader PE (`TIMEOUT_CYCLES = 2^28`, about 1 s at 312.5 MHz) was chosen
  for 100 KB PDIs; multi-MB AIE images may need a larger value.
