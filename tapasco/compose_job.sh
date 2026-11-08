#!/bin/bash
# SLURM job (pc2): `make bitstream`, the Tapasco compose of DataStreamerVN + AIEPdiLoader with the AI-Engine,
# DMA-Streaming and PDI-Loader features. Submit from the repository root: `sbatch tapasco/compose_job.sh`.
#SBATCH -J aie_reflasher_compose
#SBATCH -A pc2-mitarbeiter
#SBATCH -p largemem
#SBATCH -q fpgasynthesis
#SBATCH -t 08:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem-per-cpu=8G
#SBATCH -o logs/%x-%j.out
set -eo pipefail   # no -u: tapasco-setup.sh appends to unset variables
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")/..}"
source vck5000_modules.sh
make bitstream
