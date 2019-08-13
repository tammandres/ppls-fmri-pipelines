#--------------------
# MULTI ECHO PREPROCESSING: Reorganise outputs of the TE-dependent analysis (tedana)
#
# NB. Image folders must be organised according to the BIDS 1.2.0 format
#     https://bids-specification.readthedocs.io/en/stable/
#
# Input
#  - TE-dependent analysis outputs in a folder '/sub-[X]/func/tedana_run-[X]'
#  - 'paths.mat' file that contains folder paths and some other relevant
#    variables, created by the 'step1_prepareEnvironment*.m' script
#
# Main outputs
#  - A renamed copy of the optimal combination of echos and denoised optimal
#    combination in 'sub-[X]/func/' folder, named by default as
#    'rasub-[X]_task-[X]_run-[X]_echo-[oc,dnoc]_bold.nii'
#  - Data type of all tedana outputs larger than 100 mb changed to 'int16'
#    to conserve disk space.
# 
# Method
#  - Data type of tedana outputs is changed using functions from Nibabel. 
#    This method was chosen due to its speed. 
#  - When data type of images is being changed in a particular tedana output folder,
#    as many images are processed in parallel as the number of computer cores.
#    Currently, the number of cores is set to 1 to avoid potential memory issues,
#    and the line of code that detects the number of cores is commented in.
#
# Software : Python 3.5.5, nibabel 2.4.1 package
#--------------------

#----------
# Preparations
#----------

# Import packages
import scipy.io
import os
import glob
import numpy as np
import nibabel as nib
import re
import multiprocessing as mp
from shutil import copyfile
import time

# Load objects in "paths.mat" file to Python environment
# For testing locally, go to code folder before: os.chdir("Z:\\E182021_Semantic-encoding\\code")
paths = scipy.io.loadmat('paths.mat')

# Get path to derivatives folder
# Or set it manually: work_path = "Z:\\E182025_Speak-listen\\tmp"
work_path = paths["work_path"][0]

# Get image prefixes
rprefix = paths["rprefix"][0]
sprefix = paths["sprefix"][0]

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
# For testing, type j = 0
for j in range(0, nsub):
	
    # Subject ID
    subj = subj_list[j]
    
    # Start counting time
    start_time = time.time()
    
    # Message
    print(subj + ": Reordering tedana files")
    
    # Path to functional image folder for current subject
    func_path = os.path.join(work_path, subj, 'func')

    # Identify tedana folders
    os.chdir(func_path)
    t = glob.glob('tedana*')
    nt = len(t)
 
    # Loop over tedana folders, for testing use k = 0
    for k in range(0, nt):
        
        # Message
        print(subj + ": Changing data type of tedana outputs to int16 and renaming files for output folder: " + t[k])
        
        # Get path to the k'th tedana folder and go there
        tpath = os.path.join(func_path, t[k])
        os.chdir(tpath)
        
        # Extract task and run label from tedana folder name
        taskrunlabel = re.findall("task-.*run-\d{1,2}", t[k])
        taskrunlabel = taskrunlabel[0]

        # Identify images with size greater than 100 mb
        f = glob.glob('*.nii')
        f = np.array(f)
        sizes = [0]*len(f)
        sizes = np.array(sizes)
        for m in range(0, len(f)):
            sizes[m] = os.path.getsize(f[m])/10**6
        f = f[sizes > 100]
        
        # Change data type
        #for m in range(0, len(f)):
        def change_dtype(imgname):
            
            # Message
            print("Changing data type of: " + imgname)
            
            # Load the image
            img = nib.load(imgname)

            # Get data
            data = img.get_data()
            
            # Change data type of data
            dtype = np.int16
            data.astype(dtype)
            img.set_data_dtype(dtype)
            
            # Create a new image with changed data type and save it
            imgnew = nib.Nifti1Image(data, img.affine, img.header)
            tmp = "tmp_" + imgname
            nib.save(imgnew, tmp)
            
            # Unload the loaded files
            img = []
            data = []
            imgnew = []
            
            # Remove the original image and replace with changed image
            os.remove(imgname)
            os.rename(tmp, imgname)
        
        # Change data type in parallel loop
        #ncores = mp.cpu_count()
        ncores = 1
        p = mp.Pool(processes=ncores)
        p.map(change_dtype, f)
        p = []
        
        # Generate new image names, using old names as basis
        # Note that previously, I simply generated names with adding up labels :
        #f_oc = rprefix + sprefix + subj + "_" + taskrunlabel + "_echo-oc_bold.nii"
        #f_dnoc = rprefix + sprefix + subj + "_" + taskrunlabel + "_echo-dnoc_bold.nii"
        # But this does not capture any special labels added to image names, such as "desc-"
        # Therefore, I am first extracting names of all echo-1 preprocessed images
        # And then pick out the name of the image that contains the desired task-run combination
        # And then replace "echo-1" with "echo-oc" or "echo-dnoc" to generate name
        os.chdir(func_path)
        f = glob.glob(rprefix + sprefix + subj + '*echo-1*.nii')
        f = np.array(f)
        tmp   = [re.search(taskrunlabel, x) for x in f]
        tmp   = np.array(tmp)
        fname = f[tmp != None][0]
        f_oc   = re.sub("echo-1", "echo-oc", fname)
        f_dnoc = re.sub("echo-1", "echo-dnoc", fname)
        
        # Copy and rename dn_ts_OC and ts_OC images
        os.chdir(tpath)
        path_oc = os.path.join(func_path, f_oc)
        path_dnoc = os.path.join(func_path, f_dnoc)
        copyfile("ts_OC.nii", path_oc)
        copyfile("dn_ts_OC.nii", path_dnoc)
    
    # Message
    print(subj + ": Changing data type of tedana outputs to int16 and renaming files completed.")
    
    # Print time taken
    time_taken = time.time() - start_time
    tmin = str(round(time_taken/60, 2))
    th   = str(round(time_taken/3600, 2))
    print(subj + ": p5_tedana_reorder took " + tmin  + " minutes = " + th + " hours")
