# Multi-echo fMRI preprocessing on a computer cluster
This is a multi-echo fMRI preprocessing pipeline that uses Python's [TE-dependent analysis package (tedana)](https://tedana.readthedocs.io/en/latest/usage.html) to optimally combine the data across echos and to decompose it into BOLD and non-BOLD components. Other preprocessing steps are mainly accomplished with the [SPM12 MATLAB toolbox](https://github.com/spm/spm12). This workflow is designed to be run on the Eddie3 computer cluster at the University of Edinburgh. However, the preprocessing scripts that are called on the cluster are not specific to Eddie3 and can be used elsewhere.

## How the scripts work

* The scripts that accomplish specific preprocessing stages are
  - `p1_func`: performs slice timing and motion correction with SPM12.
  - `p2_gmwm`: creates a grey-plus-white matter mask in the space of functional images with SPM12.
  - `p3_tedana_mask`: creates a brain mask for TE-dependent analysis. It first creates a mask based on BOLD images using the [Nilearn](https://nilearn.github.io/index.html) Python package, then combines it with the previously created grey and white matter mask.
  - `p4_tedana_main`: TE-dependent analysis with the tedana Python package. This script takes preprocessed BOLD images of individual echos as input and outputs an optimal combination of echos and denoised optimal combination of echos for each BOLD time series.
  - `p5_tedana_reorder`: changes the datatype of TE-dependent analysis outputs to "int16" with [nibabel](https://nipy.org/nibabel/) Python package to conserve disk space, copies relevant outputs to the BOLD images folder, and renames them.
  - `p6_unwarp`: performs distortion correction for preprocessed images with SPM12.
  - `p7_anat`: coregisters the anatomical T1 image to median preprocessed BOLD image and segments its using SPM12. This is a necessary step for spatially normalising the functional images.
  - `p8_normsmooth_dartel`: spatially normalises BOLD images to MNI space and smooths them using SPM's DARTEL.
* The scripts from "p1" to "p7" are called on the computer cluster by the "preproc.sh" script, and the "p8_normsmooth_dartel" is called by the "preproc_dartel.sh". The DARTEL script is not called by "preproc.sh", because it requires the data of all subjects to be processed. See comments in the individual scripts and the methods section below for more information on what the scripts do.
* Before running the scripts on the cluster, the brain imaging data need to be tidied up and scripts need to be set up. This is accomplished by the "step" scripts:
  - `step1_prepareImages`: takes raw imaging data as input and outputs a tidied data set in BIDS format. In addition to renaming images, it updates the .json metadata files of fieldmap phase difference images and functional images and removes dummy scans from each 4D BOLD image.
  - `step1_getEvents`: creates ["task events"](https://bids-specification.readthedocs.io/en/stable/04-modality-specific-files/05-task-events.html) files that describe timings and other properties of the behavioural task in BIDS format. This script is currently not provided: each study will have a different script depending on the format of their behavioural data files. Note that this step is only for making the BIDS-formatted data set complete, it is not necessary for preprocessing itself. The timings in task events files will be used after preprocessing. 
  - `step1_prepareEnvironment`: creates a "paths.mat" file that contains file paths and settings that the preprocessing scripts need in order to run.
* For more information, see comments inside individual scripts and read the methods section below.
## How to use the scripts

### 1. Prepare your data and scripts

* **Create a "code" folder inside your local study folder**. Download the scripts by going to the main page of the "PPLS-fMRI-pipelines" GitHub repository and choosing "Clone or download". Unzip the file and copy the scripts "p1", "p2" etc into the "code" folder. Also download the DICOM to NIfTI converter "dcm2niix" from https://github.com/rordenlab/dcm2niix/releases and copy "dcm2niix.exe" to your "code" folder. If you already have a "code" folder inside your study folder, you may want to create a copy of it (such as "code_myname"), as otherwise you may run into file access and permission issues.
* **Run the "step1_prepareImages.m" script in MATLAB on your computer.** It takes in the raw imaging data and transforms it into a tidy data set in BIDS format. It creates a "BIDS" folder in your study folder that contains the tidy data, and a "derivatives" folder that contains a copy of the tidy data.
  * In the input section of the script, you need to specify **a path to your study folder** (where the tidy data will be saved), **a path to your code folder**, **a path to the SPM folder**, and **paths to raw image folders of all subjects** that you are running the script for. All these folders are usually on a network share, so paths to these folders are UNC paths, such as "\\\chss.datastore.ed.ac.uk\\...\\rootFolder\yourStudyFolder". I recommend mapping the path that contains your study folder to a drive letter, such as "Z". For example, the UNC path given above will then simply become "Z:\yourStudyFolder". Similarly, I recommend mapping the path that contains your raw study folder (usually on the imaging centre's drive) to another drive letter, such as "Y". The path to your raw image folder (that contains image folders for all subjects) will then become "Y:\\yourRawFolder\". You can Google "map a network drive Windows" for more information. For more information, see "Paths to your study folders: Additional information" below.
  
  * In the input section, you also need to specify a "taskLabel" variable. It contains a [task label](https://bids-specification.readthedocs.io/en/stable/04-modality-specific-files/01-magnetic-resonance-imaging-data.html#task-including-resting-state-imaging-data) that will be included in the names of your functional images, for example "sub-01_task-**nback**_run-1_echo-1.nii". If different fMRI runs have different tasks, you can ignore the "taskLabel" variable and specify path to a "taskLabels.txt" file that will contain the task label for each subject and each run. See the input section of the script for more information on the format of that file.
  * In addition, you can specify how many **dummy volumes** to discard ("ndiscard" variable), whether to run **DICOM to NIfTI conversion** ("nifticonv" variable), the **list of subjects** to run the script for ("subjList" variable), and whether to **deface** the images ("deface" variable). See the input section for a full list of variables and comments.
  * This script creates a **"BIDS" folder** inside your study folder that will contain tidied up image folders for all subjects, for example "yourStudyFolder\BIDS\sub-01". It will also create a **"derivatives" folder** that is a copy of the "BIDS" folder. You will be working with the "derivatives" folder, so that if anything goes wrong you have an untouched copy of your original data in the "BIDS" folder.
  * The script will save a **log-file** inside your study folder: "log_step1_prepareImages_[DATE].txt". In addition to logging the steps that the script accomplished, it contains information about the **dimensions of 4D images** (useful if you want to double check that dummy volumes were removed), and a **printout of echo times**. When a script has finished running for a subject, its log file contains a line such as this: "sub-01: step1_prepareImages took 7.4649 minutes = 0.12441 hours".
  * Look into the "qualchecks.xlsx" file for a list of additional quality checks to do: you can check that all image files are there, that 3 dummy volumes were removed, and that no brain tissue was lost after anatomical images were defaced. 
* **Run the "step1_prepareEnvironment.m" script in MATLAB on your computer**. It creates a "paths.mat" file inside your "code" folder that contains settings that the other scripts need in order to run.
   * Specify variables described in the input section of the script. The most important things to specify are **echo times** ("echotimes" variable), **smoothing kernels** ("s"), **blip direction** for fieldmap-based distortion correction ("blipdir"), and **paths to relevant folders on the computer cluster** ("work_path", "spm_path", "code_path"), and **whether to run the scripts for all subjects or a subset** ("mode"). See the input section for more information. Note that you can specify multiple smoothing kernels: in this case, a set of smoothed images will be created for each smoothing kernel. If you are unsure about blip direction, run the scripts for a single subject using both possible blip directions and visually check which gives a better result.
  * The script saves these variables in a "paths.mat" file inside the code folder in your local study folder ("\localStudyFolder\code"). All other preprocessing scripts load the "paths.mat" file and get their settings and file paths from there.
* **Open the "preproc.sh" script** and specify the "vpath" variable (same as path to your study folder on the cluster), and the "codepath" variable (path to the "code" folder inside your study folder on the cluster).
* **(Optional) Run the "step1_getEvents.m" script in MATLAB**. This script creates ["task events"](https://bids-specification.readthedocs.io/en/stable/04-modality-specific-files/05-task-events.html) files that describe timings and other properties of the behavioural task in BIDS format. This script is currently not provided: each study will have a different script depending on the format of their behavioural data files. Note that this step is only for making the BIDS-formatted data set complete, it is not necessary for preprocessing itself. The timings in task events files will be used after preprocessing.

#### Paths to your study folders: additional information

* Windows UNC path to your study folder is most likely:

   `\\chss.datastore.ed.ac.uk\chss\chss\groups\hsscollege-shared\ppls\morcom02\yourStudyFolder`
   
   and Mac UNC path is
   
   `\\chss.datastore.ed.ac.uk\chss\chss\groups\hsscollege-shared\ppls\morcom02\yourStudyFolder`
   
* Similarly, Windows UNC path to the SPM folder is most likely:

   `\\chss.datastore.ed.ac.uk\chss\chss\groups\hsscollege-shared\ppls\morcom02\Shared_resources\spm12`
   
* Note that both your study folder and the SPM folder are contained inside the same "morcom02" folder. I recommend mapping that path to a drive letter, such as "Z". For example, if a full path to your study folder is
  
   `\\chss.datastore.ed.ac.uk\chss\chss\groups\hsscollege-shared\ppls\morcom02\E182025_Speak-listen` 
   
   and you map the path
   
   `\\chss.datastore.ed.ac.uk\chss\chss\groups\hsscollege-shared\ppls\morcom02\` 
   
   to drive letter "Z", then path to your study folder simply becomes "Z:\E182025_Speak-listen", and path to the SPM folder becomes "Z:\Shared_resources\spm12".
   
* You also have a study folder on the brain imaging centre's server. Windows UNC path to that folder is most likely

   `\\cmvm.datastore.ed.ac.uk\cmvm\scs\groups\BRICIA\yourStudyFolder`

   or

   `\\cmvm.datastore.ed.ac.uk\cmvm\scs\groups\CRICIA\yourStudyFolder`

   depending on which brain imaging centre you worked with. You can map the path to a folder that contains your study folder to another drive letter, such as "Y". If your study folder on the imaging centre's server is called "EXXXXXX_SpeakandListen_RO", then path to that study folder simply becomes "Y:\\EXXXXXX_SpeakandListen_RO". 

* Note that the "step1_prepareImages" script requires you to enter a path to the raw image folders for each individual subject. If you have mapped the path to your study folder on the server, then path to the raw folder of subject number 7 can look something like this: 

   ` Y:\EXXXXXX_SpeakandListen_RO\Skyra_fit\07\20190703_100431.698000\\`

   The raw image folders of subject number 7 are actually inside the folder "20190703_100431.698000"; the name of that folder is a timestamp for when the images were collected. The anatomical and functional images are contained in subfolders, for example "...\20190703_100431.698000\5_t1_mprage_sag_p3_iso_Munich" contains the anatomical T1 images and "...\20190703_100431.698000\6_fMRI_PSN_TR_p3_s2_3mm" contains the fMRI images from the first fMRI run. The script requires you to enter the path 

   ` Y:\EXXXXXX_SpeakandListen_RO\Skyra_fit\07\20190703_100431.698000\\`

   for subject number 7, so that it can find the raw image folders for that subject.

### 2. Copy the data and scripts to the computer cluster

- Open a terminal window and connect to the cluster. Replace [userName] with your university user name. If you are using a saved session on MobaXterm, click on that session to achieve the same result. You will be asked for your password:

  `ssh [userName]@eddie3.ecdf.ed.ac.uk`

- Create your study folder and the 'derivatives' folder in the 'scratch' space. Replace [studyFolder] with the name you want to give to your study folder on the cluster (e.g. "semantic"):

  `cd /exports/eddie/scratch/[userName]/`

  `mkdir -p [studyFolder]/derivatives`

- Log in to a data staging node that allows `sftp` connections. **Usually this is not necessary**, but currently it is. The node name is given to you:

  `qlogin -q staging -l h='node2c11'`

- Now connect to DataStore from the cluster using `sftp` and port 22222:

  `sftp -P 22222 [userName]@chss.datastore.ed.ac.uk`

- Then set paths to your study folder on the cluster (a "local" folder as you are starting `sftp` from the cluster), and to your study folder on DataStore (a "remote" folder as you are connecting to it). These folders are not the 'derivatives' folders, but folders that contain the 'derivatives'. If you want to be sure you navigated to correct folders, you can type `lls` to list contents of the local (cluster) folder and `ls` to list contents of the remote (DataStore) folder. Here, path to your DataStore folder is not the same as your mapped network drive: use the template below and only change the parts in square brackets.

  `lcd /exports/eddie/scratch/[userName]/[studyFolderCluster]/`

  `lls`

  `cd /chss/datastore/chss/groups/hsscollege-shared/ppls/morcom02/[studyFolderDataStore]/`

  `ls`

- Copy the 'derivatives' folder from DataStore to the cluster:

  `get -R derivatives`

- Use the same method to copy the 'spm12_v7487' folder to your study folder:

  `cd /chss/datastore/chss/groups/hsscollege-shared/ppls/morcom02/Shared_resources`

  `lcd /exports/eddie/scratch/[userName]/[studyFolder]/`

  `get -R spm12_v7487`

- ... and to copy the the 'code' folder to your study folder:

  `cd /chss/datastore/chss/groups/hsscollege-shared/ppls/morcom02/[studyFolder]/`

  `lcd /exports/eddie/scratch/[userName]/[studyFolder]`

  `get -R code`

- You can also use the same method to copy folders of individual subjects, but for that you need to set your local and remote folder as the 'derivatives' folder:

  `lcd /exports/eddie/scratch/[userName]/[studyFolderCluster]/derivatives`

  `cd /chss/datastore/chss/groups/hsscollege-shared/ppls/morcom02/[studyFolderDataStore]/derivatives`

  `get -R sub-01`

  `get -R sub-02`

- Exit `sftp` and the staging node by typing `exit` twice:

  `exit`

  `exit`

- Few additional tips

  - **I recommend creating a .txt file with these commands and then copy-pasting them directly to the terminal**. You can copy-paste many lines in parallel to accomplish this step quickly. See the "cluster_commands.txt" file for an example.
  - `sftp` access may be sometimes turned off. If so, contact the Information Services helpline.
  - The `cd` command means "current directory" and it navigates you to a specific folder.
  - If you are navigating to a folder using the `cd` command, you can list the contents of that folder by typing `ls`.
  - If you want to quickly delete a folder that is inside your current folder, type `rm -rf [folderName]`. Be careful: this will permanently delete the folder.

### 3. Submit the scripts to the cluster and monitor progress

#### Basic command for submitting a script

- Open a new terminal window (MobaXterm, Windows, or Mac terminal) to connect to the Eddie3 cluster. Paste the lines below to the terminal. If you are using a saved session on MobaXterm, click on that session to achieve the same result:

  `ssh [userName]@eddie3.ecdf.ed.ac.uk`

- Submit the "preproc.sh" script to the cluster with the command below (note that the command is on a single line). Before submitting the script, you may need to adjust the amount of computing resources you request and decide if you want to submit your script using priority computing time (more on this below):

  `qsub -pe sharedmem 12 -l h_vmem=16G -l h_rt=86400 -P psych_PPLS-fMRI-studies -e /exports/eddie/scratch/[userName]/[studyFolder]/derivatives/ -o /exports/eddie/scratch/[userName]/[studyFolder]/derivatives/ /exports/eddie/scratch/[userName]/[studyFolder]/code/preproc.sh`

- The options in the job submission command are

  - `-pe sharedmem` : number of computer cores to request,
  - `-l h_vmem` : amount of memory requested per computer core,
  - `-l h_rt` : processing time requested in seconds (3600 is 1 hour)
  - `-P` : priority compute project to which the job is assigned to (delete this if you want to submit your script as a regular job, not a priority job)
  - `-e` : path where a text file of errors will be saved,
  - `-o` : path where a text file of console outputs will be saved.
  - The last line in the command is a path to your script.

#### Adjusting the resources you request

- When you submit your script, it will be assigned a job ID and put to a queue on the cluster. Ideally you would request enough resources to run the script in reasonable time, but not too many resources because otherwise your job may stay in the queue for hours.
- To adjust the resources you request for processing, change the numbers behind `-pe sharedmem`, `-l h_vmem`, and `-l h_rt` flags. Recommended resources to request for processing 
  - 1-3 subjects : `-pe sharedmem 8 -l h_vmem=32G -l h_rt=72000`
  - 10 subjects : `-pe sharedmem 12 -l h_vmem=16G -l h_rt=86400`
- Note that it may not be good to submit the script for more than 12 subjects, because the slice timing correction step in the "p1_func" script currently seems to take a lot of time if more subjects are processed in parallel.
- To use priority computing time (shorter queue), your job submission command must contain the line `-P psych_PPLS-fMRI-studies`, where "psych_PPLS-fMRI-studies" is our priority compute project. Your username must also have been previously associated with the priority compute project. Before submitting your script as a priority job, ensure that the data and the scripts are set up correctly because priority computing time is paid for and will be wasted if the script crashes. To check that the script is working, you can submit the script as a regular (non-priority) job for processing the data of a single subject and confirm that it runs. To submit your scripts as regular jobs, simply omit the line`-P psych_PPLS-fMRI-studies`.
- The ["memory specification" page on the Eddie3 cluster manual](https://www.wiki.ed.ac.uk/display/ResearchServices/Memory+Specification) can be helpful to get a sense of how much resources you can request. The cluster has "standard", "intermediate" and "large" computing nodes, and the number of "large" nodes is smaller than "standard" or "intermediate" nodes. If you request a lot of resources, your job will be assigned to larger nodes and you may have to wait longer. For example, maximum total requestable memory in "intermediate" nodes is 256 GB, so if you request 16 cores and 32 GB per core (a total of 16*32 = 512 GB) your job will likely go to a "large" computing node instead and will stay in the queue longer.

#### Monitoring the progress of your job

- Monitor the progress of your job by typing `qstat`. This commands lists the status of all active jobs. Status 'qw' means 'waiting', and 'r' means 'running. When the job has completed, it does not appear in the list of jobs.
- After the job has completed
  - Check that all preprocessed files are there on the cluster. Refer to "qualchecks*.xlsx" for a list.
  - Skim the console output text file to check that all scripts ran. The file is named as "preproc.sh.po[job-ID]". If a script completed all steps for a particular subject, it prints out a line such as: "sub-01: p1_func: time taken: 58.8074 minutes = 0.98012 hours".
  - Skim the text file of errors to check that TE-dependent analysis script ran (the main console outputs of that script are printed in that file despite it being an "errors" file). The file of errors is named as "preproc.sh.pe[job-ID]".

#### Troubleshooting

- If any of the MATLAB scripts did not run, try submitting the "preproc.sh" script to the cluster again. Increase the runtime length if needed. If you only want to re-run some specific preprocessing steps, open the "preproc.sh" script in a text editor that respects Linux line endings (such as [Notepad++](https://notepad-plus-plus.org/)), then go to the heading that says "# Call the scripts in a sequence" and comment in the lines of all scripts you do not want to run again.
- In general, if you have an issue with a script that you cannot identify, you can run the script line-by-line interactively on the cluster. To request an interactive session for 1 hour with 8 GB of memory, type `qlogin -l h_vmem=8G -l h_rt=3600`. If you want to check a MATLAB script, load MATLAB first by typing `module load matlab/R2018a` and then start MATLAB by typing `matlab`. If you are testing a Python script, you can similarly load Python with `module load roslin/python/3.5.5`, start Python with `python` and then copy the script line by line to the terminal (however, copy-pasting does not sometimes work for lines that are indented).

#### Submitting the DARTEL script

- The "preproc.sh" script can be used to process all or some subjects at any given moment. Once you have processed all your subjects and their data is in the 'derivatives' folder on the cluster, you can submit the DARTEL script to normalise the images to MNI space and to smooth them. You can use the command:

  `qsub -pe sharedmem 8 -l h_vmem=16G -l h_rt=48000 -P psych_PPLS-fMRI-studies -e /exports/eddie/scratch/[userName]/[studyFolder]/derivatives/ -o /exports/eddie/scratch/[userName]/[studyFolder]/derivatives/ /exports/eddie/scratch/[userName]/[studyFolder]/code/preproc_dartel.sh`

### 4. Copy data back from the cluster

- Open a terminal window and connect to the cluster. Replace [userName] with your university user name. If you are using a saved session on MobaXterm, click on that session to achieve the same result:

  `ssh [userName]@eddie3.ecdf.ed.ac.uk`

- Connect to a data staging node that allows `sftp` connections. Usually this is not necessary, but currently it is. The node name is given to you:

  `qlogin -q staging -l h='node2c11'`

- Set the permission of all files to be copied back (in the "derivatives" folder) to "read, write, execute". This is to avoid potential file access issues later:

  `cd /exports/eddie/scratch/[userName]/[studyFolder]`

  `chmod 777 -R -v derivatives`

- Connect to DataStore from the cluster using sftp and port 22222:

  `sftp -P 22222 [userName]@chss.datastore.ed.ac.uk`

- Set paths to your study folder on the cluster (a "local" folder), and to your study folder on DataStore (a "remote" folder). These folders should contain the 'derivatives' folder. If you want to be sure you nagivated to correct folders, you can type `lls` to list contents of the local (cluster) folder and `ls` to list contents of the remote (DataStore) folder. Here, path to your folder on DataStore is not the same as your mapped network drive: use the template below and only change parts in the square brackets.

  `lcd /exports/eddie/scratch/[userName]/[studyFolderCluster]/`

  `lls`

  `cd /chss/datastore/chss/groups/hsscollege-shared/ppls/morcom02/[studyFolderDataStore]/`

  `ls`

- Copy the 'derivatives' folder from cluster to DataStore. The difference from copying files back to DataStore from copying files to the cluster is the `put` command instead of `get`:

  `put -R derivatives`

- You can use the same method to copy folders of individual subjects, but for that you need to set your local and remote folder as the 'derivatives' folder. Be sure you also ran the `chmod` command on the "derivatives" folder beforehand:

  `lcd /exports/eddie/scratch/[userName]/[studyFolderCluster]/derivatives`

  `cd /chss/datastore/chss/groups/hsscollege-shared/ppls/morcom02/[studyFolderDataStore]/derivatives`

  `put -R sub-01`

  `put -R sub-02`

- Exit `sftp` and the staging node by typing `exit` twice:

  `exit`

  `exit`

## Software requirements
* MATLAB R2018a for all scripts except "step1_prepareImages" which was run with R2018b
* [Statistical Parametric Mapping (SPM) 12 v7487 (MATLAB toolbox)](https://github.com/spm/spm12)
* Python 3.5.5
* The preprocessing scripts also use [tedana 0.0.7](https://tedana.readthedocs.io/en/latest/usage.html), [Nilearn 0.5.2](https://nilearn.github.io/index.html), and [nibabel 2.4.1](https://nipy.org/nibabel/) Python packages. These are automatically installed on the computer cluster as the scripts are run.

## Methods

### Functional preprocessing
BOLD images acquired at echo time 1 were realigned (but not resliced) using the "spm_reslice" function from Statistical Parametric Mapping (SPM) 12 v7219 (www.fil.ion.ucl.ac.uk/spm); in this process, voxel-to-world matrices of echo-1 images were updated and estimates of head motion were obtained. The voxel-to-world matrix of each echo-1 volume was then applied to the corresponding volumes acquired at other echo times using the "spm_get_space" function; this ensures that BOLD time series acquired at different echos were realigned exactly in the same way. Each realigned BOLD time series was then slice time corrected using "spm_slice_timing" with reference time set at half of the Repetition Time (TR/2). Realigned and slice time corrected BOLD images were then resliced to the space of the first volume of the first echo-1 BOLD time series using "spm_reslice". Note that head motion estimates were obtained prior to temporal processing as recommended by [Power et al. (2017)](10.1371/journal.pone.0182939), but this is not the same as performing motion correction before slice timing correction because images were resliced to the same space *after* slice timing correction. A brain mask was then computed based on preprocessed echo-1 BOLD images using "compute_epi_mask" from Nilearn 0.5.2 ([Abraham et al., 2014](https://doi.org/10.3389/fninf.2014.00014); https://nilearn.github.io/index.html) and was combined with a grey-and-white matter mask in BOLD space for better coverage of anterior and ventral temporal lobes. Minimally preprocessed BOLD time series were then fed into the "TE-dependent analysis" workflow version 0.0.7 ([tedana developers, 2019](https://tedana.readthedocs.io/en/latest/approach.html#); [DuPre et al., 2019](https://doi.org/10.5281/zenodo.2558498 ); [Kundu et al., 2011](https://doi.org/10.1016/j.neuroimage.2011.12.028); [Kundu et al., 2013](https://doi.org/10.1073/pnas.1301725110)) that decomposes the BOLD time series into components and classifies each component as BOLD signal or noise; the workflow was run inside the previously created brain mask. All preprocessed BOLD time series were then unwarped to correct for inhomogeneities in the scanner's magnetic field: a voxel displacement map was calculated based on a phase difference and magnitude image with SPM's "Calculate VDM" tool, coregistered to the first echo-1 image from the first task-run combination, and then applied to each task-run combination using SPM's "Apply VDM" tool; using a single coregistered VDM on all echos and task-run combinations ensures that all realigned time series were unwarped in the same way. Preprocessed BOLD time series corresponding to optimal combination of echos and denoised optimal combination of echos were then spatially normalised to MNI space using SPM's non-linear registration tool DARTEL ([Ashburner, 2007](https://doi.org/10.1016/j.neuroimage.2007.07.007)); this process was repeated three times using Gaussian smoothing kernels with 0mm, 4mm and 8mm Full Width at Half Maximum (FWHM) to obtain unsmoothed and smoothed spatially normalised images.

### Anatomical preprocessing
A copy of the T1-weighted image was first coregistered to the median image of minimally preprocessed (not unwarped) echo-1 BOLD images with SPM's coregistration routine and segmented with SPM's unified segmentation ([Ashburner & Friston, 2005](https://doi.org/10.1016/j.neuroimage.2005.02.018)). The resulting grey and white matter tissue class images were combined into a single mask using "spm_imcalc", resliced to the space of the median functional image using "spm_reslice" with trilinear interpolation, and thresholded at 0.25 to binarise the mask. After the BOLD images were unwarped, another copy of the T1-weighted image was coregistered to the median image of unwarped echo-1 BOLD images and segmented with SPM's unified segmentation; in this process, DARTEL-compatible tissue class images were obtained for each subject. Finally, DARTEL-compatible grey and white matter tissue class images of all subjects were used to create a DARTEL template and to obtain DARTEL flow fields for each subject.


