# Versal CDO Command Reference & Hardware Scoping

Companion tool: `cdo_parser.py` in this directory. It parses both the binary
CDO form (`microarch/adf/sw/aie.cdo.*.bin`) and the text/assembler CDO form
(`gen_files/*.cdo`) into the same internal structure, re-emits either as
readable text, and includes a self-test that round-trips real reference
lines through a hand-built binary encoding of the documented format. All
counts and encodings below are **verified**: every one of the 1979 commands
across the six AIE binary files decoded with zero unknown opcodes and zero
length mismatches, and the file-level declared length matched the number of
words actually consumed in every case.

## 1. Wire format

### 1.1 File header (5 words, only present at the start of a standalone `.bin`)

| Word | Meaning | Notes |
|---|---|---|
| 0 | Format version | `0x4` in every sample seen |
| 1 | Magic | `0x004F4443` = ASCII `"CDO\0"` little-endian |
| 2 | Unconfirmed | `0x200` in every sample seen (constant) — never had to interpret this to parse correctly; treat as fixed preamble |
| 3 | Buffer length | Word count of everything that follows (the actual command stream). Matched exactly against consumed words in every file we tested. |
| 4 | Checksum | Differs per file, consistent with being a real checksum. Not validated by our parser. |

**Hardware implication**: if you concatenate the six per-stage files (or generate your own combined stream) yourself, this 5-word header is easiest to strip on the host/software side before handing the hardware a pure command stream — the hardware sequencer doesn't need to understand it at all, it only needs the loop in 1.2.

### 1.2 Per-command header (1 or 2 words)

```
 31        24 23      16 15        8 7         0
+-----------+-----------+-----------+-----------+
|  reserved | length(*) |  module   |  opcode   |   word 0
+-----------+-----------+-----------+-----------+
```

- `opcode`  = bits [0:7]  — selects the operation (table in §2)
- `module`  = bits [8:15] — always `1` ("Generic"/register-access module) for every command in the six AIE binaries. PMC's own bring-up CDOs use other module numbers for PM/board/error-management commands (see §4 of the old catalog, kept below) — irrelevant to an AIE-only replay engine.
- `length`  = bits [16:23] — payload word count, **unless it equals `0xFF` (255)**, which is an escape:
  - **Short form** (`length != 0xFF`): payload is exactly `length` words, starting at word 1.
  - **Long form** (`length == 0xFF`): the *next* word (word 1) is a full 32-bit payload length, and the real payload starts at word 2.
- bits [24:31]: never observed set in our samples; treat as reserved/unknown, not zero-checked by our parser.

Both forms are exercised in real data: `write64`/`mask_write64`/`mask_poll64`/`nop` always use the short form (payload ≤ 254 words), but 13 of the 40 `dma_write` commands use the long-form escape — their payloads range up to 2048 words (8KB). Verified directly against the parser's `long_form` flag, not just inferred from size.

### 1.3 Payload layouts by opcode

All multi-word addresses are big-half-first: `addr = (payload[0] << 32) | payload[1]`.

All rows verified against `Xilinx/embeddedsw`'s real PLM firmware source (`lib/sw_services/xilplmi/src/common/server/xplmi_generic.c`) — see §4 for citations.

| Opcode | Mnemonic | Payload words | Fields | Confidence |
|---|---|---|---|---|
| 1 | `mask_poll` | 4 | `addr, mask, expected, timeout_us` (32-bit addr) | **confirmed** (source: `XPlmi_MaskPoll`); never seen in binary AIE files, only inferred-then-verified from the opcode table |
| 2 | `mask_write` | 3 | `addr, mask, value` (32-bit addr) | **confirmed** — round-trips against real `ai_engine_data.cdo`/`pmc_data.cdo` lines; confirmed genuine read-modify-write via `XPlmi_UtilRMW()`, not an AXI-WSTRB write (§4) |
| 3 | `write` | 2 | `addr, value` (32-bit addr) | **confirmed** — round-trips |
| 4 | `delay` | 1 | `value` (confirmed unit: **microseconds**) | **confirmed**; **never appears in any AIE-relevant file**, 0 instances in all 6 binaries |
| 5 | `dma_write` | 2 + N | `addr_hi, addr_lo, data[0..N-1]` (64-bit addr, data **inline**, no external pointer) | **confirmed** mechanism and field layout (`XPlmi_DmaWrite`); mnemonic name is our own choice — bootgen's actual assembler keyword for this opcode wasn't found anywhere in the available source (bootgen itself is closed-source) |
| 6 | `mask_poll64` | 5 | `addr_hi, addr_lo, mask, expected, timeout_us` (64-bit addr) | **confirmed** — opcode number, mnemonic, and field order all verified (`XPlmi_MaskPoll64`/`XPlmi_GenericMaskPoll`); genuine software retry-loop poll, not a bus-level blocking read — see §4 |
| 7 | `mask_write64` | 4 | `addr_hi, addr_lo, mask, value` (64-bit addr) | **confirmed**; confirmed genuine read-modify-write via `XPlmi_UtilRMW()`, not AXI-WSTRB (§4) |
| 8 | `write64` | 3 | `addr_hi, addr_lo, value` (64-bit addr) | **confirmed** (`XPlmi_Write64`) |
| 17 (0x11) | `nop` | 0–2 (varies) | none (payload, if any, is all-zero words) | **confirmed** — source comment states verbatim: *"supported for alignment purposes"* (§4) |

## 2. Verified command inventory — the six AIE structural CDOs

Exact counts from `cdo_parser.py`, run against `microarch/adf/sw/aie.cdo.*.bin`. **Every command in every file decoded successfully — zero unknown opcodes, zero length mismatches, declared buffer length matched consumed length exactly, in all six files.**

| File | Total | `write64` | `mask_write64` | `mask_poll64` | `dma_write` | `nop` |
|---|---:|---:|---:|---:|---:|---:|
| `aie.cdo.reset.bin` | 394 | 232 | 150 | 12 | 0 | 0 |
| `aie.cdo.clock.gating.bin` | 19 | 0 | 19 | 0 | 0 | 0 |
| `aie.cdo.error.handling.bin` | 853 | 803 | 50 | 0 | 0 | 0 |
| `aie.cdo.init.bin` | 588 | 555 | 21 | 0 | 6 | 6 |
| `aie.cdo.elfs.bin` | 119 | 56 | 10 | 0 | 34 | 19 |
| `aie.cdo.enable.bin` | 6 | 0 | 6 | 0 | 0 | 0 |
| **Total** | **1979** | **1646** | **256** | **12** | **40** | **25** |

**This is the entire instruction set a hardware replay engine needs: 5 opcodes.** No procedural control flow, no PM/topology commands, no `delay`, no unresolved/unknown opcodes anywhere in 1979 real commands.

`dma_write` burst sizes observed: `[8, 9, 37, 43, 48, 63, 65, 105, 137, 1024, 2048]` words. The 1024/2048-word bursts (13 of 40 total, requiring the long-form header) are AIE data-memory zero-clears; the smaller bursts (37–137 words) carry real instruction/data content for program memory.

### `reset.bin` is the one file that leaves the AIE array's address window — and it matters

28 of `reset.bin`'s 394 commands (all `write64`/`mask_poll64`) target `0xf70a0000`/`0xf70a0004`/
`0xf70a000c`/`0xf70a0200` — outside `0x20000000000`, and **no other file among the six ever
does this** (verified exhaustively, not just spot-checked). These are not leftover PLL/clock
bring-up (that's a separate mechanism, done once at boot via the *text* `ai_engine_data.cdo`
image). Matched byte-for-byte against `Xilinx/embeddedsw`'s real PM firmware
(`lib/sw_services/xilpm/src/versal/server/xpm_regs.h`/`xpm_aie.c`):

- `0xf70a000c` = `NPI_PCSR_LOCK_OFFSET`; `0xf9e8d7c6` = `NPI_PCSR_UNLOCK_VAL` (standard Versal
  PCSR unlock magic).
- `0xf70a0000`/`0xf70a0004` = `NPI_PCSR_MASK_OFFSET`/`NPI_PCSR_CONTROL_OFFSET`; the value
  written, `0x08000000`, is exactly `ME_NPI_REG_PCSR_MASK_ME_SHIM_RESET_MASK`.

This is the exact sequence implemented by `Aie1_ShimRst(ColStart, ColEnd)`: unlock PCSR → assert
`SHIM_RESET` → deassert → relock, bracketing a per-column loop writing each column's own
`AIE_TILE_COL_SHIM_RST_OFFSET` register (`0x36040` — that's the bulk of the rest of `reset.bin`,
which *is* inside the AIE array window). **`Aie1_ShimRst` is called from
`Aie1_Operation(Part, Ops)`**, documented as dispatching *"reset, clock gating, zeroization,
error events, etc. on the specified partition of AIE1 columns"* — a general-purpose,
column-range-scoped reconfiguration entry point, not a boot-only function. Shim tiles carry real
hardware state (FIFOs, internal state machines) that a plain register overwrite can't clear; this
reset pulse is how a clean slate is guaranteed before applying new configuration to a partition.

**Implication: don't skip `reset.bin`.** The fact that it's the only file needing addresses
outside the array window is a sign it does something structurally different (a real reset pulse
via PCSR) that the other five files can't do themselves — not a sign it's dispensable. It's
plausibly the most load-bearing file for correctness across repeated swaps, not the least.
Practically, this does mean your hardware/loader needs *some* path to 3 PCSR registers
(`LOCK`/`MASK`/`CONTROL` at `0xf70a000c`/`0x0000`/`0x0004`) — a much narrower, more specific ask
than general NPI access, and worth pursuing either directly or via a PMC/PS-adjacent helper for
just this one step, while your NoC master handles everything else (the other ~98.6% of commands,
all within the array's own window).

## 3. Tooling: `cdo_parser.py`

```
python3 cdo_parser.py [file ...]
```

- With no arguments, just runs the self-test and prints usage.
- Detects binary vs. text automatically (ASCII-decodable first 64 bytes ⇒ text).
- Binary input → parsed via the header/opcode model in §1.
- Text input → line-based parser recognizing the mnemonics in §1.3 plus the PMC-only commands (`pm_add_node`, `log_string`, `proc`/`end`, etc. — captured as `unhandled_text:<name>` since we haven't numerically decoded those modules; they're out of scope for AIE reconfiguration, see the original catalog notes below).
- Every input produces a `<file>.decoded.cdo` next to it, in the same mnemonic-per-line style as the real Vivado-produced text CDOs — diff these by eye against `gen_files/*.cdo` to sanity-check formatting/style even though the actual addresses won't overlap (different subsystems, see prior session notes).
- **Self-test**: hand-encodes four real lines lifted verbatim from `gen_files/ai_engine_data.cdo` (`mask_write`, `write`, `mask_poll`) into synthetic binary words using only the rules in §1, decodes them back, and asserts the round trip is exact. This is the actual verification the task asked for — it proves the 32-bit opcode encodings are correct against ground truth, independent of the AIE-specific 64-bit opcodes (which have no text-form ground truth available, and are instead validated only by "parses the whole real file with zero errors" — see §2).

Run it against your own future `.bin` files the same way; a `[warn] declared buflen=... but consumed=...` message on stderr is your signal that either the format assumption broke or the file is corrupt/truncated.

## 4. Hardware implementation guide

A minimal microsequencer covers 100% of the observed command stream. Suggested state machine:

```
FETCH_HDR ──(len==0xFF)──▶ FETCH_LONGLEN ──▶ FETCH_PAYLOAD ──▶ DISPATCH
    ▲                                                              │
    └───────────────────────── (loop) ◀───────────────────────────┘
```

Per-opcode hardware requirements:

| Opcode | What the engine must do | Complexity |
|---|---|---|
| `write64` (84% of all commands) | Single AXI-MM write to `addr`, value = payload | trivial — this is nearly the whole workload |
| `mask_write64` (13%) | AXI-MM **read** `addr`, `(old & ~mask) \| value`, AXI-MM **write** back | needs a read channel, not just write-only — your NoC master must support AXI reads. **Confirmed cannot be shortcut via AXI `WSTRB`**: real PLM source (`XPlmi_UtilRMW`) does a literal read-modify-write, and independently every real mask value observed (`0x1, 0x2, 0x3, 0x4, 0x7f, 0x7f7f, 0x8080, 0xff80`) has sub-byte granularity, which `WSTRB` (byte-lane only) can't express anyway. |
| `dma_write` (2%) | Burst-write N inline words starting at `addr`; words come from the same instruction stream, sequentially, no scatter-gather, no separate source pointer to resolve | simple streaming copy; size an internal buffer/FIFO for up to 2048 words (8KB) if you don't want to interleave fetch-and-write per word, though word-at-a-time is also fine since there's no external addressing complexity |
| `mask_poll64` (0.6%) | Confirmed real: read `addr`, compare `(val & mask) == expected`, retry until `timeout_us` elapses | needs a read channel + a compare + a retry/timeout counter. Real PLM enforces a 1-second minimum timeout floor; your hardware doesn't have to match that, since every real instance we've seen (`mask=0`) resolves on the very first read regardless. |
| `nop` (1.3%) | Skip payload words, do nothing | trivial — could even be optimized away by a host-side pre-processor before handing the stream to hardware, since it provably never touches the target address space |

**Bottom line for scoping**: this is comparable in complexity to a basic register-init-sequence player (the kind already common for e.g. PHY/SerDes bring-up scripts) — one read port, one write port to your NoC master, a small opcode decoder, and a timeout counter for the poll case. It is not comparable to a general DMA engine or a CPU; there's no branching, no loops, no addressing modes beyond linear (base+offset already resolved at compile time into absolute 64-bit addresses).

### Both risk notes below are now RESOLVED against the real PLM firmware source

Fetched `Xilinx/embeddedsw` (the public, official PLM firmware source) and read
`lib/sw_services/xilplmi/src/common/server/xplmi_generic.c` directly — this is the actual code
that executes every command in table §1.3. Both open questions from the previous pass are
settled:

**`mask_write`/`mask_write64` is confirmed to be a genuine read-modify-write, not an AXI-WSTRB
write.** `XPlmi_MaskWrite()` (line 558) and `XPlmi_MaskWrite64()` (line 789) both call
`XPlmi_UtilRMW(Addr, Mask, Value)` — a function literally named "RMW". This matches what the
data already told us independently: every real mask value in the six AIE binaries
(`0x1, 0x2, 0x3, 0x4, 0x7f, 0x7f7f, 0x8080, 0xff80`) has sub-byte granularity, which `WSTRB`
(byte-lane only) cannot express — now confirmed from both directions. **Hardware needs a real
AXI read port for this opcode.**

**`mask_poll64` is a real, confirmed opcode with a real, confirmed field layout, and it is a
genuine software retry-loop poll — not a bus-level blocking read.** The `XPlmi_GenericCmds[]`
command table (line 2436) lists handlers in array order, and array position *is* the opcode
number: `0=Features, 1=MaskPoll, 2=MaskWrite, 3=Write, 4=Delay, 5=DmaWrite, 6=MaskPoll64,
7=MaskWrite64, 8=Write64, ..., 17=Nop` — every opcode number in §1.3 matches exactly, including
the ones (1 and 6) that had zero backing before. `XPlmi_MaskPoll64()` (line 761) computes
`Addr = (Payload[0]<<32) | Payload[1]` and calls
`XPlmi_GenericMaskPoll(Cmd, Addr, XPLMI_MASK_POLL_64BIT_TYPE)`, which extracts
`Mask=Payload[2], ExpectedValue=Payload[3], TimeOutInUs=Payload[4]` and calls
`XPlmi_UtilPoll64(Addr, Mask, ExpectedValue, TimeOutInUs)` — a real, retrying poll loop, exactly
the field order we'd guessed. The reader-suggested "just block on the read" hypothesis does not
hold: there is real software-level compare-and-retry logic here, unconditionally.

Two bonus findings from the same read:
- PLM clamps the requested timeout up to a **minimum of 1,000,000 microseconds (1 second)** via
  `XPLMI_MASK_POLL_MIN_TIMEOUT`, unless an optional 6th "flags" payload word (absent in all 12 of
  our real instances) explicitly disables that. So even though the compiled CDO literally says
  `timeout=1` (1 microsecond), real PLM firmware would actually wait up to 1 second before giving
  up — it just never needs to, because...
- ...all 12 real instances have `mask=0`, and `(RegVal & 0) == 0` is trivially always true —
  these specific polls pass immediately on the first read, confirming our original degenerate-
  but-real-mechanism explanation. **The opcode and mechanism are both real; these particular 12
  instances just happen to be no-ops in practice.**
- `nop`'s source comment (line 308) reads verbatim: *"This function provides no operation. The
  command is supported for alignment purposes."* — confirms it's padding, not a wait, exactly as
  inferred.
- `delay`'s unit is confirmed as microseconds directly from its docstring.

Hardware implication, updated: a `mask_poll64` engine should implement the real thing (read,
compare `(val & mask) == expected`, retry with a timeout counter) since the mechanism is now
confirmed real and reusable — but you can safely floor your own timeout implementation at
whatever's practical for your design rather than matching PLM's 1-second minimum, since every
real instance we've seen resolves on the very first read regardless.

## 5. Everything else (PMC-only commands, unchanged from the first pass)

These are **not** needed for an AIE-array replay engine — they only appear in `pmc_data.cdo` and sibling per-domain bring-up files, never in the six AIE binaries. Kept here for completeness / in case the scope ever grows to include full-chip reconfiguration.

| Command | Purpose | Confidence |
|---|---|---|
| `pm_init_node` | EEMI-style firmware call: bring up one power/clock domain through its init sequence (init_start/scan_clear/bisr/mem_init/mbist_clear/init_finish) | confirmed as a **firmware call**, not a register write — genuinely not replicable by a plain AXI-MM master |
| `pm_add_node` / `pm_add_node_parent` / `pm_add_node_name` | Register PLM's whole-chip PM topology graph (611+177+115 occurrences in `pmc_data.cdo` — this is the entire chip's power/clock/reset dependency graph) | inferred |
| `pm_describe_nodes` | Bulk/compact node description | uncertain, single large-payload occurrence, not inspected in detail |
| `pm_add_subsystem` | Defines a PM "subsystem" (named node group + access permissions) — possibly where NoC/NPI master access grants are actually authorized | uncertain, worth a closer look if you ever need to grant a *new* master access to the AIE window programmatically rather than via TaPaSCo's build-time Vivado properties |
| `pm_force_hc`, `pm_clock_set_rate` | House-cleaning/health-check (guessed) and clock-rate setting | uncertain / inferred |
| `set_board`, `ot_check`, `em_set_action`, `log_string`, `cframe_clear_check` | Board id, over-temp check, error-management action registration, boot-log string, PL config-frame clear/check | inferred, all PMC-boot diagnostics |
| `marker` | Debug/traceability section tag, no hardware effect | confirmed |
| `proc ... end`, `begin ... end`, `break` | Procedural block scaffolding, used exactly once in `pmc_data.cdo` (near the error-management commands) | uncertain, not disambiguated (two different `end` uses) |
| `delay` | Fixed-duration wait, distinct from `nop` | inferred — real command, 2 total occurrences chip-wide, **zero in any AIE-relevant file** |

## 6. Resolved / open items

Resolved this pass:
- ~~Full byte-accurate parse of all six binaries~~ — done, §2.
- ~~Confirm header format~~ — done, §1, validated by exact buflen match on every file.
- ~~Verify 32-bit `write`/`mask_write`/`mask_poll` field order~~ — done via self-test round-trip against real text lines.

Resolved this pass (round 3 — cross-checked against real Xilinx PLM firmware source, `Xilinx/embeddedsw` cloned locally, `lib/sw_services/xilplmi/src/common/server/xplmi_generic.c`):
- ~~Is `mask_write`/`mask_write64` actually just an AXI-`WSTRB` write?~~ — no, confirmed twice over: from real mask data (sub-byte granularity) and now from source (`XPlmi_UtilRMW` — a literal read-modify-write function).
- ~~`mask_poll64`'s opcode identity and field layout~~ — fully confirmed: opcode 6, mnemonic `MaskPoll64`, fields `addr_hi, addr_lo, mask, expected, timeout_us` exactly as guessed, real software retry-loop (`XPlmi_UtilPoll64`), not a bus-level blocking read.
- ~~`nop`'s purpose~~ — confirmed verbatim from source comment: "supported for alignment purposes."
- ~~`delay`'s unit~~ — confirmed: microseconds.
- Bonus, not previously tracked as an open item: PLM enforces a 1-second minimum timeout floor on all mask-poll commands (`XPLMI_MASK_POLL_MIN_TIMEOUT`) unless explicitly disabled via an optional flags word — irrelevant to our real instances (all resolve instantly via `mask=0`) but worth knowing if a future recompile ever emits a non-degenerate poll.
- All opcode numbers 0–17 in the PLM's `XPlmi_GenericCmds[]` table were checked against our full inferred set (1,2,3,4,5,6,7,8,17) and matched exactly, with no exceptions.

Still open (much smaller list now):
1. `dma_write`'s real text/assembler mnemonic is still unknown — bootgen itself (which compiles the text `.cdo` assembler format into binary) is closed-source and its keyword table isn't in `embeddedsw`. Field layout and opcode number (5) are fully confirmed from `XPlmi_DmaWrite`; only the cosmetic text keyword is a guess.
2. `pm_add_subsystem` — worth decoding if you ever need to grant a new master NoC access programmatically instead of via Vivado build-time properties. (Now that we have full `embeddedsw` cloned locally, this would be a `xilpm`/PM-module lookup rather than the generic module — same repo, different subsystem, not yet pulled.)
