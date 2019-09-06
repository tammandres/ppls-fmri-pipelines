#--------------------
# MULTI ECHO PREPROCESSING: TE-dependent analys (tedana)
# 
# NB. Image folders must be organised according to the BIDS 1.2.0 format
#     https://bids-specification.readthedocs.io/en/stable/
#
# Input
#  - Combined analysis mask (grey and white matter + EPI mask), created
#    by the 'p3_tedana_mask*.py' script, named as 'sub-[X]_mask-comb_spm.nii'
#  - Slice time and motion corrected 4D time series of functional images,
#    containing at least two different echos.
#  - 'paths.mat' file that contains folder paths and some other relevant
#    variables, created by the 'step1_prepareEnvironment*.m' script
#
# Main outputs
#  - Optimal combination of echos and denoised optimal combination
#    in 'sub-[X]/func/tedana_task-[X]_run-[X]' folder, named as 'ts_OC.nii' 
#    and 'dn_ts_OC.nii', respectively
#  - Diagnostic plots in 'sub-[X]/func/tedana_run-[X]/figures' folder
# 
# Method
#  - TE-dependent analysis (tedana) is run in the combined analysis mask,
#    using a small number of maximum iterations (500) with 15 maximum restarts.
#    This is based on the observation that tedana tends to converge fast
#    but is sensitive to starting values.
#  - This script first creates an array of strings: each string is a call 
#    to the tedana algorithm for a specific subject and specific task-run combination.
#    If that string was copied to the terminal, tedana would be executed
#    with the parameters specified in the string.
#  - The script then executes these calls in parallel, with the number of
#    parallel calls equal to the number of computer cores.
#
# Author   : Andres Tamm
# Software : Python 3.5.5, tedana 0.0.7 package
#--------------------

#----------
# Preparations
#----------

# Import packages
import scipy.io
import tedana
import os
import glob
import re
import numpy as np
import multiprocessing as mp
import time

# Start counting time
start_time = time.time()

# Load objects in "paths.mat" file to Python environment
# For testing locally, go to code folder before: os.chdir("Z:\\E182021_Semantic-encoding\\code")
paths = scipy.io.loadmat('paths.mat')

# Get path to derivatives folder
# Or set it manually: work_path = "Z:\\E182013_Sentence-code\\tmp\\derivatives\\"
work_path = paths["work_path"][0]

# Get echo times
# Or set it manually: echotimes = "13.00 31.26 49.52"
echotimes = paths["echotimes"][0]

# Specify iteration settings for tedana
maxit = 500       # Maximum number of iterations
maxrestart = 15   # Maximum number of restarts if tedana does not converge in maximum number of iterations

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
# Create a list of tedana calls that need to be made
# Each subject has multiple calls: one call per task-run combination
# For example, if sub-01 has 'task-sentence_run-1', 'task-sentence_run-2',
# and 'task-nback_run-1', there will be three tedana calls for that subject
#----------

# Loop over subjects to create tedana calls
# To test the loop, type j = 0
#tedcall = [""]*nsub
tedcall = []
for j in range(0, nsub):
    
    # Subject ID
    subj = subj_list[j]
    
    # Message
    print("Getting tedana calls for subject: " + subj)
    
    # Path to functional image folders for current subject
    func_path = os.path.join(work_path, subj, 'func')
    
    # Path to tedana mask
    mask = os.path.join(func_path, subj + "_mask-comb_spm.nii")
    
    # Get paths to images and sort alphabetically
    # This ensures that images from each task-run combination
    # are in ascending order with respect to echo number
    # This is because echo time field follows task and run fields in image file names
    os.chdir(func_path)
    imgs = glob.glob('rasub*nii')
    imgs = np.asarray(imgs)
    imgs = np.sort(imgs)
    n = len(imgs)
    
    # Filter out optimal combinations of echos (useful if rerunning the script)
    ridx = [0]*n
    ridx = np.array(ridx)
    for i in range(0, n):
        tmp = re.search("echo-\d", imgs[i])
        if tmp:
            ridx[i] = 1
        else:
            ridx[i] = 0
    imgs = imgs[ridx == 1]
    n = len(imgs)
    
    # Create an index for task-run combinations 
    # and identify the number of such combinations
    # To test the loop, use i = 0
    taskrunvalues = [""]*n
    taskrunvalues = np.array(taskrunvalues, dtype = object)
    for i in range(0, n):
        image = imgs[i]
        tmp = re.findall("task-.*run-\d{1,2}", image)
        tmp = tmp[0]
        taskrunvalues[i] = tmp
    taskrunlevels, taskrunindex = np.unique(taskrunvalues, return_inverse=True)   
    ntaskrun = len(set(taskrunindex))

    # Convert filenames to filepaths
    tmp = [""]*n
    for i in range(0, n):
        tmp[i] = os.path.join(func_path, imgs[i])
    tmp = np.array(tmp)
    imgs = tmp
 
    # Get images for each task-run combination in a string
    # To test use i = 0
    imgtaskrun = [""]*ntaskrun
    for i in range(0, ntaskrun):
        tmp = imgs[taskrunindex == i]
        tmp = np.array2string(tmp, separator = " ", max_line_width = 10**10)
        tmp = re.sub("'", "", tmp)  # remove single quotes
        tmp = re.sub("[\[\]]", "", tmp)  # remove start and end brackets
        imgtaskrun[i] = tmp
    
    # Get output folders for each run
    out = [""]*ntaskrun
    for i in range(0, ntaskrun):
        fname = "tedana_" + taskrunlevels[i]
        out[i] = os.path.join(func_path, fname)
    
    # Create tedana calls for this subject
    t = [""]*ntaskrun
    for i in range(0, ntaskrun):
        s1 = "tedana -d " + imgtaskrun[i] + " -e " + echotimes +  " --mask " +  mask
        s2 = " --maxit " + str(maxit) + " --maxrestart " + str(maxrestart)
        s3 = " --out-dir " + out[i] + " --png"
        s = s1 + s2 + s3
        t[i] = s  
    
    # Store the subject's tedana calls
    #tedcall[j] = t
    tedcall = tedcall + t

# Gather the tedana calls of all subjects in the same level of the array
#tedcall = np.ravel(tedcall)   
ncall = len(tedcall)
print("Total number of tedana calls for these subjects is: " + str(ncall))

# Call tedana in a parallel loop
ncores = mp.cpu_count()
print("Number of computer cores is: " + str(ncores))
print("Echo times are: " + echotimes)
print("Calling tedana with one call per core")
p = mp.Pool(processes=ncores)
p.map(os.system, tedcall)

# For a non-parallel loop, can use:
#for j in range(0, ncall)
#    os.system(tedcall[j])

# Print time taken
time_taken = time.time() - start_time
tmin = str(round(time_taken/60, 2))
th   = str(round(time_taken/3600, 2))
print("For all processed subjects, p4_tedana_main took " + tmin  + " minutes = " + th + " hours")
    
    
    
    
    
