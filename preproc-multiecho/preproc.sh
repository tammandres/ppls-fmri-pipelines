#!/bin/sh
# NB. Edit this file only on Linux environment, or in Windows using Notepad++

# Initialise the environment modules
. /etc/profile.d/modules.sh
 
# Load MATLAB and Python
module load matlab/R2018a
module load roslin/python/3.5.5

#---------------------------------
# Input
#---------------------------------

# Specify path that will contain the virtual environment folder (same as your study folder)
# NB. Must start with "/" and there must be no white spaces before and after "=" sign
vpath=/exports/eddie/scratch/[userName]/[studyFolder]

# Specify path to code folder (the scripts need to be run from code folder so that they find "paths.mat" file)
# NB. Must start with "/" and there must be no white spaces before and after "=" sign
codepath=/exports/eddie/scratch/[userName]/[studyFolder]/code

#---------------------------------
# Prepare the Python virtual environment
#---------------------------------

# Install packages in a virtual environment called "tedana-venv"
cd ${vpath}                               # Go to the folder that contains the virtual environment
python -m venv tedana-venv                # Create the virtual environment
source ${vpath}/tedana-venv/bin/activate  # Activate the virtual environment
python -m pip install --upgrade pip       # Upgrade pip
python -m pip install nilearn==0.5.2      # Install nilearn
python -m pip install tedana==0.0.7       # Install tedana
python -m pip install nibabel==2.4.1      # Install nibabel
#python -m pip install https://github.com/ME-ICA/tedana/archive/master.zip

#---------------------------------
# Run the scripts
#---------------------------------

# Activate the virtual environment
source ${vpath}/tedana-venv/bin/activate

# Add the code folder to MATLAB search path (necessary for MATLAB scripts to find the 'paths.mat' file)
# And set the code folder as the current directory (necessary for Python scripts to find the 'paths.mat')
export MATLABPATH=${codepath}
cd ${codepath}

# Set names of scripts to be called
p1="p1_func.m"
p2="p2_gmwm.m"
p3="p3_tedana_mask.py"
p4="p4_tedana_main.py"
p5="p5_tedana_reorder.py"
p6="p6_unwarp.m"
p7="p7_anat.m"
#p8="p8_normsmooth.m"

# Call the scripts in a sequence
matlab -nodesktop < ${codepath}/${p1}
matlab -nodesktop < ${codepath}/${p2}
python ${codepath}/${p3}
python ${codepath}/${p4}
python ${codepath}/${p5}
matlab -nodesktop < ${codepath}/${p6}
matlab -nodesktop < ${codepath}/${p7}
#matlab -nodesktop < ${codepath}/${p8}
