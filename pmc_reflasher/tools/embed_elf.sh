#!/usr/bin/env bash
# Append the A72 firmware to an existing Tapasco PDI so the PLM starts it at boot.
#
#   embed_elf.sh <in.pdi> <aie_reflasher.elf> <out.pdi>
#
# Works on the PDI Tapasco already wrapped with the AIE image: bootgen's
# type=bootimage keeps every image of the input and we add one more.
set -euo pipefail

in=$(realpath "${1:?input pdi}")
elf=$(realpath "${2:?firmware elf}")
out=${3:?output pdi}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/fw.bif" <<EOF
all:
{
  image
  {
    { type=bootimage, file=$in }
  }
  image
  {
    name=default_subsys, id=0x1c000000
    { core=a72-0, file=$elf }
  }
}
EOF

bootgen -arch versal -image "$work/fw.bif" -w -o "$out" -log error
echo "wrote $out"
