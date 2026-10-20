# Background: why the PMC does the reflash, and what did not work

## The PL cannot reconfigure the AIE on its own

The first attempt (git history up to commit `356c866`, PE `AIEngineReflasher`) was a PL core
with an AXI4 "bulk" master for DMA into the AIE array and an AXI4-Lite master for single
register accesses, interpreting the CDO command stream of an AIE image itself. Tapasco maps
DDR at `0x100_0000_0000` and the AIE array at `0x200_0000_0000`, and the CDO files produced by
`aiecompiler` (`aie.cdo.reset/clock.gating/error.handling/elfs/init/enable.bin`) write
exactly that range, so most of the job worked.

A few commands in the reset CDO do not target the array but the AIE NPI block at
`0xF70A0000`:

```
write64 0xf70a000c 0xf9e8d7c6      # NPI unlock
mask_poll64 0xf70a000c 0x0 0x0 0x1
write64 0xf70a0200 0x1             # array reset
mask_poll64 0xf70a0200 0x0 0x0 0x1
write64 0xf70a000c 0x0
```

Those registers live in the PMC's address space and are only reachable through the
`NOC_PMC_AXI_0` port of the CIPS. Through that port the PMC region appears remapped at
`0x1_0000_0000 + (addr - 0xF000_0000)` (segment `psv_pmc_ram_npi`), which the PL variant did
not use, so its NPI writes were decode errors rather than a hard permission wall. We did not
pursue that further: the AIE reset sequence, clock gating and ELF loading are undocumented
PLM behaviour, and re-implementing them in PL is fragile. Screenshots of that design are in `img/`: the synthesized block design
([synthesized_design_labels.png](../img/synthesized_design_labels.png)), the NoC wiring that
gave the PL a path to the PMC ([pl_gets_to_talk_to_pmc.png](../img/pl_gets_to_talk_to_pmc.png),
[noc_pmc_output.png](../img/noc_pmc_output.png)), the CIPS address space as seen from the PL
([cips_address_space.png](../img/cips_address_space.png)) and the two AIE designs
([two_aie_designs.png](../img/two_aie_designs.png)).

## The PLM already does it

The Platform Loader and Manager (PLM, firmware on the PMC in every Versal PDI) contains the
CDO interpreter, the AIE ELF loader and the NPI access rights. At boot it loaded the AIE
image Tapasco's `ai_engine.tcl` plugin appended to the PDI. XilLoader exposes the same path
at runtime through the IPI command `LOAD_SUBSYSTEM_PDI` (`XPLMI_ALL_IPI_FULL_ACCESS`,
non-secure requests allowed, stable since 2020.x). This is also how XRT reconfigures the AIE
on the stock VCK5000 shell: the VMR firmware on the R5 hands the partial PDI from the xclbin
to the PLM over IPI (`Xilinx/VMR vmr/src/rmgmt/rmgmt_xfer.c` -> xilfpga -> XMailbox ->
`{0x030701, 0xF, addr_hi, addr_lo}` -> `XLoader_LoadSubsystemPdi`). We keep only that one
IPI call.

The partial PDI must be a bootgen image (`tools/make_aie_pdi.sh`): the loader parses the PDI
headers first and compares the IDCODE in the image header table exactly against the silicon
(`XLoader_IdCodeCheck`). bootgen's default `0x04ca8093`/0 does not match the production
VCK5000 (`0x14ca8093`/1) and the load is rejected. The PMC DMA reads the PDI from DDR over
the PMC NoC port, which Tapasco already connects.

## Who sends the IPI

Three senders were considered. Only the last one is kept in the tree; the other two are in
the git history (commits up to `8085ffb`, directory `pmc_reflasher/`).

1. **Bare-metal firmware on A72 #0**, polling a mailbox in DDR, sending the IPI with the
   `xipipsu` driver. Needs an ELF embedded in the PDI or loaded over JTAG, a BSP from the
   XSA, and an MMU entry for DDR_LOW3. Never brought up.
2. **The x86 host writes the IPI registers through a PCIe BAR.** Needs a new BAR and a NoC
   route from the CPM to the PMC slave. Never built.
3. **A PL processing element** does the handshake. Nothing on the card beyond the PE, and
   the reflash is an ordinary Tapasco job. This is `AIEPdiLoader`.

## Reaching the IPI block from the PL

The IPI channel registers (`0xFF330000 + n * 0x10000`) are visible on the NoC path, but the
message RAM (`psv_ipi_buffer`, `0xFF3F0000`, 4 KiB) is only exposed by Vivado's CIPS model on
the direct PL-to-PS slave ports (`S_AXI_LPD`, `S_AXI_GP2`), never on `NOC_PMC_AXI_0`. AMD's
own `vck190_axi_cci_bd.tcl` shows the same. A NoC output toward the PMC would also get a 1 GB
PL_LO aperture that cannot intersect the fixed LPD addresses (BD 41-1743). So the plugin
enables `S_AXI_LPD` and connects the PE's master straight to it. Tapasco's own address map
construction cannot place the ~100 fixed-address LPD segments; connecting the port in the
post-platform hook and calling `assign_bd_address` afterwards lets Vivado do it.

The Slave Boot Interface was the other candidate, but the 2023.1 PLM only arms the SBI
data-ready interrupt after an SBI load or a PLM update, so a PL master would also have to
poke the PMC GIC enables.

## Versal IPI reference (2023.1 `xipipsu`, `xplmi_ipi.c`)

| Thing | Value |
|---|---|
| Channel register blocks | PMC `0xFF320000`, IPI0 `0xFF330000` ... IPI5 `0xFF380000` (TRIG +0x0, OBS +0x4, ISR +0x10, IMR +0x14) |
| Channel bit masks | PSM `0x1`, PMC `0x2`, IPI0 `0x4` ... IPI5 `0x80`, PMC_NOBUF `0x100`, IPI6 `0x200` |
| Buffer index | PMC 1, IPIn 2 + n (IPI6 and PMC_NOBUF have no buffer) |
| Message RAM | `0xFF3F0000 + src_index * 0x200 + dst_index * 0x40`, response at +0x20 inside the requester's slot |
| Request IPIn -> PMC | `0xFF3F0000 + (2 + n) * 0x200 + 0x40` (IPI5: `0xFF3F0E40`) |
| Response PMC -> IPIn | request + 0x20 (IPI5: `0xFF3F0E60`) |
| Command words | `{0x030701, 0xF, addr_hi, addr_lo}`; `addr = 0x100_0000_0000 + Tapasco device offset` |
| Handshake | write 4 words, write `0x2` to TRIG, poll OBS bit `0x2` until clear, read response[0] (PLMI status) and [1] (XilLoader status) |

Two PLM details that cost a day each:

- **The PLM only scans as many ISR bits as there are IPI instances in the design.** The
  per-design 2023.1 PLM sets `XPAR_XIPIPSU_NUM_TARGETS` from the CIPS configuration and its
  GIC task loops over ISR bit indices `0 .. NUM_TARGETS - 1`. With only IPI5 enabled that is
  bits 0..3, IPI5 is bit 7, and the request is masked and dropped without a log line (xsdb's
  own `plm` commands, which also use IPI5, time out the same way). Enable IPI0..IPI6.
- **The response is written into the requester's own slot.** `xipipsu_buf.c` computes the
  response address as `dest * 0x200 + src * 0x40 + 0x20` with src = PMC, dest = requester.
  Reading `0xFF3F0000 + 0x200 + (2 + n) * 0x40 + 0x20` instead returns whatever sentinel
  you planted there.

IPI5 is the channel xsdb uses (`XPLMI_IPI_XSDB_MASTER_MASK`): the PLM skips the subsystem
lookup for it, and a JTAG session races the PE for the same buffer. IPI0..IPI4 are unused
in a Tapasco design (no A72 or R5 software) and IPI2 was verified to work, so it is the
host default.

## Getting at the card for debugging

The VCK5000 PS has no network interface. The paths in are the PCIe link and the bracket
micro-USB (FT4232H: JTAG plus UART). With `hw_server` running, `xsdb` can read the IPI
registers, show the PLM log (`plm log` on the DPC target) and set its log level. Loading a
full PDI over JTAG drops the PCIe link; unbind the device first. The PLM's UART is on
`PMC_MIO 16..17` on the AIR reference platform; which pins Tapasco routes is unverified.
