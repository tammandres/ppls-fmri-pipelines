#---------------------------------
# MULTI ECHO PREPROCESSING: Get brain mask for TE-dependent analysis (tedana)
# 
# NB. Image folders must be organised according to the BIDS 1.2.0 format
#     https://bids-specification.readthedocs.io/en/stable/
#	
# Input
#  - Grey and white matter mask, created by the p1_func*.m script and named as
#    'sub-[X]_mask-gmwm_space-epi_spm.nii'
#  - Slice time and motion corrected 4D echo-1 functional images, named as
#    'rasub-[X]_task-[X]_run-[X]_echo-1_bold.nii'
#  - 'paths.mat' file that contains folder paths and some other relevant
#    variables, created by the 'step1_prepareEnvironment*.m' script
#
# Main outputs
#  - A mask in the space of the preprocessed functional images that combines
#    an EPI mask with grey and white matter mask, named as
#    'sub-[X]_mask-comb_spm.nii'. TE-dependent analysis is later conducted
#    inside that mask.
# 
# Method
#  - A mask based on preprocessed echo-1 functional images ("EPI mask") 
#    is computed using compute_epi_mask() from Nilearn
#  - That mask is added to a previously created grey-plus-white matter mask,
#    using math_img() from Nilearn
#
# Note
#  - Grey-and-white matter mask tends to offer a better coverage of ventral
#    and anterior temporal lobes than an EPI mask alone. Hence, we combined
#    that mask with an EPI mask.
#
# Author   : Andres Tamm
# Software : Python 3.5.5, Nilearn 0.5.2 package
#---------------------------------

#----------
# Preparations
#----------

# Import packages
import scipy.io
import os
import glob
import time
from nilearn.masking import compute_epi_mask
from nilearn.image import load_img
from nilearn.image import math_img

# Load objects in "paths.mat" file to Python environment
# For testing locally, go to code folder before: os.chdir("Z:\\E182021_Semantic-encoding\\code")
paths = scipy.io.loadmat('paths.mat')

# Get path to derivatives folder
# Or set it manually: work_path = "Z:\\E182013_Sentence-code\\tmp\\derivatives\\"
work_path = paths["work_path"][0]

#----------
# Get subject folders that need to be processed
#----------

# Set derivatives as the current directory
os.chdir(work_path)

# Identify all subject folders that are available
subj_list = glob.glob('sub*')

# If you want to run the script for a subset of subjects
# Load subject IDs from the 'code_paths.mat' file
# OR specify subject IDs manually: subj_list = ['sub-01', 'sub-03', 'sub-04']
mode = paths["mode"][0]
if mode == "subset":
    subs = paths["subs"]
    subj_list = [0]*len(subs)
    for i in range(0, len(subs)):
        subj_list[i] = subs[i][0][0]

# Check subject folders
print("Subjects to be processed are:")
print(subj_list)

# Identify the number of subjects
nsub = len(subj_list)

#----------
# Process the folder of each subject
#----------

# Loop over subjects
# For testing, use subj = subj_list[0]
for subj in subj_list:
    	
    # Message
    print(subj + ": Creating mask for tedana")
    
    # Start counting time
    start_time = time.time()
    
    # Path to folders for current subject
    func_path = os.path.join(work_path, subj, 'func')
    anat_path = os.path.join(work_path, subj, 'anat')
    
    # Go to the functional images folder
    os.chdir(func_path)
    
    # Get names of func images to be used for mask
    imgs = glob.glob('rasub*echo-1_bold.nii')

    # Compute EPI mask
    mask_epi = compute_epi_mask(imgs, verbose=1)
    
    # Save EPI mask
    fname = subj + '_mask-epi.nii'
    mask_epi.to_filename(fname)
    
    # Path to grey plus white matter mask
    img_gmwm = os.path.join(anat_path, subj + '_mask-gmwm_space-epi_spm.nii')
    
    # Load gmwm mask
    mask_gmwm = load_img(img_gmwm)
     
    # Combine EPI mask with grey and white matter masks
    mask_comb = math_img("x + y > 0", x=mask_epi, y=mask_gmwm)
    
    # Save
    fname = subj + '_mask-comb_spm.nii'
    mask_comb.to_filename(fname)
    
    # Print time taken
    time_taken = time.time() - start_time
    tmin = str(round(time_taken/60, 2))
    th   = str(round(time_taken/3600, 2))
    print(subj + ": p3_tedana_mask took " + tmin  + " minutes = " + th + " hours")
	
