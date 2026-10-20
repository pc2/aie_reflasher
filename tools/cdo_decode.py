import sys, struct

def words(data):
    n = len(data) // 4
    return struct.unpack('<%dI' % n, data[:n*4])

def decode(path, max_print=40):
    data = open(path, 'rb').read()
    w = words(data)
    print(f"=== {path} ({len(data)} bytes, {len(w)} words) ===")
    i = 0
    # detect + skip standard CDO header: len, 'CDO\0', ..., buflen, checksum
    if len(w) >= 5 and w[1] == 0x004F4443:
        print(f"CDO header: ver={w[0]:#x} id={w[1]:#x} hdrlen={w[2]:#x} buflen={w[3]:#x} chksum={w[4]:#x}")
        i = 5
    printed = 0
    counts = {}
    addrs_20000 = []
    while i < len(w):
        hdr = w[i]
        cmdid = hdr & 0xFF
        paylen = (hdr >> 16) & 0xFF
        i += 1
        if paylen == 0xFF:
            paylen = w[i]; i += 1
        payload = w[i:i+paylen]
        i += paylen
        counts[cmdid] = counts.get(cmdid, 0) + 1
        desc = None
        if cmdid == 3 and len(payload) >= 2:      # WRITE
            desc = f"WRITE      addr={payload[0]:#010x} val={payload[1]:#010x}"
        elif cmdid == 2 and len(payload) >= 3:    # MASK_WRITE
            desc = f"MASKWRITE  addr={payload[0]:#010x} mask={payload[1]:#010x} val={payload[2]:#010x}"
        elif cmdid == 8 and len(payload) >= 3:    # WRITE64
            addr = (payload[0] << 32) | payload[1]
            desc = f"WRITE64    addr={addr:#014x} val={payload[2]:#010x}"
            if 0x20000000000 <= addr < 0x20100000000:
                addrs_20000.append(('WRITE64', addr, payload[2]))
        elif cmdid == 7 and len(payload) >= 4:    # MASKWRITE64
            addr = (payload[0] << 32) | payload[1]
            desc = f"MASKWRITE64 addr={addr:#014x} mask={payload[2]:#010x} val={payload[3]:#010x}"
            if 0x20000000000 <= addr < 0x20100000000:
                addrs_20000.append(('MASKWRITE64', addr, payload[3]))
        elif cmdid == 5 and len(payload) >= 4:    # DMAWRITE
            dest = (payload[0] << 32) | payload[1]
            desc = f"DMAWRITE   dest={dest:#014x} srcoff={payload[2]:#x} len={payload[3]:#x}"
            if 0x20000000000 <= dest < 0x20100000000:
                addrs_20000.append(('DMAWRITE', dest, payload[3]))
        elif cmdid == 17:
            desc = "NOP"
        else:
            desc = f"CMD id={cmdid} module={((hdr>>8)&0xFF):#x} paylen={paylen}"
        if printed < max_print:
            print(desc)
            printed += 1
    print("counts by cmdid:", counts)
    if addrs_20000:
        print(f"** {len(addrs_20000)} commands target the 0x20000000000-0x20100000000 (AIE array) window **")
        for t in addrs_20000[:15]:
            print("   ", t)
    else:
        print("** no commands found targeting the 0x20000000000 window **")
    print()

for p in sys.argv[1:]:
    decode(p)
