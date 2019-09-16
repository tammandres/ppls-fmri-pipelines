#!/bin/sh
# NB. Edit this file only on Linux environment, or in Windows using Notepad++
# This script loops over 

#---------------------------------------------------------------------------
# INPUT SECTION

# Specify paths to your data folder on the cluster
# It should contain the folders of each subject, e.g. sub-01, sub-02, ...
dpath=/exports/eddie/scratch/atamm2/emotion/derivatives  # data folder (contains data of all subjects)
#---------------------------------------------------------------------------

# Identify all subject folders
#   For example, if subject folders are named "sub-03", "sub-04" and "sub-05",
#   then "folders" is an array that contains values "./sub-03", "./sub-04", "./sub-05"
cd ${dpath}
shopt -s globstar
folders=(./sub*)
echo "Subject folders are: ${folders[@]}"

# Loop over subject folders, deleting the "...events.json" files from "func" folder
for i in "${folders[@]}"
do
# Get subject's ID
sub=${i:2}
echo "**Processing subject: "$sub

# Get path to functional images folder
fpath=${dpath}/${sub}/func

# Go to the folder and delete "events.json" file
cd ${fpath}
rm -f *events.json
done