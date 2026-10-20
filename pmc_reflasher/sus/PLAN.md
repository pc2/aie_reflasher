# AIEPdiLoader: plan for the dedicated AIE reflash PE

Replaces the CDO-interpreting `AIEngineReflasher` with a PE that does one thing: hand a
partial PDI in card DDR to the PLM over IPI and report the PLM's verdict. The PLM does
the AIE configuration. Written in SUS, same library modules and port names as before so
the Tapasco side changes are small.

## 1. Modules (`aie_pdi_loader.sus`, compiles with sus_compiler 0.4.0)

### `pmc_pdi_loader #(ADDR_WIDTH, TIMEOUT_CYCLES)` (reusable core)

- Owns one `axi4_lite_writer` and one `axi4_lite_reader` (from `sus-xrt/axi_lite.sus`),
  exported as a plain AXI4-Lite master (`awaddr .. rready`, all latency `'0`).
- Interface: `action start(bool[64] pdi_ps_addr, bool[32] cmd_word, int channel)`, `output bool busy`,
  `trigger done(bool ok, error_code, bool[32] plmi_status, bool[32] loader_status)`,
  `action rst`.
- Addresses are computed per request from the `channel` argument n (0..5; 5 is the PLM's
  xsdb-master channel, the only one served without a subsystem configuration):
  TRIG/OBS at `0xFF330000 + n*0x10000`, request buffer
  `0xFF3F0000 + (2+n)*0x200 + 0x40`, response buffer `0xFF3F0000 + 0x200 + (2+n)*0x40 + 0x20`.
  IPI6 and PMC_NOBUF have no message buffer, so n > 5 is rejected with error 6 before
  the bus is touched. (2026-10-20: was a `gen` parameter `IPI_CHANNEL` before.)
- Sequencer: a 10-step table driven by a 6-state machine
  (`S_WRITE -> S_WRITE_WAIT` for writes, `S_READ -> S_READ_WAIT` for reads/polls):

  | step | op | address | data / condition |
  |---|---|---|---|
  | 0..3 | write | req+0..+12 | `0x030701`, `0xF`, addr_hi, addr_lo |
  | 4 | poll | req+0 | until `== 0x030701` (proves the message RAM is reachable) |
  | 5 | write | resp+0 | `0xDEADBEEF` sentinel |
  | 6 | write | TRIG | `0x2` (PMC bit) |
  | 7 | poll | OBS | until bit 1 clear (PLM acked) |
  | 8, 9 | read | resp+0, resp+4 | PLMI status, XilLoader status |

  Every write waits for its BRESP before the next step, so ordering never depends on the
  interconnect. Any BRESP/RRESP != OKAY, a timeout (`TIMEOUT_CYCLES`, default 2^28 ~ 1 s at
  250 MHz) or a non-zero PLMI status ends in `done(ok=false, code, ...)`.
- Error codes: 1 write response, 2 read response, 3 timeout, 4 PLM status non-zero,
  5 OBS busy before TRIG (stale request, PLM not servicing the channel), 6 channel > 5.

### `AIEPdiLoader` (Tapasco PE)

- `tapasco_ctrl_slave#(NUM_INPUT_REGS: 2)`: reg 0 = PS physical address of the PDI
  (`0x100_0000_0000 + Tapasco device offset`), reg 1 = `[0:3]` AWPROT, `[4:7]` ARPROT
  (0 = secure/unprivileged, which the IPI apertures accept), `[8:12]` AWCACHE, `[12:16]`
  ARCACHE, `[16:19]` IPI channel (host default 5), `[32:64]` IPI command word override
  (0 = LOAD_SUBSYSTEM_PDI, `0x010100` = XilPlmi FEATURES ping).
- Exports `s_axi_control` and the `small_axil` master (64-bit address, 32-bit data) with
  the exact port names of the old PE, so `pack_*.tcl` and the Tapasco plugin stay similar.
  No bulk port any more.
- Return value (`ctrl.finish`): `[0:32]` PLMI status (0 = success) or `0xFFFFFF00|err` for
  local errors, `[32:64]` XilLoader status.

## 2. Build and package

```
cd pmc_reflasher/sus && make codegen        # sus_compiler -> build/aie_pdi_loader.sv (+ tb stub)
make package PART=xcvc1902-vsvd1760-2MP-e-S # Vivado ipx package -> build/AIEPdiLoader.zip
tapasco import build/AIEPdiLoader.zip as 8848 -p vck5000
```

`pack_pdi_loader_kernel.tcl` is `pack_reflash_kernel.tcl` with the register map
`CTRL 0x00`, `PDI_ADDRESS 0x20 (64)`, `AXI_CONFIG 0x30 (64)` and `small_axil` as the only
associated bus interface.

## 3. Tapasco platform changes (plugin)

The PE now has a single AXI4-Lite master and it must reach the LPD directly:

1. Keep `enable_ipi5` (IPI5 segment) and the `S_AXI_LPD` enable from `enable_ipi5.tcl`.
2. Replace the "join bulk and small" step: there is no bulk port, so connect
   `target_ip/small_axil` through a SmartConnect straight to `/host/versal_cips_0/S_AXI_LPD`
   (AXI4-Lite -> AXI4 conversion is done by the SmartConnect; clock = design clock on
   `s_axi_lpd_aclk`). Remove the PE from Tapasco's memory subsystem connection list.
3. The NoC-to-PMC output and the `0xFF` exclusions become unnecessary: nothing reaches the
   PMC through the NoC any more. Drop them to keep the design small.
4. After `assign_bd_address`, the PE's `small_axil` space must show
   `S_AXI_LPD/pspmc_0_psv_ipi_5` at `0xFF380000` (64K) and `psv_ipi_buffer` at
   `0xFF3F0000` (4K), nothing from `NOC_PMC_AXI_0`.

## 4. Host tool

`host/reflash_aie_loader.cpp`: DMA the partial PDI into DDR with Tapasco, launch the PE with
`(0x100_0000_0000 + offset, axprot_word)`, decode the 64-bit return value. Same CLI as
`reflash-aie-pe`.

## 5. Verification before hardware (done here with Verilator 5.052: `make sim-verilator`)

Result on 2026-10-19: `happy` (PLMI status 0), `plm_err` (status 0x1234 propagated) and
`decerr` (unreachable LPD -> 0xFFFFFF01) all pass; the traced transaction sequence is
exactly the 10-step table above. The simulation also caught two bugs before hardware:
the decimal IPI base constants were off by 0x10000 (SUS 0.4.0 has no hex int literals),
and `;` is not a statement separator in SUS.


1. `make codegen` also emits the SUS testbench stub (`build/AIEPdiLoader_tb.sv`).
2. `tb/fake_plm_axil.sv` is an AXI4-Lite slave model of the IPI block: a small RAM for the
   message buffers, a TRIG register that sets the OBS bit, and a "PLM" process that, some
   cycles after TRIG, writes a programmable status into the response buffer and clears OBS.
   It also returns DECERR for addresses outside the IPI block so the readback step can be
   exercised.
3. `tb/sim.tcl` runs xsim: start the PE through `s_axi_control` (write reg 0 and reg 1,
   then CTRL bit 0), wait for `intr`, read the result register and check:
   - happy path: result `[0:32] == 0`;
   - PLM error: fake status `0x1234` -> result `[0:32] == 0x1234`;
   - unreachable buffer (DECERR) -> result `0xFFFFFF01`;
   - no ack -> result `0xFFFFFF03` after `TIMEOUT_CYCLES` (use a small override in the TB).

## 6. Bring-up order on the card

1. Build the Tapasco design with the new PE and the plugin changes; verify the address map.
2. Load it; run `vector-norm` for the baseline.
3. `reflash-aie-loader libadf_a.pdi` (reload of the running design, must return 0).
4. `reflash-aie-loader libadf_b.pdi`, `vector-norm` again: doubled outputs.
5. Time it: the PE return already includes the whole PLM load, so Tapasco's job runtime is
   the reflash latency.

## 7. Hardware bring-up log

- 2026-10-20: first run timed out (PE error 3). ILA showed every bus transaction correct;
  xsdb showed ISR bit 7 set, IMR bit 7 masked, response buffer untouched, no PLM log line,
  and xsdb's own `plm set-log-level` (also IPI5) timing out on a fresh boot. Root cause:
  the per-design 2023.1 PLM sizes its IPI handling by `XPAR_XIPIPSU_NUM_TARGETS` (= IPI
  instances in the design). With only IPI5 enabled that is 4, and `XPlmi_GicAddTask` loops
  over ISR bit indices 0..3, never reaching bit 7: the request is masked and dropped
  silently. Fix: enable IPI0..IPI6 in the CIPS (plugin updated). Verify after rebuild with
  `plm set-log-level 0x4` from xsdb on the DPC target: it must acknowledge now.

## 8. Open points

- `TIMEOUT_CYCLES = 2^28` is a guess at the PLM's worst case for a ~100 KB PDI; raise it if
  big designs (multi-MB ELFs) hit error 3 while the PLM is still working.
- IPI5 is shared with xsdb. If JTAG debugging and reflashing must coexist, try
  `reflash-aie-loader --ipi 0..4`; whether the PLM accepts a channel that no subsystem
  claims is untested (for non-IPI5 channels it calls `XPmSubsystem_GetSubSysIdByIpiMask`,
  which returns INVALID_SUBSYSID on a design without isolation config). The plugin maps
  psv_ipi_0..5 so this can be tried without a rebuild.
- The PE issues secure (AxPROT[1]=0) transactions; if a future design enables LPD XPPU
  protection, the PL master ID will need an aperture entry.
