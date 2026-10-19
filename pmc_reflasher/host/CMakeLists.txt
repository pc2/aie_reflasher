cmake_minimum_required(VERSION 3.25 FATAL_ERROR)
set(CMAKE_CXX_STANDARD 20)

project(reflash-aie)

find_package(Threads)
find_package(Tapasco REQUIRED)

add_executable(reflash-aie reflash_aie.cpp)
target_include_directories(reflash-aie PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../common)
target_link_libraries(reflash-aie tapasco ${CMAKE_THREAD_LIBS_INIT})

add_executable(reflash-aie-pe reflash_aie_pe.cpp)
target_link_libraries(reflash-aie-pe tapasco ${CMAKE_THREAD_LIBS_INIT})

add_executable(reflash-aie-direct reflash_aie_direct.cpp)
target_include_directories(reflash-aie-direct PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../common)
target_link_libraries(reflash-aie-direct tapasco ${CMAKE_THREAD_LIBS_INIT})

add_executable(reflash-aie-loader reflash_aie_loader.cpp)
target_link_libraries(reflash-aie-loader tapasco ${CMAKE_THREAD_LIBS_INIT})
