#!/bin/sh
# NB - edit this file only on Linux environment, or in Windows using Notepad++

# Initialise the environment modules
. /etc/profile.d/modules.sh
 
# Load matlab
module load matlab/R2018a

# Path to code folder
# NB. Must start with "/"
codepath=/exports/eddie/scratch/[userName]/[studyFolder]/code

# Specify names of scripts to be called
p8="p8_normsmooth_dartel.m"

# Add the code folder to matlab search path
# This is necessary so that matlab scripts can find the 'paths.mat' file
export MATLABPATH=${codepath}

# Call the scripts in a sequence
matlab -nodesktop < ${codepath}/${p8}