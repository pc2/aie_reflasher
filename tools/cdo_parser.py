#!/usr/bin/env python3
"""
Versal CDO (Configuration Data Object) parser / text emitter.

Parses BOTH forms of CDO we've found in the TaPaSCo VCK5000 build output:

  1. Binary CDO  (e.g. microarch/adf/sw/aie.cdo.*.bin) — raw little-endian
     32-bit word streams, aiecompiler-generated.
  2. Text CDO    (e.g. gen_files/*.cdo)                — bootgen's human
     readable assembler source, Vivado-generated.

Both are parsed into the same internal `CdoCommand` structure so they can be
cross-checked against each other, and the binary form can be re-emitted as
text in the same style as the real Vivado-produced .cdo files for by-eye
diffing.

Encoding details, confidence levels, and open questions are tracked in
CDO_COMMANDS.md next to this file -- read that first if a field's meaning
looks surprising.

USAGE
    python3 cdo_parser.py <file.bin|file.cdo> [...]

    For each input, writes a decoded text-cdo next to it plus prints an
    opcode-count summary. Also runs a self-test (round trip against real
    hand-picked lines from ai_engine_data.cdo) before doing any real work,
    and aborts loudly if that self-test fails.
"""
import struct
import sys
from pathlib import Path
from typing import Callable, Dict, List, Optional, Set, Tuple

# Kept compatible with Python 3.6 (the system python on the pc2 FPGA nodes): no dataclasses,
# no `from __future__ import annotations`, typing generics instead of the builtin list[...] forms.

# ---------------------------------------------------------------------------
# Internal command representation
# ---------------------------------------------------------------------------


class CdoCommand:
    def __init__(self, module: int, opcode: int, mnemonic: str, args: dict, raw_payload: tuple,
                 long_form: bool, source: str = "binary", word_offset: int = -1):
        self.module = module              # header bits [8:15]
        self.opcode = opcode              # header bits [0:7]
        self.mnemonic = mnemonic          # resolved name, or "unknown_M<m>_OP<op>"
        self.args = args                  # decoded, named fields (opcode-specific)
        self.raw_payload = raw_payload    # raw payload words, always kept for fallback/debug
        self.long_form = long_form        # True if the 0xFF escape (32-bit length word) was used
        self.source = source              # "binary" or "text", for provenance when cross-checking
        self.word_offset = word_offset    # word index of the header word in its source stream (-1 if n/a)

    def __eq__(self, other):
        return isinstance(other, CdoCommand) and self.__dict__ == other.__dict__

    def __repr__(self):
        return f"CdoCommand({self.__dict__!r})"

    def text(self) -> str:
        """Render in the same style as the real bootgen .cdo text files."""
        if self.mnemonic.startswith("unknown_"):
            words = " ".join(f"0x{w:08x}" for w in self.raw_payload)
            return f"# {self.mnemonic} (module={self.module} opcode={self.opcode}) payload=[{words}]"
        if self.mnemonic.startswith("unhandled_text:"):
            real_mnemonic = self.mnemonic[len("unhandled_text:"):]
            return f"# unhandled (not numerically decoded, see CDO_COMMANDS.md): {self.args.get('raw_line', real_mnemonic)}"
        argstr = " ".join(_fmt_arg(v) for v in self.args.values())
        return f"{self.mnemonic} {argstr}".rstrip()


def _fmt_word(w) -> str:
    return f"0x{w:08x}" if isinstance(w, int) else str(w)


def _fmt_arg(v) -> str:
    if isinstance(v, (tuple, list)):
        n = len(v)
        if n <= 8:
            return f"[{n}: {' '.join(_fmt_word(w) for w in v)}]"
        head = " ".join(_fmt_word(w) for w in v[:3])
        tail = " ".join(_fmt_word(w) for w in v[-2:])
        return f"[{n}: {head} ... {tail}]"
    if isinstance(v, str):
        return v
    return f"0x{v:x}"


# ---------------------------------------------------------------------------
# Opcode table -- module 1 ("Generic") register/memory access primitives.
#
# This is the ONLY module we've observed in the aiecompiler-produced binary
# CDOs. PMC's own bring-up CDOs (pmc_data.cdo etc.) use other modules
# (PM/XilPM, board, error-management -- see CDO_COMMANDS.md section B/C) but
# those are out of scope for an AIE-array replay engine and are not decoded
# here beyond being captured as "unknown".
#
# Each entry: opcode -> (mnemonic, arg_names, decode_fn, confidence_note)
#
# decode_fn(payload: Tuple[int,...]) -> dict   maps raw payload words to named args.
# ---------------------------------------------------------------------------

CONFIDENCE_CONFIRMED = "confirmed"
CONFIDENCE_INFERRED = "inferred"
CONFIDENCE_UNCERTAIN = "uncertain"


def _decode_mask_poll(p):
    return {"addr": p[0], "mask": p[1], "expected": p[2], "timeout": p[3]}


def _decode_mask_write(p):
    return {"addr": p[0], "mask": p[1], "value": p[2]}


def _decode_write(p):
    return {"addr": p[0], "value": p[1]}


def _decode_delay(p):
    return {"value": p[0]} if p else {}


def _decode_dma_write(p):
    addr = (p[0] << 32) | p[1]
    return {"addr": addr, "data": p[2:]}


def _decode_mask_poll64(p):
    addr = (p[0] << 32) | p[1]
    # CONFIRMED against Xilinx/embeddedsw lib/sw_services/xilplmi/src/common/
    # server/xplmi_generic.c (XPlmi_MaskPoll64, XPlmi_GenericMaskPoll): opcode
    # 6, module 1 ("Generic"), field order addr_hi, addr_lo, mask, expected,
    # timeout_us -- exactly this layout. It IS a genuine software retry-loop
    # poll (calls XPlmi_UtilPoll64(Addr, Mask, ExpectedValue, TimeOutInUs)),
    # not a bus-level "block until RVALID" mechanism. PLM additionally clamps
    # TimeOutInUs up to a minimum of 1,000,000us (1s) via
    # XPLMI_MASK_POLL_MIN_TIMEOUT unless an optional 6th "flags" word
    # (not present in any of our 12 real instances) disables that. All 12
    # real instances have mask=0 -- (val & 0) == 0 is trivially always true,
    # so these specific instances pass immediately regardless of the
    # requested/clamped timeout; the opcode and field layout are still real.
    return {"addr": addr, "mask": p[2], "expected": p[3], "timeout": p[4]}


def _decode_mask_write64(p):
    addr = (p[0] << 32) | p[1]
    return {"addr": addr, "mask": p[2], "value": p[3]}


def _decode_write64(p):
    addr = (p[0] << 32) | p[1]
    return {"addr": addr, "value": p[2]}


def _decode_nop(p):
    return {"padding": p} if p else {}


# Every opcode/mnemonic/field-layout below is now verified against the real
# PLM firmware source: Xilinx/embeddedsw, lib/sw_services/xilplmi/src/common/
# server/xplmi_generic.c -- specifically the XPlmi_GenericCmds[] table (array
# position == opcode number, confirmed 0=Features, 1=MaskPoll, 2=MaskWrite,
# 3=Write, 4=Delay, 5=DmaWrite, 6=MaskPoll64, 7=MaskWrite64, 8=Write64,
# 9=DmaXfer, ..., 17=Nop) and each handler function's own payload indexing.
# mask_write/mask_write64 call XPlmi_UtilRMW() -- a literal read-modify-write,
# not an AXI-WSTRB byte-strobe write (also independently confirmed from real
# mask data, see CDO_COMMANDS.md). nop's source comment literally says
# "supported for alignment purposes" -- confirms it's padding, not a wait.
OPCODES = {
    # opcode: (mnemonic, decode_fn, fixed_payload_len_or_None, confidence)
    1: ("mask_poll", _decode_mask_poll, 4, CONFIDENCE_CONFIRMED),
    2: ("mask_write", _decode_mask_write, 3, CONFIDENCE_CONFIRMED),
    3: ("write", _decode_write, 2, CONFIDENCE_CONFIRMED),
    4: ("delay", _decode_delay, None, CONFIDENCE_CONFIRMED),  # unit confirmed: microseconds
    5: ("dma_write", _decode_dma_write, None, CONFIDENCE_CONFIRMED),  # variable length: 2 + N data words
    6: ("mask_poll64", _decode_mask_poll64, 5, CONFIDENCE_CONFIRMED),
    7: ("mask_write64", _decode_mask_write64, 4, CONFIDENCE_CONFIRMED),
    8: ("write64", _decode_write64, 3, CONFIDENCE_CONFIRMED),
    17: ("nop", _decode_nop, None, CONFIDENCE_CONFIRMED),  # confirmed: alignment padding, payload (if any) is ignored
}

# Text-CDO mnemonic -> opcode, for the text parser (keeps both parsers
# talking about the same opcode numbers/decode functions above).
MNEMONIC_TO_OPCODE = {mnem: op for op, (mnem, *_r) in OPCODES.items()}


# ---------------------------------------------------------------------------
# Binary parser
# ---------------------------------------------------------------------------

CDO_MAGIC = 0x004F4443  # "CDO\0", little-endian word


def _words_from_bytes(data: bytes) -> tuple:
    n = len(data) // 4
    if n * 4 != len(data):
        raise ValueError(f"file length {len(data)} is not a multiple of 4 bytes")
    return struct.unpack("<%dI" % n, data[: n * 4])


def parse_binary_cdo(data: bytes) -> List[CdoCommand]:
    words = _words_from_bytes(data)
    commands: List[CdoCommand] = []

    i = 0
    header_info = {}
    if len(words) >= 5 and words[1] == CDO_MAGIC:
        header_info = {
            "version": words[0],
            "magic": words[1],
            "field2_unconfirmed": words[2],
            "buflen": words[3],
            "checksum": words[4],
        }
        i = 5

    total_len = header_info.get("buflen")
    consumed = 0
    while i < len(words):
        hdr = words[i]
        opcode = hdr & 0xFF
        module = (hdr >> 8) & 0xFF
        paylen = (hdr >> 16) & 0xFF
        i += 1
        consumed += 1
        long_form = paylen == 0xFF
        if long_form:
            paylen = words[i]
            i += 1
            consumed += 1
        payload = words[i : i + paylen]
        if len(payload) != paylen:
            raise ValueError(
                f"truncated command at word {i - (2 if long_form else 1)}: "
                f"expected {paylen} payload words, only {len(payload)} remain"
            )
        i += paylen
        consumed += paylen

        entry = OPCODES.get(opcode)
        if entry is not None:
            mnemonic, decode_fn, fixed_len, _conf = entry
            if fixed_len is not None and len(payload) != fixed_len:
                # Length mismatch against our assumed fixed layout -- don't
                # guess, keep it as a flagged-unknown so nothing is silently
                # misdecoded.
                mnemonic_out = f"unknown_M{module}_OP{opcode}_lenmismatch"
                args = {}
            else:
                mnemonic_out = mnemonic
                args = decode_fn(payload)
        else:
            mnemonic_out = f"unknown_M{module}_OP{opcode}"
            args = {}

        commands.append(
            CdoCommand(
                module=module,
                opcode=opcode,
                mnemonic=mnemonic_out,
                args=args,
                raw_payload=tuple(payload),
                long_form=long_form,
                source="binary",
                word_offset=i - consumed_this_cmd_len(long_form, paylen),
            )
        )

    if total_len is not None and consumed != total_len:
        print(
            f"  [warn] declared buflen={total_len} words but consumed={consumed} "
            f"words of command data (header_info={header_info})",
            file=sys.stderr,
        )

    return commands


def consumed_this_cmd_len(long_form: bool, paylen: int) -> int:
    return (2 if long_form else 1) + paylen


# ---------------------------------------------------------------------------
# Text parser (for gen_files/*.cdo -- bootgen's readable CDO source format)
# ---------------------------------------------------------------------------

_TEXT_IGNORE_PREFIXES = (
    "#", "version", "marker", "Xilinx", "Created", "Design", "Architecture",
    "Part:", "Date:", "Bits:",
)


def parse_text_cdo(text: str) -> List[CdoCommand]:
    commands: List[CdoCommand] = []
    for lineno, raw_line in enumerate(text.splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith(_TEXT_IGNORE_PREFIXES):
            continue
        parts = line.split()
        mnemonic = parts[0]
        opcode = MNEMONIC_TO_OPCODE.get(mnemonic)
        if opcode is None:
            # pm_*, set_board, ot_check, em_set_action, log_string, proc/end/
            # begin/break, cframe_clear_check, etc: real commands, just not
            # decoded numerically yet (see CDO_COMMANDS.md section B/C/D).
            commands.append(
                CdoCommand(
                    module=-1,
                    opcode=-1,
                    mnemonic=f"unhandled_text:{mnemonic}",
                    args={"raw_line": line},
                    raw_payload=(),
                    long_form=False,
                    source="text",
                )
            )
            continue
        try:
            values = [int(t, 0) for t in parts[1:]]
        except ValueError:
            values = parts[1:]  # non-numeric args (e.g. quoted strings) kept as-is
        _mnem, decode_fn, _fixed_len, _conf = OPCODES[opcode]
        args = decode_fn(tuple(values)) if values and all(isinstance(v, int) for v in values) else {"raw_args": values}
        commands.append(
            CdoCommand(
                module=1,
                opcode=opcode,
                mnemonic=mnemonic,
                args=args,
                raw_payload=tuple(values) if values and all(isinstance(v, int) for v in values) else (),
                long_form=False,
                source="text",
            )
        )
    return commands


# ---------------------------------------------------------------------------
# Text emitter
# ---------------------------------------------------------------------------


def emit_text_cdo(commands: List[CdoCommand]) -> str:
    lines = [cmd.text() for cmd in commands]
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Self-test: round-trip real lines lifted verbatim from
# gen_files/ai_engine_data.cdo against hand-built binary encodings, using
# ONLY the encoding rules documented in CDO_COMMANDS.md. If this fails, the
# encoding model is wrong -- fix it before trusting any .bin decode below.
# ---------------------------------------------------------------------------

# (mnemonic, args-as-ints) pulled directly from gen_files/ai_engine_data.cdo
REFERENCE_TEXT_LINES = [
    "mask_write 0xf70a0104 0xfe7fedef 0x7e5dcc6c",
    "mask_write 0xf70a0100 0x73ff00 0x14800",
    "write 0xf1130000 0x20000",
    "mask_poll 0xf70a010c 0x1 0x1 0x1000",
]


def _encode_short_form(module: int, opcode: int, payload: List[int]) -> List[int]:
    assert len(payload) < 0xFF, "self-test only needs short-form commands"
    hdr = (opcode & 0xFF) | ((module & 0xFF) << 8) | ((len(payload) & 0xFF) << 16)
    return [hdr] + payload


def self_test() -> None:
    text_cmds = parse_text_cdo("\n".join(REFERENCE_TEXT_LINES))
    assert len(text_cmds) == len(REFERENCE_TEXT_LINES), "text parser dropped a line"

    words: List[int] = []
    for cmd in text_cmds:
        words.extend(_encode_short_form(1, cmd.opcode, list(cmd.raw_payload)))

    data = struct.pack("<%dI" % len(words), *words)
    binary_cmds = parse_binary_cdo(data)  # no 5-word file header on this synthetic blob

    assert len(binary_cmds) == len(text_cmds), (
        f"round trip produced {len(binary_cmds)} commands, expected {len(text_cmds)}"
    )
    for i, (t, b) in enumerate(zip(text_cmds, binary_cmds)):
        assert t.mnemonic == b.mnemonic, f"line {i}: mnemonic mismatch {t.mnemonic} != {b.mnemonic}"
        assert t.args == b.args, f"line {i}: args mismatch {t.args} != {b.args}"
    print(f"[self-test] OK -- {len(text_cmds)} reference lines round-tripped through the binary encoder/decoder")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def looks_like_text(data: bytes) -> bool:
    sample = data[:64]
    try:
        sample.decode("ascii")
    except UnicodeDecodeError:
        return False
    return True


def process_file(path: Path) -> None:
    data = path.read_bytes()
    if looks_like_text(data):
        commands = parse_text_cdo(data.decode("ascii", errors="replace"))
        kind = "text"
    else:
        commands = parse_binary_cdo(data)
        kind = "binary"

    out_path = path.with_suffix(path.suffix + ".decoded.cdo")
    out_path.write_text(emit_text_cdo(commands))

    counts: Dict[str, int] = {}
    num_landing_in_0x200 = 0
    num_landing_in_0xf70 = 0
    num_landing_elsewhere = 0
    for c in commands:
        counts[c.mnemonic.split("_lenmismatch")[0]] = counts.get(c.mnemonic.split("_lenmismatch")[0], 0) + 1
        addr = c.args.get("addr")
        if addr:
            if addr >= 0x20000000000:
                num_landing_in_0x200 += 1
            elif 0xf7000000 <= addr:
                num_landing_in_0xf70 += 1
            else:
                num_landing_elsewhere += 1

            
    print(f"{path.name} [{kind}]: {len(commands)} commands -> {out_path.name}")
    print(f"  {num_landing_in_0x200} land in 0x20000000000, {num_landing_in_0xf70} land in 0xf7000000, {num_landing_elsewhere} land elsewhere")
    for mnem, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"    {mnem:30s} {n}")
    
    return commands


def main(argv: List[str]) -> int:
    self_test()
    if not argv:
        print(__doc__)
        return 0
    for arg in argv:
        process_file(Path(arg))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
