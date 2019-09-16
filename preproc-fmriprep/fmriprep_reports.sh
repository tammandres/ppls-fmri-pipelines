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
opath=/exports/eddie/scratch/atamm2/emotion/out          # folder where fMRIPrep outputs will be saved
wpath=/exports/eddie/scratch/atamm2/emotion/             # folder where fMRIPrep temporary folders were created

# List the labels of all subjects (with leading zeros IF these are included in the subject label) in an array
labs=(01 02 03 04 05 06 07 08 09 10)
#---------------------------------------------------------------------------

# Loop over subjects, calling fMRIPrep separately for each subject
for i in ${labs[@]}
do
tpath=${wpath}/tmp${i}
mkdir ${tpath}
udocker run -v ${dpath}:/in -v ${opath}:/out -v ${fpath}:/fs -v ${tpath}:/work fprep /in /out participant --participant-label ${i} --fs-no-reconall --fs-license-file /fs/license.txt -w /work --dummy-scans 0 --skip_bids_validation --reports-only
done

