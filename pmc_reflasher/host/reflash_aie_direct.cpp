// Direct-from-host AI Engine reflasher: no firmware on the card.
//
//   reflash-aie-direct <aie_partial.pdi> [--bdf 0000:xx:yy.z] [--bar 4] [--bar-offset 0x0]
//                      [--channel 5] [--timeout s] [--ping]
//
// The host itself performs the IPI handshake with the PLM by writing the Versal
// IPI registers through a PCIe BAR that the design maps onto the LPD IPI block
// (AXI 0xFF300000, 1 MiB). It impersonates one of the PS IPI channels (default
// IPI5, which the PLM treats as the external "xsdb" debug master). The PDI itself
// goes into card DDR with Tapasco's DMA, and the PLM fetches it from there.
//
// Register facts (embeddedsw ipipsu driver, PLM xplmi_ipi.c, ATF plat_ipi.h):
//   channel regs:  TRIG +0x0, OBS +0x4, ISR +0x10  (PMC 0xFF320000, IPI0 0xFF330000, ... IPI5 0xFF380000)
//   bit masks:     PSM 0x1, PMC 0x2, IPI0 0x4 ... IPI5 0x80 ; buffer index PMC=1, IPI0=2 ... IPI5=7
//   message RAM:   0xFF3F0000 + src_index*0x200 + dst_index*0x40 (+0x20 for the response buffer)
//   request:       X -> PMC lives in X's group, PMC target ; response PMC -> X lives in PMC's group, X target
//   PLM listens on IPI0..IPI5 (IMR mask 0xFC) and acks by clearing its ISR bit, which clears our OBS bit.

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#include <dirent.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <tapasco.hpp>

#include "reflash_proto.h"   // REFLASH_DDR_PS_BASE

namespace {

constexpr uint64_t IPI_BLOCK_AXI_BASE = 0xFF300000ULL;  // what BAR offset 0 corresponds to
constexpr uint32_t IPI_MSG_RAM        = 0xFF3F0000U;
constexpr uint32_t IPI_PMC_BASE       = 0xFF320000U;
constexpr uint32_t IPI_PMC_MASK       = 0x2U;
constexpr uint32_t IPI_PMC_INDEX      = 1U;
constexpr uint32_t REG_TRIG = 0x0, REG_OBS = 0x4, REG_ISR = 0x10;

struct Channel { uint32_t base, mask, index; };
Channel channel_for(int n) {
    // IPI0..IPI5: base 0xFF330000 + n*0x10000, mask bit (2+n), buffer index 2+n
    return Channel{0xFF330000U + (uint32_t)n * 0x10000U, 1U << (2 + n), 2U + (uint32_t)n};
}

// XilLoader LOAD_SUBSYSTEM_PDI: header (len 3, module 7, cmd 1), src DDR, addr hi, addr lo
constexpr uint32_t PLM_CMD_LOAD_PDI = 0x030701U;
constexpr uint32_t PLM_PDI_SRC_DDR  = 0xFU;
// XilPlmi "features" query, module 1 (generic) cmd 0: cheap liveness check
constexpr uint32_t PLM_CMD_FEATURES = 0x010100U;

class Bar {
public:
    bool open(const std::string &bdf, int bar) {
        std::string path = "/sys/bus/pci/devices/" + bdf + "/resource" + std::to_string(bar);
        fd_ = ::open(path.c_str(), O_RDWR | O_SYNC);
        if (fd_ < 0) { perror(path.c_str()); return false; }
        struct stat st{};
        if (fstat(fd_, &st) != 0) { perror("fstat"); return false; }
        len_ = (size_t)st.st_size;
        p_ = (volatile uint8_t *)mmap(nullptr, len_, PROT_READ | PROT_WRITE, MAP_SHARED, fd_, 0);
        if (p_ == MAP_FAILED) { perror("mmap"); p_ = nullptr; return false; }
        return true;
    }
    ~Bar() { if (p_) munmap((void *)p_, len_); if (fd_ >= 0) ::close(fd_); }
    size_t len() const { return len_; }
    uint32_t rd(uint64_t off) const {
        return *(volatile uint32_t *)(p_ + off);
    }
    void wr(uint64_t off, uint32_t v) {
        *(volatile uint32_t *)(p_ + off) = v;
    }
private:
    int fd_ = -1;
    size_t len_ = 0;
    volatile uint8_t *p_ = nullptr;
};

std::string find_bdf(uint32_t vendor, uint32_t device) {
    DIR *d = opendir("/sys/bus/pci/devices");
    if (!d) return "";
    std::string found;
    while (dirent *e = readdir(d)) {
        if (e->d_name[0] == '.') continue;
        std::string base = std::string("/sys/bus/pci/devices/") + e->d_name;
        std::ifstream fv(base + "/vendor"), fd(base + "/device");
        uint32_t v = 0, dv = 0;
        fv >> std::hex >> v; fd >> std::hex >> dv;
        if (v == vendor && dv == device) { found = e->d_name; break; }
    }
    closedir(d);
    return found;
}

} // namespace

int main(int argc, char **argv) {
    std::string pdi_path, bdf;
    int bar = 4, chan = 5;
    uint64_t bar_offset = 0;  // offset inside the BAR where AXI 0xFF300000 appears
    double timeout_s = 10.0;
    bool ping = false;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&](void) -> std::string { return (i + 1 < argc) ? argv[++i] : ""; };
        if (a == "--bdf") bdf = next();
        else if (a == "--bar") bar = std::stoi(next());
        else if (a == "--bar-offset") bar_offset = std::stoull(next(), nullptr, 0);
        else if (a == "--channel") chan = std::stoi(next());
        else if (a == "--timeout") timeout_s = std::stod(next());
        else if (a == "--ping") ping = true;
        else pdi_path = a;
    }
    if ((pdi_path.empty() && !ping) || chan < 0 || chan > 5) {
        std::cerr << "usage: reflash-aie-direct <aie_partial.pdi> [--bdf B:D.F] [--bar N] [--bar-offset X] [--channel 0..5] [--timeout s] [--ping]\n";
        return 2;
    }
    if (bdf.empty()) {
        bdf = find_bdf(0x10ee, 0xb03f);  // Tapasco VCK5000: CPM_PCIE0_PF0_CFG_DEV_ID {B03F}
        if (bdf.empty()) { std::cerr << "no 10ee:b03f device found, pass --bdf\n"; return 1; }
    }

    Bar b;
    if (!b.open(bdf, bar)) return 1;
    const Channel ch = channel_for(chan);
    auto off = [&](uint64_t axi) { return bar_offset + (axi - IPI_BLOCK_AXI_BASE); };
    if (off(IPI_MSG_RAM + 0x2000) > b.len()) {
        std::cerr << "BAR" << bar << " too small (" << b.len() << " bytes) for the IPI block\n";
        return 1;
    }
    const uint64_t req_buf  = off(IPI_MSG_RAM + ch.index * 0x200 + IPI_PMC_INDEX * 0x40);
    const uint64_t resp_buf = off(IPI_MSG_RAM + IPI_PMC_INDEX * 0x200 + ch.index * 0x40 + 0x20);
    const uint64_t trig = off(ch.base + REG_TRIG), obs = off(ch.base + REG_OBS);

    // Sanity: a readable OBS register. 0xFFFFFFFF usually means the window does not reach the LPD.
    uint32_t o = b.rd(obs);
    std::cout << "bdf " << bdf << " bar" << bar << " channel IPI" << chan
              << " OBS=0x" << std::hex << o << " PMC_ISR=0x" << b.rd(off(IPI_PMC_BASE + REG_ISR)) << std::dec << "\n";
    if (o == 0xFFFFFFFFU) { std::cerr << "IPI block not reachable through this BAR\n"; return 1; }
    if (o & IPI_PMC_MASK) { std::cerr << "a request from IPI" << chan << " is still pending at the PMC\n"; return 1; }

    // Stage the PDI in card DDR.
    tapasco::Tapasco tap;
    tapasco::DeviceAddress h = 0;
    std::vector<uint8_t> pdi;
    uint32_t payload[8] = {0};
    if (ping) {
        payload[0] = PLM_CMD_FEATURES;
    } else {
        std::ifstream f(pdi_path, std::ios::binary | std::ios::ate);
        if (!f) { std::cerr << "cannot open " << pdi_path << "\n"; return 1; }
        std::streamsize size = f.tellg();
        f.seekg(0);
        if (size <= 0 || (size & 3)) { std::cerr << "bad PDI size\n"; return 1; }
        pdi.resize(size);
        if (!f.read(reinterpret_cast<char *>(pdi.data()), size)) { std::cerr << "read failed\n"; return 1; }
        if (tap.alloc(h, pdi.size()) != 0) { std::cerr << "device alloc failed\n"; return 1; }
        tap.copy_to(pdi.data(), h, pdi.size());
        uint64_t ps_addr = REFLASH_DDR_PS_BASE + h;
        payload[0] = PLM_CMD_LOAD_PDI;
        payload[1] = PLM_PDI_SRC_DDR;
        payload[2] = (uint32_t)(ps_addr >> 32);
        payload[3] = (uint32_t)(ps_addr & 0xFFFFFFFFU);
        std::cout << "PDI " << pdi.size() << " bytes at device 0x" << std::hex << h
                  << " (PS 0x" << ps_addr << ")" << std::dec << "\n";
    }

    // IPI handshake.
    for (int i = 0; i < 8; ++i) b.wr(req_buf + 4 * i, payload[i]);
    std::atomic_thread_fence(std::memory_order_seq_cst);
    (void)b.rd(req_buf);                       // flush posted writes before the doorbell
    auto t0 = std::chrono::steady_clock::now();
    b.wr(trig, IPI_PMC_MASK);
    for (;;) {
        if (!(b.rd(obs) & IPI_PMC_MASK)) break;
        double dt = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        if (dt > timeout_s) {
            std::cerr << "timeout: PLM did not ack (OBS=0x" << std::hex << b.rd(obs)
                      << " PMC_ISR=0x" << b.rd(off(IPI_PMC_BASE + REG_ISR)) << std::dec << ")\n";
            if (h) tap.free(h);
            return 1;
        }
        std::this_thread::sleep_for(std::chrono::microseconds(200));
    }
    double dt = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    uint32_t r0 = b.rd(resp_buf), r1 = b.rd(resp_buf + 4);
    if (h) tap.free(h);

    std::cout << "plmi_status=0x" << std::hex << r0 << " loader_status=0x" << r1 << std::dec
              << " (" << dt << " s)\n";
    return r0 == 0 ? 0 : 1;
}
