#!/bin/bash
#SBATCH -p stdmemq
#SBATCH -J jopt-test
#SBATCH -o jopt-test-%j
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=40
#SBATCH --export=ALL
#SBATCH -t 02:00:00

set echo

umask 0027

../../runorca.sh -i rimp2-opt.inp 
