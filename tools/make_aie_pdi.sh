#!/usr/bin/env bash
# Build an AIE-only partial PDI that the PLM can load at runtime.
#
#   make_aie_pdi.sh <libadf.a | dir with aie.cdo.*.bin> <out.pdi> --like <reference.pdi>
#   make_aie_pdi.sh <src> <out.pdi> --id-code 0x14ca8093 --ext-id-code 0x1
#
# id_code / extended_id_code MUST match the device: the PLM compares the IHT IDCODE
# exactly against PMC_TAP_IDCODE (XLoader_IdCodeCheck) and rejects the PDI otherwise.
# Without them bootgen stamps the generic 0x04ca8093 (silicon rev 0, ext id 0); the
# VCK5000 production part reports 0x14ca8093 / 1. --like reads both from any PDI that
# already runs on the card (e.g. the Tapasco full PDI).
#
# The image is the same "aie_image" (id 0x1c000000, type=cdo) that Tapasco's
# ai_engine.tcl plugin appends to the boot PDI, just without the bootimage
# part, so it is a partial PDI. Order of the CDOs matches Tapasco's plugin.
set -euo pipefail

src=$(realpath "${1:?source (libadf.a or dir)}")
out=$(realpath -m "${2:?output pdi}")
shift 2
idcode=""; extid=""; ref=""
while [ $# -gt 0 ]; do
    case "$1" in
        --like) ref=$(realpath "$2"); shift 2;;
        --id-code) idcode=$2; shift 2;;
        --ext-id-code) extid=$2; shift 2;;
        *) echo "unknown option $1" >&2; exit 2;;
    esac
done
if [ -n "$ref" ]; then
    # IHT: full PDI -> offset at boot header 0xC4; partial -> 0x10 after SMAP preamble; Idcode at +0x18, ExtIdCode at +0x44
    read -r idcode extid < <(python3 -I - "$ref" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
u = lambda o: struct.unpack_from('<I', d, o)[0]
iht = u(0xC4) if u(0x14) == 0x584C4E58 else (0x10 if u(0) == 0xDD else 0)
print(f"0x{u(iht+0x18):08x} 0x{u(iht+0x44):x}")
PY
)
fi
if [ -z "$idcode" ] || [ -z "$extid" ]; then
    echo "need --like <reference.pdi> or --id-code/--ext-id-code (PLM rejects a wrong IDCODE)" >&2; exit 2
fi
echo "id_code=$idcode extended_id_code=$extid"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

bins=(aie.cdo.reset.bin aie.cdo.clock.gating.bin aie.cdo.error.handling.bin aie.cdo.elfs.bin aie.cdo.init.bin aie.cdo.enable.bin)

if [ -f "$src" ]; then
    # libadf.a -> sw.o -> six CDO sections (same objcopy incantation as Tapasco)
    (cd "$work" && ar x "$src")
    for b in "${bins[@]}"; do
        objcopy -O binary --set-section-flags ".$b=alloc" -j ".$b" "$work/sw.o" "$work/$b" -I plugin
    done
    dir=$work
else
    dir=$src
fi

for b in "${bins[@]}"; do
    [ -s "$dir/$b" ] || { echo "missing $dir/$b" >&2; exit 1; }
done

bif=$work/aie_partial.bif
{
    echo "all:"
    echo "{"
    echo "  id_code = $idcode"
    echo "  extended_id_code = $extid"
    echo "  image"
    echo "  {"
    echo "    name=aie_image, id=0x1c000000"
    echo "    { type=cdo"
    for b in "${bins[@]}"; do echo "      file=$dir/$b"; done
    echo "    }"
    echo "  }"
    echo "}"
} > "$bif"

bootgen -arch versal -image "$bif" -w -o "$out" -log error
echo "wrote $out ($(stat -c %s "$out") bytes)"
