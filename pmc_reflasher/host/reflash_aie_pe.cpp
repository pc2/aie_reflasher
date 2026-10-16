// AI Engine reflash through the existing AIEngineReflasher PE: the PE performs the
// IPI handshake with the PLM, the PLM loads an AIE-only partial PDI from card DDR.
//
//   reflash-aie-pe <aie_partial.pdi> [--channel 5] [--no-resp-check] [--ctrl 0x31000031111]
//
// The PE executes a binary CDO command stream (write64 / mask_poll64) over its
// AXI-Lite "small" port, which Tapasco routes through the NoC into the PMC/LPD
// address space (NOC_PMC_AXI_0). The stream we generate is 7 commands:
//
//   write64  IPI<n> request buffer[0..3] = {0x030701, 0xF, pdi_addr_hi, pdi_addr_lo}
//   write64  IPI<n>.TRIG = 0x2                      (ring the PMC)
//   mask_poll64 IPI<n>.OBS & 0x2 == 0               (PLM acknowledged)
//   mask_poll64 response[0] & 0xFFFFFFFF == 0       (PLM status OK; optional)
//
// Register facts: embeddedsw ipipsu driver, PLM xplmi_ipi.c, ATF plat_ipi.h.
// IPI<n> (n=0..5): regs 0xFF330000 + n*0x10000 (TRIG +0, OBS +4), buffer index 2+n.
// Message RAM 0xFF3F0000 + src_index*0x200 + dst_index*0x40 (+0x20 = response).
// PMC: mask 0x2, buffer index 1. IPI5 is what the PLM calls the xsdb master.
//
// Requires: the IPI<n> channel enabled in the CIPS (PS_GEN_IPI<n>_ENABLE 1) so that
// psv_ipi_<n> and psv_ipi_buffer are assigned in the PE's small_axil address space.

#include <chrono>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include <tapasco.hpp>

#define PE_NAME "pc2-sus-experiments:sus-xrt:AIEngineReflasher:1.0"

namespace {

constexpr uint64_t DDR_PS_BASE   = 0x10000000000ULL;   // DDR_LOW3 as seen from PS/PMC/PE bulk port
constexpr uint32_t IPI_MSG_RAM   = 0xFF3F0000U;
constexpr uint32_t IPI_PMC_MASK  = 0x2U;
constexpr uint32_t IPI_PMC_INDEX = 1U;
constexpr uint32_t PLM_CMD_LOAD_PDI = 0x030701U;   // len 3, XilLoader (7), LOAD_SUBSYSTEM_PDI (1)
constexpr uint32_t PLM_PDI_SRC_DDR  = 0xFU;

// CDO opcodes (module 1), as implemented by the PE
constexpr uint32_t OP_MASK_POLL64 = 6, OP_WRITE64 = 8;

struct Stream {
    std::vector<uint32_t> w;
    void write64(uint64_t addr, uint32_t val) {
        w.push_back(OP_WRITE64 | (1u << 8) | (3u << 16));
        w.push_back((uint32_t)(addr >> 32)); w.push_back((uint32_t)addr); w.push_back(val);
    }
    void mask_poll64(uint64_t addr, uint32_t mask, uint32_t expected, uint32_t timeout) {
        w.push_back(OP_MASK_POLL64 | (1u << 8) | (5u << 16));
        w.push_back((uint32_t)(addr >> 32)); w.push_back((uint32_t)addr);
        w.push_back(mask); w.push_back(expected); w.push_back(timeout);
    }
};

} // namespace

int main(int argc, char **argv) {
    std::string pdi_path;
    int chan = 5;
    bool resp_check = true;
    uint64_t ctrl = 0x00031000031111ULL;   // AxPROT/AxCACHE bits, same as reconfig_main.cpp
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--channel" && i + 1 < argc) chan = std::stoi(argv[++i]);
        else if (a == "--no-resp-check") resp_check = false;
        else if (a == "--ctrl" && i + 1 < argc) ctrl = std::stoull(argv[++i], nullptr, 0);
        else pdi_path = a;
    }
    if (pdi_path.empty() || chan < 0 || chan > 5) {
        std::cerr << "usage: reflash-aie-pe <aie_partial.pdi> [--channel 0..5] [--no-resp-check] [--ctrl X]\n";
        return 2;
    }

    std::ifstream f(pdi_path, std::ios::binary | std::ios::ate);
    if (!f) { std::cerr << "cannot open " << pdi_path << "\n"; return 1; }
    std::streamsize size = f.tellg();
    f.seekg(0);
    if (size <= 0 || (size & 3)) { std::cerr << "bad PDI size " << size << "\n"; return 1; }
    std::vector<uint8_t> pdi(size);
    if (!f.read(reinterpret_cast<char *>(pdi.data()), size)) { std::cerr << "read failed\n"; return 1; }

    tapasco::Tapasco tap;
    tapasco::PEId pe = tap.get_pe_id(PE_NAME);

    // 1. PDI into card DDR.
    tapasco::DeviceAddress pdi_h = 0;
    if (tap.alloc(pdi_h, pdi.size()) != 0) { std::cerr << "alloc failed\n"; return 1; }
    tap.copy_to(pdi.data(), pdi_h, pdi.size());
    const uint64_t pdi_ps = DDR_PS_BASE + pdi_h;

    // 2. Command stream for the PE.
    const uint32_t ipi_base = 0xFF330000U + (uint32_t)chan * 0x10000U;
    const uint32_t ipi_idx  = 2U + (uint32_t)chan;
    const uint64_t req  = IPI_MSG_RAM + ipi_idx * 0x200U + IPI_PMC_INDEX * 0x40U;
    const uint64_t resp = IPI_MSG_RAM + IPI_PMC_INDEX * 0x200U + ipi_idx * 0x40U + 0x20U;

    // The PE ignores AXI error responses, so an unmapped address reads back as junk
    // (usually 0) and a naive poll would pass. Every step below therefore waits for a
    // value that only exists if the access really reached the IPI block.
    constexpr uint32_t SENTINEL = 0xDEADBEEFU;
    Stream s;
    s.write64(req + 0x0, PLM_CMD_LOAD_PDI);
    s.write64(req + 0x4, PLM_PDI_SRC_DDR);
    s.write64(req + 0x8, (uint32_t)(pdi_ps >> 32));
    s.write64(req + 0xC, (uint32_t)(pdi_ps & 0xFFFFFFFFU));
    s.mask_poll64(req + 0x0, 0xFFFFFFFFU, PLM_CMD_LOAD_PDI, 0); // message RAM reachable?
    s.write64(resp, SENTINEL);                                // PLM overwrites this with its status
    s.write64(ipi_base + 0x0, IPI_PMC_MASK);                  // TRIG
    s.mask_poll64(ipi_base + 0x4, IPI_PMC_MASK, 0, 0);        // OBS: wait for ack
    if (resp_check)
        s.mask_poll64(resp, 0xFFFFFFFFU, 0, 0);               // response[0] == XST_SUCCESS (sentinel gone)
    // Without the response check the stream ends at the OBS poll: it proves the PLM
    // answered but not whether it liked the PDI. Verify functionally afterwards.

    tapasco::DeviceAddress st_h = 0;
    const size_t st_bytes = s.w.size() * 4;
    if (tap.alloc(st_h, st_bytes) != 0) { std::cerr << "alloc failed\n"; return 1; }
    tap.copy_to(reinterpret_cast<uint8_t *>(s.w.data()), st_h, st_bytes);

    std::cout << "PDI " << pdi.size() << " bytes at PS 0x" << std::hex << pdi_ps
              << ", IPI" << std::dec << chan << " req 0x" << std::hex << req << " resp 0x" << resp
              << ", stream " << std::dec << s.w.size() << " words at device 0x" << std::hex << st_h << std::dec << "\n";

    // 3. Run the PE. It finishes only after every command, i.e. after the PLM acked
    //    (and, with the response check, after the PLM reported success). If it never
    //    returns, the PLM either rejected the PDI or the IPI path is not reachable.
    unsigned int cycles = 0;
    tapasco::RetVal<unsigned int> ret(&cycles);
    auto t0 = std::chrono::steady_clock::now();
    auto task = tap.launch(pe, ret, DDR_PS_BASE + st_h, (size_t)s.w.size(), ctrl);
    task();
    double dt = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    std::cout << "PE done in " << dt << " s" << (resp_check ? " (PLM status 0 confirmed)" : " (PLM acked)") << "\n";

    tap.free(st_h);
    tap.free(pdi_h);
    return 0;
}
