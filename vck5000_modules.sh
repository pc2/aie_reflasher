#!/bin/bash

module reset

## Modules for AIE development
ml fpga xilinx/vck5000 xilinx/vitis/23.1 xilinx/vivado/23.1 devel/CMake/3.31.8-GCCcore-14.3.0
export XILINXD_LICENSE_FILE=27000@kiso.uni-paderborn.de
export LM_LICENSE_FILE=27000@kiso.uni-paderborn.de

export TAPASCO_PLATFORM=pcie
export PLATFORM_FILE=/opt/software/FPGA/Xilinx/Vitis/2023.1/base_platforms/xilinx_vck190_base_202310_1/xilinx_vck190_base_202310_1.xpfm

# source ~/mitarbeiter/tapasco-workdir/tapasco-setup.sh
source /tmp/tapasco_workdir/tapasco-setup.sh
