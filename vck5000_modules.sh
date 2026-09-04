#!/bin/bash

module reset

## Modules for AIE development
ml fpga xilinx/vck5000 xilinx/vitis/23.1
export XILINXD_LICENSE_FILE=27000@kiso.uni-paderborn.de
export LM_LICENSE_FILE=27000@kiso.uni-paderborn.de


source ~/mitarbeiter/tapasco-workdir/tapasco-setup.sh
