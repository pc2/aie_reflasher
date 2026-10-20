#!/usr/bin/env python3
"""Dump the image/partition structure of a Versal PDI and sanity-check AIE CDO partitions.

usage: pdi_info.py <file.pdi> [--cdo-dir <dir with aie.cdo.*.bin>] [--compare-with <other.pdi>] [--decode]

Note: bootgen rewrites write64/mask_poll64 whose upper address word is 0 into the 32-bit
write/mask_poll forms when it merges CDO files, so a byte compare against the raw bins fails
by design; --cdo-dir therefore compares command-by-command after normalising those forms.

Layout from embeddedsw lib/sw_services/xilpdi (xilpdi.h, versal/xilpdi_plat.h):
  Boot header (full PDI only): 'XLNX' at 0x14, meta-header offset at 0xC4.
  Image Header Table (128 B): Version, NoOfImgs, ImgHdrAddr(words), NoOfPrtns, PrtnHdrAddr(words),
     SBDAddr, Idcode, Attr, PdiId, ..., ident string at 0x28 ('PPDI' partial / 'FPDI' full).
  Image header (64 B): FirstPrtnHdr(words), NoOfPrtns, EncRevokeID, ImgAttr, ImgName[16], ImgID, UID, PUID, FuncID, ...
  Partition header (128 B): EncDataWordLen, UnEncDataWordLen, TotalDataWordLen, NextPrtnOfst(words),
     DstnExecutionAddr(64), DstnLoadAddr(64), DataWordOfst(words), PrtnAttrb, SectionCount, ChecksumWordOfst, PrtnId, ...
  PrtnAttrb[26:24]: 1 = ELF, 2 = CDO.
"""
import struct, sys, os
from pathlib import Path

def u32(d, o): return struct.unpack_from('<I', d, o)[0]
def u64(d, o): return struct.unpack_from('<Q', d, o)[0]

def parse(path):
    d = Path(path).read_bytes()
    out = {'file': path, 'size': len(d)}
    if len(d) > 0x18 and u32(d, 0x14) == 0x584C4E58:
        out['kind'] = 'full (boot header present)'
        iht = u32(d, 0xC4)
    elif u32(d, 0) == 0xDD and u32(d, 4) == 0x11223344:
        out['kind'] = 'partial (SMAP preamble, no boot header)'
        iht = 0x10
    else:
        out['kind'] = 'partial (no boot header)'
        iht = 0
    ident = d[iht+0x28:iht+0x2C]
    out['iht_off'] = iht
    out['ident'] = ident.decode('ascii', 'replace')
    out['version'] = u32(d, iht)
    n_img, ih_addr = u32(d, iht+4), u32(d, iht+8) * 4
    n_prt, ph_addr = u32(d, iht+0xC), u32(d, iht+0x10) * 4
    out['idcode'] = u32(d, iht+0x18)
    out['extid'] = u32(d, iht+0x44)
    out['iht_attr'] = u32(d, iht+0x1C)
    images = []
    for i in range(n_img):
        o = ih_addr + 64*i
        name = d[o+0x10:o+0x20].rstrip(b'\0').decode('ascii', 'replace')
        images.append({'first_ph': u32(d, o)*4, 'n_prtns': u32(d, o+4), 'attr': u32(d, o+0xC),
                       'name': name, 'img_id': u32(d, o+0x20), 'uid': u32(d, o+0x24), 'puid': u32(d, o+0x28)})
    prtns = []
    for i in range(n_prt):
        o = ph_addr + 128*i
        attr = u32(d, o+0x24)
        typ = {0x1000000: 'ELF', 0x2000000: 'CDO'}.get(attr & 0x7000000, hex(attr & 0x7000000))
        prtns.append({'hdr_off': o, 'enc_words': u32(d, o), 'unenc_words': u32(d, o+4), 'total_words': u32(d, o+8),
                      'exec': u64(d, o+0x10), 'load': u64(d, o+0x18), 'data_off': u32(d, o+0x20)*4,
                      'attr': attr, 'type': typ, 'prtn_id': u32(d, o+0x30)})
    out.update(n_img=n_img, n_prt=n_prt, images=images, prtns=prtns, data=d)
    return out

def strip_cdo_header(b):
    # 5-word CDO file header: ver, 'CDO\0', 0x200?, buflen(words), checksum
    w = struct.unpack_from('<5I', b, 0)
    assert w[1] == 0x004F4443, "no CDO magic"
    return b[20:20 + w[3]*4]

def main(argv):
    if len(argv) < 2:
        print(__doc__); return 2
    path, cdo_dir, decode, other = argv[1], None, False, None
    i = 2
    while i < len(argv):
        if argv[i] == '--cdo-dir': cdo_dir = argv[i+1]; i += 2
        elif argv[i] == '--compare-with': other = argv[i+1]; i += 2
        elif argv[i] == '--decode': decode = True; i += 1
        else: i += 1
    p = parse(path)
    print(f"{p['file']}: {p['size']} bytes, {p['kind']}, ident={p['ident']!r}, version=0x{p['version']:x}, idcode=0x{p['idcode']:08x}")
    print(f"  {p['n_img']} image(s), {p['n_prt']} partition(s)")
    for im in p['images']:
        print(f"  image {im['name']!r:14} id=0x{im['img_id']:08x} uid=0x{im['uid']:x} puid=0x{im['puid']:x} prtns={im['n_prtns']} attr=0x{im['attr']:x}")
    for k, pr in enumerate(p['prtns']):
        print(f"  prtn {k}: {pr['type']:4} data_off=0x{pr['data_off']:x} unenc={pr['unenc_words']} words ({pr['unenc_words']*4} B) load=0x{pr['load']:x} attr=0x{pr['attr']:08x} id=0x{pr['prtn_id']:x}")
    d = p['data']
    cdos = [pr for pr in p['prtns'] if pr['type'] == 'CDO']
    # Find the AIE image's CDO partition: the last CDO partition whose image is named aie_image (full PDI) or the only one (partial)
    aie_imgs = [im for im in p['images'] if im['name'] == 'aie_image']
    target = None
    if aie_imgs:
        im = aie_imgs[-1]
        target = [pr for pr in p['prtns'] if pr['hdr_off'] == im['first_ph']][0]
    elif len(cdos) == 1:
        target = cdos[0]
    if target is None:
        print("  no aie_image / single CDO partition found"); return 1
    blob = d[target['data_off']: target['data_off'] + target['unenc_words']*4]
    hdr = struct.unpack_from('<5I', blob, 0)
    print(f"  AIE CDO partition: {len(blob)} B, header ver=0x{hdr[0]:x} magic=0x{hdr[1]:x} len={hdr[3]} words -> payload {hdr[3]*4} B")
    payload = strip_cdo_header(blob)
    if p['kind'].startswith('partial'):
        ok = (p['ident'] == 'IDPP' and p['n_img'] == 1 and p['n_prt'] == 1 and p['images'][0]['name'] == 'aie_image'
              and p['images'][0]['img_id'] == 0x1c000000 and target['type'] == 'CDO')
        print(f"  partial-PDI shape (ident IDPP, one aie_image 0x1c000000, one CDO partition): {'OK' if ok else 'UNEXPECTED'}")
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import cdo_parser
    def norm(cmds):
        out = []
        for c in cmds:
            m, pl = c.mnemonic, list(c.raw_payload)
            if m == 'write64' and pl[0] == 0: m, pl = 'write', pl[1:]
            elif m == 'mask_poll64' and pl[0] == 0: m, pl = 'mask_poll', pl[1:]
            elif m == 'mask_write64' and pl[0] == 0: m, pl = 'mask_write', pl[1:]
            out.append((m, tuple(pl)))
        return out
    if other:
        q = parse(other)
        qi = [im for im in q['images'] if im['name'] == 'aie_image']
        if not qi: print(f"  {other}: no aie_image"); return 1
        qpr = [pr for pr in q['prtns'] if pr['hdr_off'] == qi[-1]['first_ph']][0]
        qpay = strip_cdo_header(q['data'][qpr['data_off']: qpr['data_off'] + qpr['unenc_words']*4])
        print(f"  aie_image CDO payload vs {other}: {len(payload)} B vs {len(qpay)} B -> {'BYTE-IDENTICAL' if qpay == payload else 'DIFFERENT'}")
        same_id = (p['idcode'] == q['idcode'] and p['extid'] == q['extid']) or (p['iht_attr'] & 0x1)
        print(f"  IDCODE/ExtIdCode vs {other}: 0x{p['idcode']:08x}/{p['extid']} vs 0x{q['idcode']:08x}/{q['extid']} -> "
              f"{'OK' if same_id else 'MISMATCH: the PLM will reject this PDI (XLOADER_ERR_IDCODE); rebuild with --like'}")
    if cdo_dir:
        bins = ["aie.cdo.reset.bin","aie.cdo.clock.gating.bin","aie.cdo.error.handling.bin","aie.cdo.elfs.bin","aie.cdo.init.bin","aie.cdo.enable.bin"]
        cat = b''.join(strip_cdo_header(Path(cdo_dir, b).read_bytes()) for b in bins)
        same = norm(cdo_parser.parse_binary_cdo(cat)) == norm(cdo_parser.parse_binary_cdo(payload))
        print(f"  command-by-command vs the six CDO bins in {cdo_dir}: {'EQUIVALENT' if same else 'DIFFERENT'}")
    if decode:
        cmds = cdo_parser.parse_binary_cdo(payload)
        from collections import Counter
        c = Counter(x.mnemonic for x in cmds)
        print(f"  decoded {len(cmds)} commands: {dict(c)}")
        npi = [x for x in cmds if any(isinstance(v, int) and 0xF70A0000 <= v < 0xF70B0000 for v in x.args.values())]
        print(f"  commands touching NPI 0xF70Axxxx: {len(npi)}")
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))
