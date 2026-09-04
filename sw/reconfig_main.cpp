#include <iostream>

#include <chrono>
#include <string>
#include <tapasco.hpp>
#include <fstream>

#define PE_NAME "esa.informatik.tu-darmstadt.de:user:AIEngineReflasher:1.0"

int main(int argc, char **argv) {
        const char* reconfig_file_path = argv[1];
        std::ifstream file(reconfig_file_path, std::ios::binary | std::ios::ate);
        std::streamsize size = file.tellg();

        file.seekg(0, std::ios::beg);

        std::vector<uint8_t> reflash_buffer(size);
        if (!file.read(reinterpret_cast<char*>(reflash_buffer.data()), size))
        {
                std::cerr << "Could not read the file data" << std::endl;
                exit(1);
        }

        if(size % 4 != 0) {
                std::cerr << "File size isn't a multiple of 4????" << std::endl;
                exit(1);
        }
        size_t num_elements = size / 4 - 5;
        // Skip header
        uint8_t* reflash_data = reflash_buffer.data() + sizeof(uint32_t) * 5;

        // instantiate Tapasco (assume only one FPGA connected to this host)
        tapasco::Tapasco tap;
        tapasco::PEId peId = tap.get_pe_id(PE_NAME);

        // define streams
        
        constexpr size_t HM_ADDR = 0;
        tap.copy_to(reflash_data, HM_ADDR, num_elements * 4);


        unsigned int cycles = 0;
        tapasco::RetVal<unsigned int> ret(&cycles);

        // launch PE task
        std::cout <<  "Launch PE task" << std::endl;
        auto start = std::chrono::high_resolution_clock::now();
        auto task = tap.launch(peId, ret, HM_ADDR, num_elements);

        // wait for PE completion
        task();
        auto end = std::chrono::high_resolution_clock::now();

        // print runtimes
        std::chrono::duration<double> dur = end - start;
        std::cout << "Done reflashing. Host runtime: " << dur.count() << " s" << std::endl;

        return 0;
}
