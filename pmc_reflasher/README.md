# PMC-based AI Engine reflasher for the VCK5000 (Tapasco)

> **Chosen path (2026-10-16): PE-initiated IPI.** The existing `AIEngineReflasher` PE
> already executes `write64`/`mask_poll64` over an AXI-Lite port that Tapasco routes into
> the PMC/LPD address space. Enable IPI5 in the CIPS (`tapasco/enable_ipi5.tcl`), rebuild,
> then `reflash-aie-pe aie_b.pdi` drives the PLM's partial-PDI load through that PE. No
> firmware, no new BAR, no NoC changes. See "Variant chosen" at the end. The A72-firmware
> and direct-PCIe variants below remain as fallbacks.

Reconfigure only the AI Engine array of a running Tapasco VCK5000 design, with the PL,
NoC, DDR and PCIe link untouched. The PL variant in the parent directory failed because a
handful of CDO commands write the AIE NPI block at `0xF70A0000`, which only the PMC may
touch. So here the PMC does the whole job: the **PLM** (the firmware already running on the
PMC in every Tapasco PDI) loads a *partial PDI* containing just the AIE CDOs, exactly as it
does for the full AIE image at boot.

This is also how XRT reconfigures the AIE on the stock VCK5000 shell: the VMR firmware on
the R5 hands the partial PDI from the xclbin to the PLM over IPI
(`Xilinx/VMR vmr/src/rmgmt/rmgmt_xfer.c` -> xilfpga -> `XMailbox` -> IPI command
`{0x030701, 0xF, addr_hi, addr_lo}` -> PLM `XLoader_LoadSubsystemPdi`). We skip the xclbin,
XGQ queues and FreeRTOS and keep only that one IPI call.

```
host (Tapasco DMA)        card DDR (DDR_LOW3 = 0x100_0000_0000 from the PS)        PS
reflash-aie  --PCIe-->   [req mailbox][resp mailbox][log][aie_partial.pdi]
                              ^ polls                 |
                              |                        A72 #0 bare-metal firmware
                              +------ writes resp <----+   |
                                                           | IPI: LOAD_SUBSYSTEM_PDI(DDR, addr)
                                                           v
                                                         PMC / PLM  --NoC (ps_pmc -> aie)-->  AIE array
                                                           (executes the CDOs incl. NPI 0xF70A0000)
```

Nothing in the Tapasco block design changes. The NoC connectivity Tapasco already builds is
sufficient: the A72 (`ps_cci` ports S00..S03) reaches all DDR controllers, and the PMC
(`ps_pmc` S05) reaches both DDR and the AIE (`M01_AXI`). That is the same path the PLM used
to configure the AIE at boot.

## Components

| Path | What |
|---|---|
| `common/reflash_proto.h` | Mailbox layout and command/status codes shared by host and firmware |
| `firmware/main.c` | Bare-metal A72 app: poll mailbox, send `LOAD_SUBSYSTEM_PDI` IPI, report PLM status |
| `firmware/build_arm.tcl` | xsct script: standalone BSP from an XSA, app linked into OCM |
| `firmware/load_firmware.tcl` | xsdb script to start the ELF over JTAG (development path) |
| `host/reflash_aie.cpp` | Tapasco host tool: copy PDI to DDR, ring mailbox, wait, dump firmware log |
| `tools/make_aie_pdi.sh` | `libadf.a` (or the six `aie.cdo.*.bin`) -> AIE-only partial PDI via bootgen |
| `tools/embed_elf.sh` | Append the firmware to an existing PDI so the PLM boots it |
| `tapasco/aie_reflasher_fw.tcl` | Tapasco plugin: export XSA, optionally embed the ELF at build time |

## Flow

1. **Build the Tapasco design once with the plugin** (copy `tapasco/aie_reflasher_fw.tcl` to
   `$TAPASCO_HOME_TOOLFLOW/vivado/platform/vck5000/plugins/`, add
   `{"Feature": "AIE-Reflasher", "Properties": {}}` to the job). It writes
   `tapasco_vck5000.xsa` into the Vivado project directory. Any Tapasco VCK5000 build
   gives a usable XSA; only the CIPS matters for the BSP.
2. **Build the firmware**: `XSA=.../tapasco_vck5000.xsa xsct firmware/build_arm.tcl`
   -> `firmware/build/aie_reflasher/Debug/aie_reflasher.elf`.
3. **Get the firmware onto the card**, either
   - at build time: rebuild with `"elf": "/path/aie_reflasher.elf"` in the feature
     properties, or run `tools/embed_elf.sh in.pdi aie_reflasher.elf out.pdi` on the PDI
     Tapasco produced, then load that PDI as usual; or
   - at run time over JTAG: `xsdb firmware/load_firmware.tcl .../aie_reflasher.elf`
     (needs the micro-USB cable and `hw_server`).
4. **Build the partial PDI** for the design you want to switch to:
   `tools/make_aie_pdi.sh ../libadf_b.a aie_b.pdi` (also accepts a directory holding the
   six `aie.cdo.*.bin`, e.g. `../tests/AIEngineReflasher/adf_b`).
5. **Reflash**: `mkdir host/build && cd host/build && cmake .. && make` then
   `./reflash-aie aie_b.pdi --log`. Exit code 0 and `state=ok plmi_status=0x0` means the
   PLM accepted and executed the image. `--ping` checks the firmware without loading.

The host tool reserves device memory `[0, 16 MiB + 64 KiB)` with Tapasco's fixed allocator so
nothing else lands on the mailbox. Change `REFLASH_REGION_DEV_OFFSET` in the header if that
collides with your DMA-streaming buffers; host and firmware both read it from there.

## Why the PLM, and why this is minimal

- The PLM already contains a complete CDO interpreter, the AIE ELF loader and the NPI access
  rights. Re-implementing any of it (our PL core, or libxaie on the A72 as the AIR firmware
  does) means re-deriving undocumented behaviour; the PLM is the reference implementation.
- The partial-PDI path is a supported, access-controlled IPI command
  (`XPLMI_ALL_IPI_FULL_ACCESS(XLOADER_CMD_ID_LOAD_SUBSYSTEM_PDI)` in
  `embeddedsw/lib/sw_services/xilloader/src/common/server/xloader_cmd.c`), stable since
  2020.x, and the exact one XRT's VMR uses.
- The firmware is a single poll loop, no interrupts, no OS, about 200 lines; the only driver
  it uses is `xipipsu`. The BSP's `xilfpga` library wraps the same call if you prefer
  `XFpga_BitStream_Load(..., PDI_LOAD)` to hand-rolled IPI words.

The "AIR" reference (Xilinx/ROCm-air-platforms) does **not** go through XRT: its A72
firmware DMAs tile memory itself with libxaie and does the NPI resets by hand, and the
full PDI is only loaded once over JTAG. It is the libxaie-on-A72 alternative to this design,
not an XRT flow.

## Bare metal or an RTOS?

Bare metal (Vitis "standalone" BSP), on A72 #0. Reasons:

- The job is one blocking call per request; there is nothing to schedule. VMR needs FreeRTOS
  because it multiplexes sensors, flash, clocks, xclbin parsing and PCIe queues. The AIR
  firmware, which is the closest sibling to ours, is standalone too.
- The standalone BSP already provides `xipipsu`, `xilfpga`, caches, `usleep` and a serial
  console. There is nothing an RTOS would add except a scheduler and a larger surface to
  debug without a UART.
- The R5 is not an option: it is a 32-bit core and Tapasco maps DDR only at
  `0x100_0000_0000` (DDR_LOW3), which the R5 cannot address without extra translation.
  The A72 is 64-bit and the BSP's MMU table has a DDR_LOW3 entry.

If you ever want more than "load this PDI" on the card (e.g. a queue of AIE jobs, or
AIE reconfiguration synchronised with PL kernels), that is the point where FreeRTOS on the
A72 or the AIR firmware becomes worth it.

## Can I ssh into the card?

No. The VCK5000's PS has no network interface wired out; the only off-card paths are the
PCIe link and the bracket micro-USB (FT4232H: JTAG plus UART). The stock XRT shell does
run a small PetaLinux on the APU (the `xrt-apu` package: ERT and PS kernels), but the host
talks to it exclusively through XRT's shared-memory queues, not SSH. In a Tapasco PDI the
A72 does nothing at all until something starts it.

Your ways in:

- **JTAG** via the micro-USB cable: `xsdb` to load/debug the firmware, Vivado HW manager
  to program PDIs. Loading a full PDI this way drops the PCIe link; the AIR README warns
  the host may hang, use `pci_remove.sh`-style unbinding first.
- **UART** on the same cable (`screen /dev/ttyUSBx 115200`): PLM boot log and the
  firmware's `xil_printf`. Which MIO pins reach the FTDI is unclear: Tapasco configures
  `PS_UART0` on `PS_MIO 16..17`, the AIR platform (which has a working console) on
  `PMC_MIO 16..17`. Check against the shell XSA or UG1428 before relying on it.
- **Shared DDR over PCIe**: what this reflasher uses. The firmware mirrors its log into
  the DDR ring, so `reflash-aie --log` works with no cable at all.

## Things to verify on first bring-up (ordered by likelihood of biting)

1. **IPI channel for the A72**: the BSP must define `XPAR_XIPIPSU_0_DEVICE_ID` and
   `XPAR_XIPIPS_TARGET_PSV_PMC_0_CH0_MASK`. CIPS defaults assign IPI0 to the A72; if the
   generated `xparameters.h` lacks them, rebuild with `"enable_ipi": "true"`.
2. **Firmware fits in OCM** (256 KiB). The linker rewrite in `build_arm.tcl` puts
   everything there. If `app build` overflows, give it a reserved DDR window instead
   (and keep the Tapasco allocator away from it).
3. **MMU covers DDR_LOW3**: the Versal A72 BSP's `translation_table.S` has a
   `DDR_LOW_3_REGION_START_ADDR` entry sized from the XSA. Confirm
   `XPAR_*DDR_LOW3*` appears in `xparameters.h`; otherwise the mailbox reads fault.
4. **PLM accepts an AIE image reload**. The PLM tracks loaded images by ID
   (`0x1c000000` for `aie_image`); reloading the same ID is the normal DFX/partial
   path. If `loader_status` is non-zero, decode it with the XilLoader error list in
   `xloader.h`; common causes are a PDI built by a different tool version than the PLM
   (both must be 2023.1 here) or the PDI address not being readable by the PMC DMA.
5. **UART pin mapping** as noted above, only if you need the console.

## Direct variant: the host talks to the PLM itself (no firmware)

The A72 firmware above does nothing but copy 4 words into an IPI buffer and poke one
register. The host can do that through PCIe if the design gives it a window onto the IPI
block. Then the whole reflash is: DMA the partial PDI into card DDR, write the IPI
request, ring the doorbell, poll for the ack. Files: `host/reflash_aie_direct.cpp`
and the plugin sketch `tapasco/aie_reflasher_direct.tcl`.

**What the PLM expects.** It services IPI channels IPI0..IPI5 (PMC IMR mask `0xFC`), and
nothing identifies the sender beyond "which channel's trigger register was written". A PCIe
master that can write those registers is indistinguishable from the A72. IPI5 is special:
the PLM calls it the xsdb master (`XPLMI_IPI_XSDB_MASTER_MASK`) and skips the
subsystem lookup for it, so it is the channel to impersonate when no A72 image exists.
`LOAD_SUBSYSTEM_PDI` is `XPLMI_ALL_IPI_FULL_ACCESS`, non-secure requests allowed.

**Register map** (Versal, from the `ipipsu` driver, `xplmi_ipi.c` and ATF `plat_ipi.h`):

| Thing | Value |
|---|---|
| Channel register blocks | PMC `0xFF320000`, IPI0 `0xFF330000` ... IPI5 `0xFF380000` (TRIG +0x0, OBS +0x4, ISR +0x10) |
| Channel bit masks / buffer index | PMC `0x2`/1, IPI0 `0x4`/2, IPI1 `0x8`/3, ... IPI5 `0x80`/7 |
| Message RAM | `0xFF3F0000 + src_index*0x200 + dst_index*0x40`, response at +0x20 |
| Request X -> PMC | X's group, PMC target: `0xFF3F0000 + idx(X)*0x200 + 0x40` |
| Response PMC -> X | PMC's group, X target: `0xFF3F0000 + 0x200 + idx(X)*0x40 + 0x20` |
| Command words | `{0x030701, 0xF, addr_hi, addr_lo}`; `addr = 0x100_0000_0000 + Tapasco device offset` |
| Handshake | write 4 words, write `0x2` to X's TRIG, poll X's OBS bit `0x2` until clear, read response[0] (PLMI status) and [1] (loader status) |

**Yes, the data just sits in DDR.** The PLM's loader reads the PDI with the PMC DMA over
the PMC NoC port (`ps_pmc` -> MC, already connected). It must be a bootgen partial PDI
(`tools/make_aie_pdi.sh`), not raw CDO: the loader parses the PDI headers first. Raw CDO
commands could also be sent one by one as IPI messages, but at 6 payload words per message
that is far slower than one DMA'd PDI.

**What the design needs.** A PCIe window onto AXI `0xFF300000` (1 MiB covers all
channels and the message RAM) and a NoC route from the CPM ports to the PMC slave:

1. Window: a new PF0 BAR4 as AXI bridge master with `PCIEBAR2AXIBAR` = `0xFF300000`
   (BAR0/BAR2 untouched, tlkm unaffected), or a NoC `REMAPS` entry mapping a spare 1 MiB
   of BAR0 (e.g. `0x201_0300_0000`) to `0xFF300000`. The plugin sketch does the BAR.
2. Route: enable `NOC_PMC_AXI_0` on the CIPS, add a NoC output of category `ps_pmc`, and
   add it to the `CONNECTIONS` of `S06_AXI`/`S07_AXI`. Your PL experiment already proved
   the PMC NSU exposes LPD peripherals (OCM, TCM, PSM, ADMA appear behind it), so the IPI
   block at `0xFF3xxxxx` should be reachable the same way.

Host side: `reflash-aie-direct aie_b.pdi` (auto-detects `10ee:b03f`, mmaps
`/sys/bus/pci/devices/<bdf>/resource4`, uses IPI5). `--ping` sends the harmless XilPlmi
features query to prove the path before touching the loader. Use `--bar 0 --bar-offset
0x3000000` for the NoC-remap variant.

**Risks specific to this variant.**
- LPD XPPU: if protection were enabled, non-PS masters would be blocked at the IPI
  apertures. Tapasco's CIPS has no isolation configured, so XPPU should be off. A read of
  OBS returning `0xFFFFFFFF` or a NoC decode error is the symptom.
- Posted writes: the buffer words and the TRIG write travel the same path, but the tool
  reads the buffer back before ringing the doorbell to be safe.
- IPI5 is shared with xsdb. Do not run the tool while a JTAG session is sending PLM
  commands.
- Triggering the PLM from a channel whose owner never booted is the one thing nobody at
  AMD intended. The dispatcher code does not check for it, but it is the first thing to
  suspect if the ack never comes (check PMC ISR via the same window).

If this works it is the simplest possible reflasher: one bootgen call offline, one DMA and
five register writes online, zero code on the card.

## Variant chosen: the existing PE performs the IPI handshake

Why this one: your `AddressSegments.csv` shows the PE's `small_axil`/`bulk_axi` masters
already reach the LPD through `NOC_PMC_AXI_0` (`psv_ipi_pmc` at `0xFF320000`,
`psv_ipi_psm`, OCM, TCM, PSM, ADMA ...). What is missing are the per-channel blocks
`psv_ipi_0..5` and the message RAM `psv_ipi_buffer` (`0xFF3F0000`). They are absent
because Tapasco never enables an IPI channel in the CIPS; `PS_GEN_IPI5_ENABLE 1` makes them
appear (confirmed in AMD's `vck190_axi_cci_bd.tcl`, whose enabled IPIs list exactly those
segment names). After that, the PE can run this 9-command stream unchanged. The PE ignores AXI error
responses, so the readback poll and the sentinel make an unreachable path hang the PE
instead of passing silently:

```
write64     0xFF3F0E40 0x00030701      # IPI5 -> PMC request buffer: LOAD_SUBSYSTEM_PDI
write64     0xFF3F0E44 0x0000000F      # PDI source = DDR
write64     0xFF3F0E48 <pdi_addr_hi>   # 0x100_0000_0000 + Tapasco device offset
write64     0xFF3F0E4C <pdi_addr_lo>
mask_poll64 0xFF3F0E40 0xFFFFFFFF 0x00030701  # readback: message RAM really reachable
write64     0xFF3F03E0 0xDEADBEEF      # sentinel in the PMC -> IPI5 response buffer
write64     0xFF380000 0x00000002      # IPI5.TRIG, PMC bit
mask_poll64 0xFF380004 0x2 0x0         # IPI5.OBS: PLM acked
mask_poll64 0xFF3F03E0 0xFFFFFFFF 0x0  # response[0] == 0: sentinel replaced by success (optional)
```

`host/reflash_aie_pe.cpp` builds this stream, DMAs the partial PDI and the stream into DDR
with Tapasco, and launches the PE exactly like `sw/reconfig_main.cpp` did (same PE name,
same control word). The PE finishes only when the PLM has acknowledged; with the response
check it finishes only on PLM status 0. A PE that never returns means the PLM rejected the
PDI or the path is not there; reloading the full PDI is the recovery, as before.

About the PCIe question: Tapasco's VCK5000 platform does use the hard CPM PCIe block
(`CPM_PCIE0_FUNCTIONAL_MODE QDMA` in `versal_base.tcl`, `CPM_PCIE_NOC_0/1` into the NoC),
so the direct variant is real, but it needs a BAR and a NoC route that do not exist yet.
The PE path needs neither.

Side note from your testbench logs: the PL variant wrote the NPI registers at their native
address `0xF70A000C`, but through `NOC_PMC_AXI_0` the PMC region appears remapped at
`0x1_0000_0000 + (addr - 0xF000_0000)`, i.e. `0x1_070A_000C` (segment `psv_pmc_ram_npi`,
32 MB at `0x1_0600_0000`). Those writes may have been decode errors rather than a hard
permission wall. Not worth revisiting now that the PLM does them, but it changes the
story in the top-level README.
