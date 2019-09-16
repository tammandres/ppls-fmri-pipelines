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

# Specify the label of the subject for whom to run fmriprep
# E.g., 01 for sub-01, p3 for sub-p3, 02 for sub-02 and so on
labs=01
#---------------------------------------------------------------------------

# Create path to folder where fMRIprep temporary files will be stored
# E.g. tmp01 if subject label is 01
tpath=${wpath}/tmp${labs}

# Create output folder and temporary folder
mkdir ${opath}
mkdir ${tpath}

# Ca
udocker run -v ${dpath}:/in -v ${opath}:/out -v ${fpath}:/fs -v ${tpath}:/work fprep /in /out participant --participant-label ${labs} --fs-no-reconall --fs-license-file /fs/license.txt -w /work --dummy-scans 0 --skip_bids_validation