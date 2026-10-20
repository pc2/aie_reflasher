// Vector-norm check for the DataStreamerVN + AIE design (tapasco-examples/Vector-Norm/sw/C++,
// Boost dependency removed). Streams (x, y) pairs through the PL PE into the AIE graph and
// checks z = sqrt(x^2 + y^2). With aie/libadf_b.pdi loaded every result is doubled, so this
// tool is how a reflash is verified: it passes with design A and reports every index wrong
// by a factor of 2 with design B.
//
//   vector-norm [--samples N]        (N a multiple of 1024, default 16384)
//   vector-norm --expect-scale 2     (accept outputs scaled by this factor, i.e. design B)

#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#include <tapasco.hpp>

#define DEFAULT_SAMPLES 16384
// SUS DataStreamerVN (sus/data_streamer_vn.sus); the Bluespec original from tapasco-examples
// is accepted as a fallback so the tool also runs on bitstreams built with it.
#define PE_NAME          "pc2-sus-experiments:sus-xrt:DataStreamerVN:1.0"
#define PE_NAME_BLUESPEC "esa.informatik.tu-darmstadt.de:user:DataStreamerVN:1.0"

int main(int argc, char **argv) {

        size_t num_samples = DEFAULT_SAMPLES;
        float expect_scale = 1.0f;
        for (int i = 1; i < argc; ++i) {
                std::string a = argv[i];
                if (a == "--samples" && i + 1 < argc) num_samples = std::strtoull(argv[++i], nullptr, 0);
                else if (a == "--expect-scale" && i + 1 < argc) expect_scale = std::strtof(argv[++i], nullptr);
                else { std::cerr << "usage: vector-norm [--samples N] [--expect-scale S]" << std::endl; return 2; }
        }

        if (num_samples % 1024) {
                std::cout << "ERROR: number of samples must be multiple of 1024" << std::endl;
                return -1;
        } else if (num_samples > (1UL << 32)) {
                std::cout << "WARNING: truncating to maximum number of samples (" << (1UL << 32) << ")" <<  std::endl;
                num_samples = 1UL << 32;
        }

        std::vector<float> input;
        std::vector<float> output;
        input.resize(num_samples * 2);
        output.resize(num_samples);

        // populate input array
        std::cout <<  "Populate input array" << std::endl;
        for (size_t i = 0; i < num_samples; ++i) {
                input[i * 2] = (float)i;
                input[i * 2 + 1] = (float)(num_samples - i);
        }

        // instantiate Tapasco (assume only one FPGA connected to this host)
        tapasco::Tapasco tap;
        tapasco::PEId peId;
        try {
                peId = tap.get_pe_id(PE_NAME);
        } catch (...) {
                std::cout << "PE " PE_NAME " not in this bitstream, trying " PE_NAME_BLUESPEC << std::endl;
                peId = tap.get_pe_id(PE_NAME_BLUESPEC);
        }

        // define streams
        auto inputStream = tapasco::makeInputStream(input.data(), input.size() * sizeof(float));
        auto outputStream = tapasco::makeOutputStream(output.data(), output.size() * sizeof(float));
        unsigned int cycles = 0;
        tapasco::RetVal<unsigned int> ret(&cycles);

        // launch PE task
        std::cout <<  "Launch PE task" << std::endl;
        auto start = std::chrono::high_resolution_clock::now();
        auto task = tap.launch(peId, ret, inputStream, outputStream, num_samples);

        // wait for PE completion
        task();
        auto end = std::chrono::high_resolution_clock::now();

        // check results
        std::cout <<  "Check results" << std::endl;
        bool error = false;
        for (size_t i = 0; i < num_samples; ++i) {
                float x = input[i * 2];
                float y = input[i * 2 + 1];
                float ref = expect_scale * std::sqrt(x * x + y * y);

                float diff = std::fabs(ref - output[i]);
                if (diff > ref * 1e-5) {
                        std::cout << "ERROR: Wrong result at index " << i << ": ";
                        std::cout << output[i] << "(act) vs. " << ref << " (ref)" << std::endl;
                        error = true;
                }
        }

        if (error)
                std::cout << "ERROR: Result contains false values, test run failed" << std::endl;
        else
                std::cout << "SUCCESS: Test run completed without errors" << std::endl;

        // print runtimes
        std::chrono::duration<double> dur = end - start;
        std::cout << "Host runtime: " << dur.count() << " s" << std::endl;
        double accRuntime = cycles / (tap.design_frequency() * 1e6);
        std::cout << "Accelerator runtime: " << accRuntime << " s" << std::endl;

        return 0;
}
