// Host side for the AIEPdiLoader PE: DMA a partial PDI into card DDR, launch the PE with
// its PS address, decode the PE's 64-bit return value.
//
//   reflash-aie-loader <aie_partial.pdi>
//
// The IPI channel is a property of the design (the PDI-Loader feature's "ipi_channel", default 2):
// nothing else in a Tapasco design uses IPI0..4 (no A72/R5 software), whereas IPI5 is xsdb's
// channel and would collide with a JTAG session. IPI2 and IPI5 were both verified on hardware
// on 2026-10-20.
//
// Return value: [31:0] PLMI status (0 = success) or 0xFFFFFF00|err for loader errors
// (1 write resp, 2 read resp, 3 timeout, 4 PLM status != 0, 5 PMC still busy with an
// earlier request); [63:32] XilLoader status if the PLM reported an error, otherwise the
// handshake length in design clock cycles.

#include <chrono>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include <tapasco.hpp>

#define PE_NAME "pc2-sus-experiments:sus-xrt:AIEPdiLoader:1.0"

int main(int argc, char **argv) {
    if (argc != 2) { std::cerr << "usage: reflash-aie-loader <aie_partial.pdi>\n"; return 2; }
    const std::string pdi_path = argv[1];

    std::vector<uint8_t> pdi;
    {
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
    auto task = tap.launch(pe, ret, pdi_ps);
    task();
    double dt = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    tap.free(h);

    uint32_t lo = (uint32_t)result, hi = (uint32_t)(result >> 32);
    const bool local_err = (lo & 0xFFFFFF00U) == 0xFFFFFF00U;
    const bool plm_err = lo != 0 && !local_err;
    const float mhz = tap.design_frequency();
    std::cout << "PDI " << pdi.size() << " B at PS 0x" << std::hex << pdi_ps
              << ", result lo=0x" << lo << " hi=0x" << hi << std::dec;
    if (!plm_err)   // hi = cycles unless the PLM reported an error
        std::cout << ": " << hi << " cycles = " << (hi / (double)mhz) << " us at " << mhz << " MHz";
    std::cout << " (" << dt << " s wall)\n";
    if (local_err) {
        static const char *names[] = {"none", "write response error", "read response error",
                                      "timeout: PLM never acknowledged", "plm status",
                                      "busy: PMC still holds an unacknowledged earlier request (PLM not servicing this channel)"};
        uint32_t e = lo & 0xFF;
        std::cerr << "loader error " << e << (e < 6 ? std::string(" (") + names[e] + ")" : "") << "\n";
        return 1;
    }
    if (lo != 0) { std::cerr << "PLM rejected the PDI: PLMI status 0x" << std::hex << lo << " loader 0x" << hi << std::dec << "\n"; return 1; }
    std::cout << "AIE reflashed\n";
    return 0;
}
