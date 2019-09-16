#!/bin/sh
# NB. If you edit this file on Windows, use Notepad++ 
#     or be careful not to create any new line breaks
# Replace "atamm2" with your university username
# Replace "emotion" with the name of your study folder on the cluster

# Initialise the environment modules
. /etc/profile.d/modules.sh

# Load Python to use udocker (udocker is already installed under that Python installation)
module load igmm/apps/python/2.7.10

#---------------------------------------------------------------------------
# INPUT SECTION

# Change udocker directory to scratch (instead of default home)
export UDOCKER_DIR=/exports/eddie/scratch/atamm2/udockernew

# Specify paths to code, BIDS and output folders
fpath=/exports/eddie/scratch/atamm2/emotion/code         # folder that contains FreeSurfer license file
dpath=/exports/eddie/scratch/atamm2/emotion/derivatives  # data folder (contains data of all subjects)
opath=/exports/eddie/scratch/atamm2/emotion/out          # folder where fmriprep outputs will be saved
wpath=/exports/eddie/scratch/atamm2/emotion/             # folder where fMRIPrep temporary folders will be created
#---------------------------------------------------------------------------

# Get subject's number (e.g. 1, 2, 3, ...)
num=$SGE_TASK_ID

# Get subject's label (e.g. 01, 02, 03, ...)
# Difference from subject's number is that integers below 10 are padded with a zero
# This seems to be necessary for fmriprep to correctly recognize subject number
lab=$(printf "%02d\n" $num)

# Create a directory where fmriprep temporary files will be saved
# For example, if subject label is "01", that folder is named "tmp01"
tpath=${wpath}/tmp$lab

# Create output folder and temporary files folder
mkdir ${opath}
mkdir ${tpath}

# Call fmriprep
udocker run -v ${dpath}:/in -v ${opath}:/out -v ${fpath}:/fs -v ${tpath}:/work fprep /in /out participant --participant-label ${lab} --fs-no-reconall --fs-license-file /fs/license.txt -w /work --dummy-scans 0 --skip_bids_validation