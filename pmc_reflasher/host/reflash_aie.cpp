// Host side of the PMC-based AI Engine reflasher.
//
//   reflash-aie <aie_partial.pdi> [--timeout <s>] [--log] [--ping]
//
// Copies the partial PDI into card DDR, rings the mailbox polled by the A72
// firmware, and waits for the PLM's verdict. No PE is involved; the only
// Tapasco functionality used is DMA to/from device memory.

#include <chrono>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#include <tapasco.hpp>

#include "reflash_proto.h"

static const char *state_name(uint32_t s) {
    switch (s) {
    case REFLASH_STATE_IDLE:  return "idle";
    case REFLASH_STATE_BUSY:  return "busy";
    case REFLASH_STATE_OK:    return "ok";
    case REFLASH_STATE_ERROR: return "error";
    default:                  return "?";
    }
}

static void dump_log(tapasco::Tapasco &tap, const reflash_resp &r) {
    std::vector<uint8_t> buf(REFLASH_LOG_SIZE);
    tap.copy_from(REFLASH_REGION_DEV_OFFSET + REFLASH_LOG_OFF, buf.data(), buf.size());
    uint32_t n = r.log_wr < REFLASH_LOG_SIZE ? r.log_wr : REFLASH_LOG_SIZE;
    uint32_t start = r.log_wr < REFLASH_LOG_SIZE ? 0 : r.log_wr % REFLASH_LOG_SIZE;
    std::cerr << "---- firmware log ----\n";
    for (uint32_t i = 0; i < n; ++i)
        std::cerr << (char)buf[(start + i) % REFLASH_LOG_SIZE];
    std::cerr << "\n----------------------\n";
}

static reflash_resp read_resp(tapasco::Tapasco &tap) {
    reflash_resp r{};
    tap.copy_from(REFLASH_REGION_DEV_OFFSET + REFLASH_RESP_OFF, reinterpret_cast<uint8_t *>(&r), sizeof(r));
    return r;
}

int main(int argc, char **argv) {
    std::string pdi_path;
    double timeout_s = 10.0;
    bool want_log = false, ping = false;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--timeout" && i + 1 < argc) timeout_s = std::stod(argv[++i]);
        else if (a == "--log") want_log = true;
        else if (a == "--ping") ping = true;
        else pdi_path = a;
    }
    if (pdi_path.empty() && !ping) {
        std::cerr << "usage: reflash-aie <aie_partial.pdi> [--timeout s] [--log] [--ping]\n";
        return 2;
    }

    tapasco::Tapasco tap;

    // Reserve the region so Tapasco's allocator never hands it to anyone else.
    // (If another process already holds it this fails; run only one reflasher.)
    tapasco::DeviceAddress region = 0;
    if (tap.alloc(region, REFLASH_REGION_SIZE, (size_t)REFLASH_REGION_DEV_OFFSET) != 0 ||
        region != REFLASH_REGION_DEV_OFFSET) {
        std::cerr << "could not reserve device memory region at offset 0x" << std::hex
                  << REFLASH_REGION_DEV_OFFSET << " (got 0x" << region << ")\n";
        return 1;
    }

    reflash_resp r = read_resp(tap);
    if (r.magic != REFLASH_MAGIC) {
        std::cerr << "firmware mailbox not present (magic 0x" << std::hex << r.magic
                  << "); is the A72 firmware running?\n";
        return 1;
    }
    std::cout << "firmware v" << r.fw_version << " state=" << state_name(r.state)
              << " seq=" << r.seq << " loads_done=" << r.loads_done << "\n";
    if (r.state == REFLASH_STATE_BUSY) {
        std::cerr << "firmware is busy with a previous request\n";
        return 1;
    }

    reflash_req q{};
    q.magic = REFLASH_MAGIC;
    q.seq = r.seq + 1;
    if (ping) {
        q.cmd = REFLASH_CMD_PING;
    } else {
        std::ifstream f(pdi_path, std::ios::binary | std::ios::ate);
        if (!f) { std::cerr << "cannot open " << pdi_path << "\n"; return 1; }
        std::streamsize size = f.tellg();
        f.seekg(0);
        if (size <= 0 || size > (std::streamsize)REFLASH_PDI_MAX || (size & 3)) {
            std::cerr << "bad PDI size " << size << "\n";
            return 1;
        }
        std::vector<uint8_t> pdi(size);
        if (!f.read(reinterpret_cast<char *>(pdi.data()), size)) {
            std::cerr << "read failed\n";
            return 1;
        }
        tap.copy_to(pdi.data(), REFLASH_REGION_DEV_OFFSET + REFLASH_PDI_OFF, pdi.size());
        q.cmd = REFLASH_CMD_LOAD_PDI;
        q.pdi_size = (uint32_t)size;
        q.pdi_dev_offset = REFLASH_REGION_DEV_OFFSET + REFLASH_PDI_OFF;
    }

    auto t0 = std::chrono::steady_clock::now();
    // One 64-byte write; the firmware reacts to the seq change.
    tap.copy_to(reinterpret_cast<uint8_t *>(&q), REFLASH_REGION_DEV_OFFSET + REFLASH_REQ_OFF, sizeof(q));

    for (;;) {
        r = read_resp(tap);
        if (r.seq == q.seq && r.state != REFLASH_STATE_BUSY)
            break;
        auto dt = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        if (dt > timeout_s) {
            std::cerr << "timeout waiting for firmware (state=" << state_name(r.state)
                      << " seq=" << r.seq << ")\n";
            dump_log(tap, r);
            return 1;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    auto dt = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();

    std::cout << "state=" << state_name(r.state) << " fw_error=" << r.fw_error
              << " plmi_status=0x" << std::hex << r.plmi_status
              << " loader_status=0x" << r.loader_status << std::dec
              << " (" << dt << " s)\n";
    if (want_log || r.state != REFLASH_STATE_OK)
        dump_log(tap, r);
    return r.state == REFLASH_STATE_OK ? 0 : 1;
}
