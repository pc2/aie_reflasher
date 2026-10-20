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

This repository contains everything needed to reproduce the setup: the PE, its simulation
testbench, the Tapasco platform plugin, the host tools, the partial-PDI builder and two
compiled AIE graphs (`aie/libadf_a.a`, `aie/libadf_b.a`) that differ only in a `* 2.0` on the
output, so a successful reflash is visible from the host.

## Repository layout

| Path | Contents |
|---|---|
| `Makefile` | every build step (see below); no CMake |
| `sus/aie_pdi_loader.sus` | the `AIEPdiLoader` PE and its reusable core `pmc_pdi_loader` |
| `sus/tb/` | SystemVerilog testbench with a behavioural model of the IPI block and the PLM (Verilator or xsim) |
| `tapasco/aie_reflasher_ipi.tcl` | Tapasco vck5000 plugin: enables IPI0..6 and `S_AXI_LPD` on the CIPS and wires the PE to it |
| `tapasco/pack_pdi_loader_kernel.tcl` | Vivado IP packaging of the PE (register map) |
| `tapasco/pdi-loader.json` | Tapasco job file (`@ADF@` is filled in by `make jobfile`) (`DataStreamerVN` + `AIEPdiLoader` + AI-Engine + DMA-Streaming) |
| `host/reflash_aie_loader.cpp` | host tool that performs a reflash |
| `host/vector_norm.cpp` | host tool that runs the vector-norm example to check which AIE graph is live |
| `bin/` | prebuilt copies of the two host tools (`make host` rebuilds them in place) |
| `tools/make_aie_pdi.sh` | `libadf.a` to AIE-only partial PDI (bootgen) |
| `tools/pdi_info.py` | dumps and sanity-checks a PDI; `tools/cdo_parser.py`, `tools/cdo_decode.py` decode CDO streams |
| `aie/` | the two AIE graphs as `libadf_*.a` and the partial PDIs built from them |
| `docs/` | design notes, background on the PMC/IPI path, CDO format reference |
| `img/` | block-design and address-map screenshots from the development, referenced from `docs/background.md` |
| `sus-xrt/`, `sus-tapasco/` | submodules with the SUS AXI and Tapasco control-slave libraries |
| `tapasco-examples/` | submodule; provides the `DataStreamerVN` PE and the Vector-Norm AIE graph source |
| `vck5000_modules.sh` | pc2-specific environment (modules, licenses, Tapasco workspace) |

## Prerequisites

- Vivado/Vitis 2023.1 (`vivado`, `bootgen`, `aiecompiler`) and the VCK5000 Vitis platform.
- A Tapasco checkout and workspace for the `vck5000` platform with the runtime built
  (`tapasco-build-libs`) and `tapasco-setup.sh` sourced. The Makefile reads
  `TAPASCO_WORK_DIR` and `TAPASCO_HOME_TOOLFLOW` from it.
- `sus_compiler` 0.4.0 (`cargo install sus_compiler`), `verilator` 5.x for simulation.
- `g++` with C++20, `python3`, `zip`.
- Clone with submodules: `git clone --recursive <this repo>`.

On pc2: `source vck5000_modules.sh`.

## Reproducing the setup

### 1. Build and simulate the PE

```
make codegen      # sus_compiler -> build/aie_pdi_loader.sv
make sim          # Verilator: 8 scenarios against the fake PLM, all must print OK
```

`make sim-xsim` runs the same testbench in Vivado's simulator.

### 2. Package the PE and import it into Tapasco

```
make package      # Vivado ipx -> build/AIEPdiLoader.zip
make import       # tapasco import build/AIEPdiLoader.zip as 10203 -p vck5000
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

### 4. Build the bitstream

The design also needs the `DataStreamerVN` PE from `tapasco-examples/Vector-Norm` (imported
as ID 8847) and an AIE graph archive. See the TODO below for building those; the archives
used here are checked in as `aie/libadf_a.a` and `aie/libadf_b.a`.

```
make jobfile ADF=$PWD/aie/libadf_a.a   # build/pdi-loader.json
make bitstream                         # tapasco --jobsFile build/pdi-loader.json
```

The PDI ends up under `$TAPASCO_WORK_DIR/compose/axi4mm/vck5000/` as
`axi4mm-vck5000--DataStreamerVN_1_AIEPdiLoader_1--313.pdi`. Load it with `tapasco-load-bitstream`.

### 5. Build the partial PDIs

```
make pdi          # aie/libadf_a.pdi, aie/libadf_b.pdi (bootgen)
make check-pdi    # structure and IDCODE check
```

`tools/make_aie_pdi.sh` extracts the six `aie.cdo.*.bin` sections from the archive and wraps
them into a partial PDI with one `aie_image` (id `0x1c000000`), the same image Tapasco appends
to the boot PDI. The IDCODE must match the silicon or the PLM refuses the image; the default
is the production VCK5000 (`0x14ca8093` / `1`). To copy it from a PDI that already boots on
your card instead: `make pdi REF_PDI=/path/to/full.pdi`.

### 6. Build the host tools

```
make host         # bin/reflash-aie-loader, bin/vector-norm
```

### 7. Reflash

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

## TODO

- **Vector-Norm sources.** The `DataStreamerVN` PE and the AIE graph come from the
  `tapasco-examples` submodule (`Vector-Norm/build_bitstream.sh` builds the Bluespec PE and
  imports it as 8847). The two `libadf` archives in `aie/` were compiled from
  `tapasco-examples/Vector-Norm/aie` with pinned PLIO locations (insert after line 22 of
  `src/graph.h`):

  ```cpp
  location<PLIO>(in_x)  = shim(6 + 6, 2 * 0);
  location<PLIO>(in_y)  = shim(6 + 7, 2 * 0);
  location<PLIO>(out_z) = shim(6 + 8, 2 * 0);
  ```

  and, for variant B, a multiply by 2.0 in `src/sum_sqrt.cpp` line 14:

  ```cpp
  *outIt++ = aie::mul(aie::sqrt(aie::add(inX_i, inY_i)), aie::broadcast<float, VECTOR_SIZE>(2.0f));
  ```

  Those modifications are not yet captured as files or patches in this repository, and the
  Makefile has no targets for the Bluespec PE or `aiecompiler`. Pinning the PLIOs is what
  makes the two graphs interchangeable at runtime: the PL side of the design is built once
  for fixed shim tiles.
- The timeout of the PE (`TIMEOUT_CYCLES = 2^28`, about 1 s at 312.5 MHz) was chosen for
  100 KB PDIs; multi-MB AIE images may need a larger value.
