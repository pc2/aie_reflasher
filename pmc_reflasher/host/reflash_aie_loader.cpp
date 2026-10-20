// Host side for the AIEPdiLoader PE: DMA a partial PDI into card DDR, launch the PE with
// its PS address, decode the PE's 64-bit return value.
//
//   reflash-aie-loader <aie_partial.pdi> [--axprot 0x0]
//   reflash-aie-loader --ping                  (sends XilPlmi FEATURES instead of LOAD_PDI)
//
// Return value: [31:0] PLMI status (0 = success) or 0xFFFFFF00|err for PE-local errors
// (1 write resp, 2 read resp, 3 timeout, 4 PLM status != 0, 5 PMC still busy with an
// earlier request), [63:32] XilLoader status.

#include <chrono>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include <tapasco.hpp>

#define PE_NAME "pc2-sus-experiments:sus-xrt:AIEPdiLoader:1.0"

int main(int argc, char **argv) {
    std::string pdi_path;
    uint64_t axprot = 0;
    bool ping = false;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--axprot" && i + 1 < argc) axprot = std::stoull(argv[++i], nullptr, 0);
        else if (a == "--ping") ping = true;
        else pdi_path = a;
    }
    if (pdi_path.empty() && !ping) { std::cerr << "usage: reflash-aie-loader <aie_partial.pdi> [--axprot X] | --ping\n"; return 2; }
    // input_regs[1]: [31:0] AxPROT/AxCACHE bits, [63:32] IPI command word override
    const uint64_t cfg = (axprot & 0xFFFFFFFFULL) | (ping ? (0x010100ULL << 32) : 0);  // FEATURES: len 1, module 1, api 0

    std::vector<uint8_t> pdi(4096, 0);   // dummy for --ping
    if (!ping) {
        std::ifstream f(pdi_path, std::ios::binary | std::ios::ate);
        if (!f) { std::cerr << "cannot open " << pdi_path << "\n"; return 1; }
        std::streamsize size = f.tellg();
        f.seekg(0);
        if (size <= 0 || (size & 3)) { std::cerr << "bad PDI size " << size << "\n"; return 1; }
        pdi.resize(size);
        if (!f.read(reinterpret_cast<char *>(pdi.data()), size)) { std::cerr << "read failed\n"; return 1; }
    }

    tapasco::Tapasco tap;
    tapasco::PEId pe = tap.get_pe_id(PE_NAME);
    tapasco::DeviceAddress h = 0;
    if (tap.alloc(h, pdi.size()) != 0) { std::cerr << "alloc failed\n"; return 1; }
    tap.copy_to(pdi.data(), h, pdi.size());
    const uint64_t pdi_ps = 0x10000000000ULL + h;   // DDR_LOW3 as seen by the PMC

    uint64_t result = 0;
    tapasco::RetVal<uint64_t> ret(&result);
    auto t0 = std::chrono::steady_clock::now();
    auto task = tap.launch(pe, ret, pdi_ps, cfg);
    task();
    double dt = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    tap.free(h);

    uint32_t lo = (uint32_t)result, hi = (uint32_t)(result >> 32);
    std::cout << "PDI " << pdi.size() << " B at PS 0x" << std::hex << pdi_ps << ", result lo=0x" << lo
              << " hi=0x" << hi << std::dec << " (" << dt << " s)\n";
    if ((lo & 0xFFFFFF00U) == 0xFFFFFF00U) {
        static const char *names[] = {"none", "write response error", "read response error",
                                      "timeout: PLM never acknowledged", "plm status",
                                      "busy: PMC still holds an unacknowledged earlier request (PLM not servicing IPI5)"};
        uint32_t e = lo & 0xFF;
        std::cerr << "PE error " << e << (e < 6 ? std::string(" (") + names[e] + ")" : "") << "\n";
        return 1;
    }
    if (lo != 0) { std::cerr << "PLM rejected the PDI: PLMI status 0x" << std::hex << lo << " loader 0x" << hi << std::dec << "\n"; return 1; }
    std::cout << (ping ? "PLM answered the ping: IPI path OK\n" : "AIE reflashed\n");
    return 0;
}
