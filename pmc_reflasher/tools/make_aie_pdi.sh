#!/usr/bin/env bash
# Build an AIE-only partial PDI that the PLM can load at runtime.
#
#   make_aie_pdi.sh <libadf.a | dir with aie.cdo.*.bin> <out.pdi>
#
# The image is the same "aie_image" (id 0x1c000000, type=cdo) that Tapasco's
# ai_engine.tcl plugin appends to the boot PDI, just without the bootimage
# part, so it is a partial PDI. Order of the CDOs matches Tapasco's plugin.
set -euo pipefail

src=$(realpath "${1:?source (libadf.a or dir)}")
out=$(realpath -m "${2:?output pdi}")
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
