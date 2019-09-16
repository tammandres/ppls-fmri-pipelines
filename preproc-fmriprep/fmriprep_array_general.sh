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

# Identify all subject folders
#   For example, if subject folders are named "sub-03", "sub-04" and "sub-05",
#   then "folders" is an array that contains values "./sub-03", "./sub-04", "./sub-05"
cd ${dpath}
shopt -s globstar
folders=(./sub*)
echo "Subject folders are: ${folders[@]}"

# Get an index value of the subject's folder to be processed
#   The "SGE_TASK_ID" variable takes one of the values in a range you specified after "qsub -t" command
#   If you specified "qsub -t 1-5", it will run the script five times, taking a value 1, 2, 3 ... each time.
#   The "idx" variable is the index of the first, second etc folder in the "folders" variable.
#   For example, if "SGE_TASK_ID" takes a value 1, it means you need the index of the first folder,
#   and that is equal to 0. The index of the second folder is 1, index of third is 2 etc.
idx=`expr $SGE_TASK_ID - 1`
echo "Index of current folder is: ${idx}"

# Using the index of the current folder, extract it from the "folders" array
# Then drop first six characters to get subject's label, because elements in the "folders" array are
# "./sub-03", "./sub-04" etc, but you need "03", "04" etc.
lab=${folders[idx]}
lab=${lab:6}
echo "Subject label corresponding to current folder is: ${lab}"

# Create a directory where fmriprep temporary files will be saved
tpath=${wpath}/tmp$lab

# Create output folder and temporary files folder
mkdir ${opath}
mkdir ${tpath}

# Call fmriprep
udocker run -v ${dpath}:/in -v ${opath}:/out -v ${fpath}:/fs -v ${tpath}:/work fprep /in /out participant --participant-label ${lab} --fs-no-reconall --fs-license-file /fs/license.txt -w /work --dummy-scans 0 --skip_bids_validation