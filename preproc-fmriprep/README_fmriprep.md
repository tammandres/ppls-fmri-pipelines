# Preprocessing fMRI data with fMRIPrep on a computer cluster
These are notes for running the [fMRIPrep](https://doi.org/10.1038/s41592-018-0235-4) preprocessing pipeline on the Eddie3 computer cluster at the University of Edinburgh. The section "Quick start" gives an outline of all necessary steps for running fMRIPrep on the cluster: use it if you are already familiar with the cluster. The next section, "How the scripts work", helps to understand the scripts and their usage in more detail, but is not necessary for running the scripts. Finally, "Running the scripts" gives more detailed instructions for running fMRIPrep: this should be most helpful if you are not yet familiar with the cluster.

## Quick start

1. **Prepare your data and scripts**
   * Create a "code" folder in your study folder on DataStore. Store fMRIPrep scripts, dcm2niix.exe and FreeSurfer license file ("license.txt" ) in that folder.
   * Run "step1_PrepareImages.m" to convert images into a tidy data set in BIDS format. Two identical folders with tidy data will be created: "BIDS" and "derivatives". Use "derivatives" in further steps.
   * Choose your fMRIPrep .sh script: 
     * Use "fmriprep_array.sh" if your subject folders have only numerical labels and numbers less than 10 are padded with a zero: "sub-01", "sub-02", ..., "sub-11", "sub-12".
     * Use "fmriprep_array_general.sh" if your subject folders have more general labels, such as "sub-control01" (not just numerical) or "sub-1" (not padded with a zero).
     * Use "fmriprep_sub01.sh" script if for some reason the previous scripts did not work.
   * Update file paths inside your fMRIPrep .sh script: replace "atamm2" with your username and set correct paths to your data and code folder on the cluster.
2. **Copy your data and scripts to the cluster**
   * Use the cluster scratch space to temporarily store your data and scripts. It is located on a path "/exports/eddie/scratch/username/".
   * Connect to the cluster using MobaXterm client:
     * Connect to the cluster by typing: `ssh username@eddie3.ecdf.ed.ac.uk`
     * Go to your scratch folder on the cluster: `cd /exports/eddie/scratch/username/`
     * Create your study folder and derivatives folder in scratch space: `mkdir -p studyfolder/derivatives`
     * Log in to the staging node: `qlogin -q staging -l h='node2c11'`
     * Use sftp to connect from the cluster to your study folder on DataStore: `sftp -P 22222 username@chss.datastore.ed.ac.uk`
     * Set your study folder on the cluster as the "local" folder:  `lcd /exports/eddie/scratch/username/studyFolderCluster/`
     * Set your DataStore folder as the "remote" folder:`cd /chss/datastore/chss/groups/hsscollege-shared/ppls/morcom02/studyFolderDataStore/`
     * Copy your tidy data folder ("derivatives") to the study folder on the cluster: `get -R derivatives`
     * Copy your code folder to the cluster: `get -R code`
     * Exit "sftp" and the staging node by typing "exit" twice: `exit \ exit` 
   * If your tidy data set contains "events.json" files for each subject, delete these files on the cluster before running fMRIPrep. Do it manually or use "remove_events_json.sh".
3. **Create an fMRIPrep "udocker" container on the cluster**
   * Load a specific installation of Python: `module load igmm/apps/python/2.7.10`
   * Change udocker directory to your cluster "scratch" space: `export UDOCKER_DIR=/exports/eddie/scratch/username/udockernew`
   * Pull the image of a desired version of fMRIPrep (here, 1.5.0rc2): `udocker pull poldracklab/fmriprep:1.5.0rc2`
   * Create a container from the pulled image (calling it "fprep"): `udocker create --name=fprep poldracklab/fmriprep:1.5.0rc2`
4. **Submit your fMRIPrep scripts to the cluster**
   * Submit "fmriprep_array.sh" (or another script) with the command: `qsub -t 1-5 -tc 26 -pe sharedmem 4 -l h_vmem=16G -l h_rt=08:00:00 -P psych_PPLS-fMRI-studies -e /exports/eddie/scratch/username/studyfolder/ -o /exports/eddie/scratch/username/studyfolder/ /exports/eddie/scratch/username/studyfolder/code/fmriprep_array.sh`
   * The arguments are:
     * `-t 1-5` : means that you are running the script for subjects labelled 1 to 5: sub-01, sub-02, ..., sub-05. If you are using the "fmriprep_array_general.sh", it means you are running it for the first five subjects (in alphabetical order), no matter what the subject folders are called.
     * `-tc 26` : allow 26 subjects to be processed in parallel; this number can just be set high
     * `-pe sharedmem 4` : request 4 computer cores
     * `-l h_vmem=16G` : request 16 GB of memory per core
     * `-l h_rt=08:00:00` : requests 8 hours of run time for each single subject (subjects run in parallel)
     * `-P psych_PPLS-fMRI-studies` : uses paid priority computing hours
     * `-o`, `-e` : paths where error and output log files are saved
   * After you have run "fmriprep_array.sh" or another main fMRIPrep script for all subjects, request an interactive session and run "fmriprep_reports.sh". 
     * Request an interactive session: `qlogin -l h_vmem=8G -l h_rt=01:00:00 `
     * Go to your code folder: `/exports/eddie/scratch/username/studyfolder/code/`
     * Give execution permission to "fmriprep_reports.sh": `chmod 777 -R -v fmriprep*`
     * Run "fmriprep_reports.sh": `./fmriprep_reports.sh`
5. **Copy processed data back to DataStore**
   * Follow the same steps as in section 2.
   * Set local folder as the fmriprep output folder: `lcd /exports/eddie/scratch/username/studyfolder/out/fmriprep`
   * Set remote folder as your "derivatives" folder on DataStore: 
     `cd /chss/datastore/chss/groups/hsscollege-shared/ppls/morcom02/studyFolderDataStore/derivatives`
   * 
     Transfer all fMRIPrep outputs to "derivatives": `put -R *`
   * Exit "sftp" and the staging node by typing "exit" twice: `exit \ exit` 

6. **Examine visual quality reports**
      * The visual reports are located in the fMRIPrep output folder ("./fmriprep/out"). Open the .html file of each subject (e.g. "sub-01.html") in a web browser.

## How the scripts work

### Running fMRIPrep in a udocker container

* fMRIPrep requires too much memory and computer cores to effectively run it on a regular office computer, but it can be run relatively fast on the [Eddie3 computer cluster](https://www.wiki.ed.ac.uk/pages/viewpage.action?spaceKey=ResearchServices&title=Eddie). 

* It is convenient to run fMRIPrep in a [udocker](https://github.com/indigo-dc/udocker) container, because that way it is not necessary to install all pieces of software that fMRIPrep depends on. Note that the [website of fMRIPrep](https://fmriprep.readthedocs.io/en/stable/installation.html#) recommends a Docker or Singularity container, but these are not available or functional on the cluster.

* The command for running fMRIPrep in a udocker container for participants "01" and "02" looks like this: `udocker run -v /path/to/data:/in -v /path/to/output:/out -v /path/to/fslicense:/fs /path/to/tmp:/work fprep /in /out participant --participant-label 01 02 --fs-no-reconall --fs-license-file /fs/license.txt -w /work`
   * The arguments that start with a flag "-v" (e.g. `-v /path/to/data:/in`) specify paths to various folders that are made available inside the container. For example, "/path/to/data" should be replaced with a folder path to brain images that are to be preprocessed, and that path will be made available inside the container as "/in". Similarly, "/path/to/output" folder should be replaced with a directory path where fMRIPrep outputs will be saved, and it is available inside the container as "/out". In addition "/path/to/fslicense" is a path to FreeSurfer's "license.txt" file and "path/to/tmp" is a path where fMRIPrep temporary files will be saved.
   * "fprep" is a name given to the fMRIPrep udocker container. The first two arguments that follow it are paths to input data folder and output data folder inside the container (these were defined under the previous "-v" arguments as simply /in" and "/out" and do not have to be changed). The third argument "participants" specifies that analysis is done at a participant level and that is the only analysis level supported by fMRIPrep, according to a [tutorial by Stanford Centre for Reproducible Neuroscience](http://reproducibility.stanford.edu/fmriprep-tutorial-running-the-docker-image/).
   * All arguments after the "participants" argument are listed in the "usage" block [on fMRIPrep website](https://fmriprep.readthedocs.io/en/stable/usage.html). For example, "--participant-label" is followed by labels of participants that should be processed, "--fs-no-reconall" specifies that [FreeSurfer](https://surfer.nmr.mgh.harvard.edu/) brain surface reconstruction is disabled, "--fs-license-file" is followed by a path (inside the container) to a FreeSurfer license file, and "-w" is followed by a path (inside the container) to a folder where temporary files should be saved. Note that path to FreeSurfer license file is simply "/fs/license.txt" because the actual path to a folder that contains the "license.txt" file was specified using a "-v" argument and made available in the container as "/fs".

* Note that fMRIPrep needs a FreeSurfer "license.txt" file in order to run, even if FreeSurfer's workflow is disabled with "--fs-no-reconall" argument. FreeSurfer license file can be obtained freely [here](https://surfer.nmr.mgh.harvard.edu/registration.html). In the scripts provided in this repository, FreeSurfer is disabled by default as it can take a lot of processing time. But if it is needed, "--fs-no-reconall" can be deleted from the fMRIPrep command.

### A very brief overview of Eddie3 cluster
* You can use any terminal client to log in to Eddie3 cluster, such as Windows command prompt or Mac terminal. If you are using Windows, it is recommended to use the [MobaXterm client](https://mobaxterm.mobatek.net/), because in addition to terminal it provides a graphical file browser. To connect to the cluster from a terminal, type: `ssh username@eddie3.ecdf.ed.ac.uk`
* The main file storage place on the cluster is your "scratch" space. It has about 1TB of space and files will be deleted after 1 month. It is located on the path "/exports/eddie/scratch/username". To read more about storage, see [here](https://www.wiki.ed.ac.uk/display/ResearchServices/Storage).
* There are two ways to use the cluster: interactive and non-interactive. To use the cluster interactively, you can request an interactive session for a prespecified amount of time and resources.  You can then run applications (such as MATLAB) interactively as if you were using your own computer. However, the resources (memory and computing time) you can request are very limited. To request an interactive session with 8 GB of memory and 1 hour of running time, you can type: `qlogin -l h_vmem=8G -l h_rt=01:00:00`. Interactive sessions are mainly useful for testing that your scripts run properly on the cluster.
* The main way to run scripts on the cluster is to submit them non-interactively. This means that the command for running fMRIPrep is contained inside an ".sh" script (e.g. in "fmriprep_array.sh") and that script is submitted to the cluster as a job. After it is submitted, it is put into a queue and starts running when the computing nodes of the cluster become available. Once you've submitted the script as a job, the cluster handles the job for you and you do not have to be connected to the cluster for it to run. You can use the `qsub` command to submit an ".sh" script to the cluster (see section 4).

### Running fMRIPrep in parallel for multiple subjects

* The main advantage of using the computer cluster is that multiple subjects (for example, 10 subjects) can be processed in parallel, greatly reducing the total time that is needed to process your data set.

* In practice, it seems that the best way of running fMRIPrep in parallel is to submit a separate job script for each participant. There are two other ways of running fMRIPrep in parallel, but these do not seem to be as practical or effective, at least in our cluster:
  * Submitting a single job script for multiple participants and specifying participant labels using the "--participant-label" argument in the fMRIPrep command. The processing of these participants is parallelised to some degree, but it seems much slower.
  * Submitting a single job script for multiple participants that contains a parallel for-loop over participant labels, such that multiple fMRIPrep commands are run in parallel (one per participant). Using this strategy led to memory issues on the cluster even if I tried to limit the memory that each fMRIPrep process can use.
  
* The easiest way to submit a separate job script for each participant is to use an [array job](https://www.wiki.ed.ac.uk/display/ResearchServices/Array+Jobs). This means that the same script is submitted to the cluster multiple times, but the environment variable "SGE_TASK_ID" is different each time. For example, if your job submission command starts with `qsub -t 1-5`, then "SGE_TASK_ID" takes values 1, 2, 3, 4, and 5 at each submission of the script, running it for subjects 1 to 5.

* An alternative, more tedious way is to manually submit a separate ".sh" script for each subject.


### Understanding the scripts that are provided
* The scripts assume that your data is organised according to the [Brain Imaging Data Structure (BIDS)](https://bids-specification.readthedocs.io/en/stable) format. This means (among other things) that the imaging data of each subject is in a folder that is named according to the pattern "sub-<label>". For example, folders of subjects 1, 2 and 3 could be named "sub-01", "sub-02", "sub-03". Subject labels can also be more general, leading to folder names such as "sub-control01", "sub-control02", "sub-control03" etc. The subject labels determine which scripts you can use to process your data.
* This repository contains three main scripts that can be submitted to the cluster for running fMRIPrep. 
  * `fmriprep_array.sh` : use this script if your subject folders have only numerical labels and numbers less than 10 are padded with a zero, such as "sub-01", "sub-02", ..., "sub-11", "sub-12". To submit this script to the cluster, you can use a command that starts with `qsub -t 1-3`, where "-t 1-3" means that subjects whose labels range from 1 to 3 ("01", "02", "03") should be processed. Specifying an interval from 6-12, as in `qsub -t 6-12`, processes subjects whose folders are "sub-06", "sub-07", ... , "sub-12". See the "Running the scripts" section for how to submit it using the "qsub" command.
  * `fmriprep_array_general.sh` : use this if your subject folders have more general labels, such as "sub-control01" (not just numerical) or "sub-1" (not padded with a zero). To submit the script to the cluster, you can use a command that starts with `qsub -t 1-3` where the "-t 1-3" means that the folders of *first three* subjects will be processed, regardless of  what the subject labels are. For example, the folders of the first three subjects could be called "sub-04", "sub-7" and "sub-control01". Similarly, specifying a range 5-10 means that the fifth, sixth, seventh, and so on folder will be processed. Which folder is the first, the second and so on depends on the default alphabetical order of folders on the cluster. See the "Running the scripts" section for more information.
  * `fmriprep_sub01.sh` is useful if for some reason the previous scripts did not work. It is meant for running fMRIPrep on the cluster for a single subject. For example, if you want to run the script for subject "sub-10", you can specify the label of that subject inside the script and then submit it to the cluster. If you want to run it for a different subject, you need to edit the script (and possibly rename it), and submit it again. This script should not be necessary because it is possible to run "fmriprep_array.sh" for a single subject, but it is provided because it is simpler than other scripts and could work if other scripts fail for some reason.
* The "fmriprep_array.sh" and "fmriprep_array_general.sh" scripts can be submitted just once to process multiple subjects (they should be submitted as array scripts), but "fmriprep_sub01.sh" needs to be submitted separately to process each subject. For example, if you want to process 10 subjects with "fmriprep_sub01.sh", you would need to create 10 versions of that script, called "fmriprep_sub01.sh", "fmriprep_sub02.sh" etc and submit them all to the cluster. This is less convenient 
* In addition to the main scripts, there are a few additional useful pieces of code:
  - `fmriprep_reports.sh` needs to be used after running "fmriprep_array.sh" or "fmriprep_array_general.sh" for all subjects. This script generates visual fMRIPrep preprocessing reports for each subject. This script is necessary, because for a reason I do not currently understand, fMRIPrep does not create visual reports when it is run non-interactively on the cluster. Therefore, when fMRIPrep has finished processing all participants, "fmriprep_reports.sh" script can be run interactively (with little resources and little time) to generate reports based on fMRIPrep outputs.
  - `step1_prepareImages.m`: takes raw imaging data as input and outputs a tidied data set in BIDS format. In addition to renaming images, it updates the .json metadata files of fieldmap phase difference images and functional images and removes dummy scans from each 4D BOLD image.
  - `remove_events_json.sh` : if your BIDS-formatted data set contains both "events.json" and "events.tsv" files in the functional images folder of each subject (e.g. "/sub-01/func/sub-01_task-nback_events.json" and "/sub-01/func/sub-01_task-nback_events.tsv"), this script will delete the "events.json" files from the cluster. This is because the presence of both "events.json" and "events.tsv" files can sometimes cause fMRIPrep to exit with an error. You can also delete the "events.json" files manually.

## Running the scripts 

### 1. Prepare your data and scripts

* Create a folder called "code" inside your study folder and store fMRIPrep scripts, DICOM to NIfTI converter, and FreeSurfer license file in it.
   * Download the scripts by going to the main page of the "PPLS-fMRI-pipelines" GitHub repository, choose "Clone or download", unzip, and copy only fMRIPrep scripts into the folder.
   * Download the DICOM to NIfTI converter "dcm2niix" from https://github.com/rordenlab/dcm2niix/releases, unzip, and copy "dcm2niix.exe" to the "code" folder
   * Get FreeSurfer license file ("license.txt") from https://surfer.nmr.mgh.harvard.edu/registration.html
* Then convert your raw data (as given by the brain imaging centre) into a tidy data set in [Brain Imaging Data Structure (BIDS)](https://bids-specification.readthedocs.io/en/stable) format. Run the "step1_prepareImages.m" script in MATLAB on your computer.
   * In the input section of the script, specify a path to your study folder (where the tidy data will be saved), a path to your code folder, a path to the SPM MATLAB toolbox folder, and paths to raw image folders of subjects that you are running the script for. These paths are usually on DataStore network drive. See "README_mecho.md" in the "preproc-mecho" folder for more information about file paths. Note that SPM is only used for defacing anatomical images.
   * Specify a "taskLabel" variable. It contains a [task label](https://bids-specification.readthedocs.io/en/stable/04-modality-specific-files/01-magnetic-resonance-imaging-data.html#task-including-resting-state-imaging-data) that will be included in the names of your functional images, for example "sub-01_task-**nback**_run-1_echo-1.nii". If different fMRI runs have different tasks, you can ignore the "taskLabel" variable and specify path to a "taskLabels.txt" file that will contain the task label for each subject and each run.
   * Specify how many dummy volumes to discard ("ndiscard" variable), whether to run DICOM to NIfTI conversion ("nifticonv" variable), the list of subjects to run the script for ("subjList" variable), and whether to deface the images ("deface" variable).
   * This script creates a "BIDS" folder inside your study folder that will contain tidied up image folders for all subjects, for example "yourStudyFolder\BIDS\sub-01". It will also create a "derivatives" folder that is a copy of the "BIDS" folder. You would be working with the "derivatives" folder, so that if anything goes wrong you have an untouched copy of your original data in the "BIDS" folder. The script will save a log-file inside your study folder: "log_step1_prepareImages_[DATE].txt".
* Decide which script to use for running fMRIPrep:
   * Use "fmriprep_array.sh" if your subject folders have only numerical labels and numbers less than 10 are padded with a zero, such as "sub-01", "sub-02", ..., "sub-11", "sub-12".
   * Use "fmriprep_array_general.sh" if your subject folders have more general labels, such as "sub-control01" (not just numerical) or "sub-1" (not padded with a zero).
   * Use "fmriprep_sub01.sh" script if for some reason the previous scripts did not work.
* Then prepare your job script: open "fmriprep_array.sh", "fmriprep_array_general.sh", or "fmriprep_sub01.sh" script in a text editor. In the input section of the script, replace "atamm2" with your university username and "emotion" with the name of your study folder on the cluster. The lines that need to be changed are also listed below. (*NB. I recommend using a text editor that respects Linux line endings, such as Notepad++. If you are editing the file with a regular text editor, such as Notepad, all lines appear strung together. When using Notepad in Windows, be careful not to create new line breaks because the script will not run with Windows line endings*.)

```
  export UDOCKER_DIR=/exports/eddie/scratch/atamm2/udockernew
  ...
  fpath=/exports/eddie/scratch/atamm2/emotion/code
  dpath=/exports/eddie/scratch/atamm2/emotion/derivatives
  opath=/exports/eddie/scratch/atamm2/emotion/out
  wpath=/exports/eddie/scratch/atamm2/emotion/
```

* If you are using the script `fmriprep_sub01.sh`, you need to specify the label of the subject inside the script. For example, `labs=01` processes subject with a folder "sub-01", `labs=control01` processes subject with a folder "sub-control01". There must be no white spaces before and after the equality sign: `labs = 01` will not work. However, this script is usually not be necessary: you can use "fmriprep_array.sh" or "fmriprep_array_general.sh" to process a single subject.

### 2. Copy your data and job script to the cluster

* The Eddie3 cluster has different spaces where you can store files. You will probably want to use the "scratch" space because this has enough disk space for storing large brain images (for more information on storage, see [here](https://www.wiki.ed.ac.uk/display/ResearchServices/Storage)). Your personal scratch space is located in "/exports/eddie/scratch/username" where "username" is your university username. To set up your data and scripts on the cluster, you could create two new folders in the scratch space: "derivatives" that will store image folders of each subject, and "code"  that will store your scripts, i.e. "/exports/eddie/scratch/username/derivatives" and "/exports/eddie/scratch/username/code". 

* To connect to the cluster, open a terminal window and enter (copy-paste) the line below. You will be asked for your password. Before entering the line, replace "atamm2" with your university username. If you are a Windows user, it is recommended to use the [MobaXterm client](https://mobaxterm.mobatek.net/). In addition to a terminal window, it provides a file browser that allows to easily view files on the cluster.

  `ssh atamm2@eddie3.ecdf.ed.ac.uk`

* Create your study folder and the 'derivatives' folder in the 'scratch' space on the cluster. Replace "atamm2" with your university username and "emotion" with the name you want to give to your study folder on the cluster. The command `mkdir -p emotion/derivatives` creates a folder called "emotion" in your scratch space, and also creates a folder called "derivatives" inside that folder.

  `cd /exports/eddie/scratch/atamm2/`

  `mkdir -p emotion/derivatives`

* Log in to a data staging node that allows `sftp` connections:

  `qlogin -q staging -l h='node2c11'`

* Now connect to DataStore from the cluster using `sftp` and port 22222:

  `sftp -P 22222 atamm2@chss.datastore.ed.ac.uk`

* Then set paths to your study folder on the cluster and to your study folder on DataStore (replace "emotion" with the name of your study folder on the cluster, and replace "E123456_Emotion" with the name of your study folder on DataStore. In addition, replace "atamm2" with your university username. (*In the terminology of sftp, your study folder on the cluster is a "local" folder because you are starting the sftp connection from the cluster and your study folder on DataStore is a "remote" folder because you are connecting to it. Also note that path to your DataStore folder is not the same as your mapped network drive on Windows, it is a Linux path instead: use the template below and only change the parts in square brackets.*)

  `lcd /exports/eddie/scratch/atamm2/emotion/`

  `lls`

  `cd /chss/datastore/chss/groups/hsscollege-shared/ppls/morcom02/E123456_Emotion/`

  `ls`

* Copy the 'derivatives' folder from DataStore to the cluster, assuming that this is the folder that contains the folders of all subjects that need to be processed:

  `get -R derivatives`

* You can use similar commands to copy the the 'code' folder to your study folder. Note that the code folder should contain FreeSurfer license file.

  `lcd /exports/eddie/scratch/atamm2/emotion/`

  `cd /chss/datastore/chss/groups/hsscollege-shared/ppls/morcom02/E123456_Emotion/`

  `get -R code`

* You can also use the same method to copy folders of individual subjects, but for that you need to set your local and remote folder as the 'derivatives' folder:

  `lcd /exports/eddie/scratch/atamm2/emotion/derivatives`

  `cd /chss/datastore/chss/groups/hsscollege-shared/ppls/morcom02/E123456_Emotion/derivatives`

  `get -R sub-01`

  `get -R sub-02`

* Exit `sftp` and the staging node by typing `exit` twice. **Note that you need to exit sftp and the staging node (but not the cluster) to carry out steps 3 and 4.**

   `exit`

   `exit`

* **If your BIDS-formatted data contains both "events.json" and "events.tsv" files** in the functional images folder of each subject (e.g. "/sub-01/func/sub-01_task-nback_events.json" and "/sub-01/func/sub-01_task-nback_events.tsv"), it is better to remove the "events.json" files because leaving them in can cause fMRIPrep to exit with an error. You can delete these files on the cluster manually using MobaXterm file browser, or you can delete them using the `remove_events_json.sh` script. To remove the files with the "remove_events_json.sh" script, open the script in Notepad++ text editor and update the line `dpath=/exports/eddie/scratch/atamm2/emotion/derivatives`: replace "atamm2" with your username, replace "emotion" with the name of your study folder on the cluster, and replace "derivatives" with the name of your data folder on the cluster. Then simply copy-paste the contents of the script to a terminal window to delete .json files.

* Few additional tips

   * I recommend creating a .txt file with these commands and then copy-pasting them directly to the terminal. You can copy-paste many lines in parallel to accomplish this step quickly. See the "cluster_commands_fmriprep.txt" file for an example.
   * `sftp` access may be sometimes turned off. If so, contact the Information Services helpline.
   * The `cd` command means "current directory" and it navigates you to a specific folder.
   * If you are navigating to a folder using the `cd` command, you can list the contents of that folder by typing `ls`. In sftp, the `ls` command lists the contents of your remote folder, and `lls` lists the contents of the local folder.
   * If you want to quickly delete a folder that is inside your current folder, type `rm -rf [folderName]`. Be careful: this will permanently delete the folder.

### 3. Create an fMRIPrep container on the cluster

fMRIPrep website recommends using either Singularity or Docker containers for running the software, but these are currently not available or functional on the cluster. Instead, it is possible to use [udocker](https://github.com/indigo-dc/udocker).

* Open a terminal window and connect to the cluster. Replace "atamm2" with your university user name. You will be asked for your password:

   `ssh atamm2@eddie3.ecdf.ed.ac.uk`
   
* Load Python 2.7.10 from the IGMM folder (udocker is already installed under that Python installation):
   `module load igmm/apps/python/2.7.10`

* Change udocker directory to your cluster "scratch" space, because the default home directory will quickly run out space. For more information on storage on Eddie3 cluster, see [here](https://www.wiki.ed.ac.uk/display/ResearchServices/Storage). Replace "atamm2" with your university username:
  `export UDOCKER_DIR=/exports/eddie/scratch/atamm2/udockernew`

* Pull the image of fmriprep and type "udocker images" to check that it is there. Before pulling the image, replace "1.5.0rc2" with the most recent version of fMRIPrep (you can check the recent version [here](https://github.com/poldracklab/fmriprep/releases)). I recommend not using version 1.4.1 as it produce memory issues:
  `udocker pull poldracklab/fmriprep:1.5.0rc2`
  `udocker images`

* Create a container from the pulled image (calling it "fprep") and check that it is there. This can take about an hour. Note that if you do not create a container and try to run udocker, it will attempt to create a container each time you run it and this can slow down the process.
  `udocker create --name=fprep poldracklab/fmriprep:1.5.0rc2`
  `udocker ps`

### 4. Submit fMRIPrep job script to the cluster

#### Decide on which scripts to use

* You can run fMRIPrep using one of the three main scripts:
  * Use "fmriprep_array.sh" if your subject folders have only numerical labels and numbers less than 10 are padded with a zero, such as "sub-01", "sub-02", ..., "sub-11", "sub-12".

  * Use "fmriprep_array_general.sh" if your subject folders have more general labels, such as "sub-control01" (not just numerical) or "sub-1" (not padded with a zero).

  * Use "fmriprep_sub01.sh" script if for some reason the previous scripts did not work.

* It is convenient to use "fmriprep_array.sh" or "fmriprep_array_general.sh", because you have to submit these scripts only once to process multiple subjects. Using "fmriprep_sub01.sh" is less convenient, because you have to submit that script separately for each subject. It is probably easiest to use "fmriprep_array.sh", so this option is described first.
* After you have run one of three mains scripts for *all* of your subjects, you need to request an interactive session and run the "fmriprep_reports.sh" script to generate visual quality reports for your fMRIPrep runs. fMRIPrep should create these reports by default, but currently it does not do so when it is run in non-interactive mode.

#### Submit the "fmriprep_array.sh" script if subjects have numerical labels

* Open a terminal window and connect to the cluster. Replace "atamm2" with your university user name. You will be asked for your password:

   `ssh atamm2@eddie3.ecdf.ed.ac.uk`

*  Then submit the "fmriprep_array.sh" script to the cluster. Note that the command is on a **single line**. Replace "atamm2" with your username and "emotion" with the name of your study folder:

   `qsub -t 1-5 -tc 26 -pe sharedmem 4 -l h_vmem=16G -l h_rt=08:00:00 -P psych_PPLS-fMRI-studies -e /exports/eddie/scratch/atamm2/emotion/ -o /exports/eddie/scratch/atamm2/emotion/ /exports/eddie/scratch/atamm2/emotion/code/fmriprep_array.sh`

* Before submitting the command, you may need to adjust the options:

   * `-t 1-5` : runs the script for participants whose labels range from "01" to "05" (corresponding to subject folders "sub-01", "sub-02", ..., "sub-05"). To process the folders of different subjects, specify a different range. For example, `-t 8-12` runs the script for subjects with labels "08", "09", "10", "11", "12" (subject folders "sub-08", "sub-09"..., "sub-12").
   * `-tc 26` : specifies that a maximum of 26 subjects can be processed in parallel. Note that the number of participants that are actually processed in parallel depends on the resources that are available on the cluster in that moment, but by setting this high (for example, making it equal to the number of your participants), you ensure that as many jobs can run in parallel as possible.
   * `-pe sharedmem 4` : requests 4 computer cores per subject. Usually this should be sufficient.
   * `-l h_vmem=16G` : requests 16 GB of memory per core for each subject. This should be sufficient. There must be no white spaces before and after equality sign: `h_vmem = 16G` produces an error.
   * `-l h_rt=08:00:00` : requests a processing time of 8 hours for each subject. This should be sufficient.
   *  `-P psych_PPLS-fMRI-studies` : specifies that your job is run as a priority job under the "psych_PPLS-fMRI-studies" project. This means that you are using the paid computing time of the school and the queue of your job will be shorter.
   *  `-e` : path where a text file of errors will be saved.
   * `-o` : path where a text file of console outputs will be saved.
   - **The last line in the command is a path to your script**.

* By using the`-t` option, you are submitting your script as an [array job](https://www.wiki.ed.ac.uk/display/ResearchServices/Array+Jobs). This means that the same script is submitted to the cluster multiple times, but the environment variable "SGE_TASK_ID" is different each time. For example, if you use `-t 1-5`, then "SGE_TASK_ID" takes values 1, 2, 3, 4, and 5 at each submission of the script, running it for subjects 1 to 5.

#### Submit the "fmriprep_array_general.sh" script if subjects have general labels

* Submit "fmriprep_array_general.sh" with the same command you used for "fmriprep_array.sh", only replacing the name of the script in the job submission command:

  `qsub -t 1-5 -tc 26 -pe sharedmem 4 -l h_vmem=16G -l h_rt=08:00:00 -P psych_PPLS-fMRI-studies -e /exports/eddie/scratch/atamm2/emotion/ -o /exports/eddie/scratch/atamm2/emotion/ /exports/eddie/scratch/atamm2/emotion/code/fmriprep_array_general.sh`

* Note that the interpretation of the `-t 1-5` argument is different for "fmriprep_array_general.sh" script:   `-t 1-5` means that the folders of *first five* subjects will be processed, regardless of  what the subject labels are. For example, the folders of the first five subjects could be called "sub-04", "sub-7", "sub-control01", etc. Similarly, specifying a range 5-10 means that the fifth, sixth, seventh, and so on folder will be processed. 

#### Submit the "fmriprep_sub01.sh" script if the above scripts did not work

* "fmriprep_sub01.sh" is a template script for running fMRIPrep only for a single subject. It is simpler than previous subjects and could be easier to use if the more complex scripts did not work.

* If you want to run that script for multiple subjects, create copies of it, such as "fmriprep_sub01.sh" for the first subject, "fmriprep_sub02.sh" for the second subject, "fmriprep_sub03.sh" for the third subject etc. Make sure you set correct subject label inside each individual script.

* Then submit each of these scripts individually with the same command as above. Note that the arguments of array jobs ("-t 1-5" and "-tc 26") should no longer be used:

   `qsub -pe sharedmem 4 -l h_vmem=16G -l h_rt=08:00:00 -P psych_PPLS-fMRI-studies -e /exports/eddie/scratch/atamm2/emotion/ -o /exports/eddie/scratch/atamm2/emotion/ /exports/eddie/scratch/atamm2/emotion/code/fmriprep_sub01.sh`

   `qsub -pe sharedmem 4 -l h_vmem=16G -l h_rt=08:00:00 -P psych_PPLS-fMRI-studies -e /exports/eddie/scratch/atamm2/emotion/ -o /exports/eddie/scratch/atamm2/emotion/ /exports/eddie/scratch/atamm2/emotion/code/fmriprep_sub02.sh`

   `...`

#### Run "fmriprep_reports.sh" to generate visual quality reports
* After you have run "fmriprep_array.sh" or another main fMRIPrep script for all subjects, request an **interactive session** and run "fmriprep_reports.sh".  Replace "atamm2" with your username and "emotion" with the name of your study folder

  * Request an interactive session: `qlogin -l h_vmem=8G -l h_rt=01:00:00 `
  * Go to your code folder: `/exports/eddie/scratch/atamm2/emotion/`
  * Give execution permission to "fmriprep_reports.sh": `chmod 777 -R -v fmriprep*`
  * Run "fmriprep_reports.sh": `./fmriprep_reports.sh`
* This script will generate a "html" file for each subject that contains visual quality reports, e.g. "sub-01.html", "sub-02.html". These files are in fMRIPrep output folder, e.g. "./out/fmriprep".

#### Check that all necessary preprocessed files were created

* When fMRIPrep jobs are completed, check that all preprocessed files are on the cluster. If you did not specify additional output spaces for preprocessed images, the main results you should see in the functional images folder of each subject are: 
   * **Preprocessed BOLD image in MNI space**: 'sub-XX_task-XX_run-XX_space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz' (replace 'XX' with appropriate label)
   * **BOLD reference image in MNI space**: 'sub-XX_task-XX_run-XX_space-MNI152NLin2009cAsym_boldref.nii.gz'
   * **Table of various confound regressors**: 'sub-XX_task-XX_run-XX_desc-confounds_regressors.tsv'
* You should also see visual quality reports in the general fMRIPrep output directory: 'sub-XX.html'
* Note that the functional images directory of each subject is located in '/exports/eddie/scratch/username/studyfolder/out/fmriprep/sub-XX/func' and the general fMRIPrep output directory is higher on that path ('.../out/fmriprep'). Refer to [fMRIPrep website for a complete list of outputs](https://fmriprep.readthedocs.io/en/stable/outputs.html).

#### Monitoring your jobs plus additional tips

- To use **priority computing time** (shorter queue), your job submission command must contain the line `-P psych_PPLS-fMRI-studies`, where "psych_PPLS-fMRI-studies" is our priority compute project. Your username must also have been previously associated with the priority compute project. Before submitting your script as a priority job, ensure that the data and the scripts are set up correctly because priority computing time is paid for and will be wasted if the script crashes. To check that the script is working, you can submit the script as a regular (non-priority) job for processing the data of a single subject and confirm that it runs. To submit your scripts as regular jobs, simply omit the line`-P psych_PPLS-fMRI-studies`.
- The ["memory specification" page on the Eddie3 cluster manual](https://www.wiki.ed.ac.uk/display/ResearchServices/Memory+Specification) can be helpful to get a sense of **how much resources you can request**. The cluster has "standard", "intermediate" and "large" computing nodes, and the number of "large" nodes is smaller than "standard" or "intermediate" nodes. If you request a lot of resources, your job will be assigned to larger nodes and you may have to wait longer. For example, maximum total requestable memory in "intermediate" nodes is 256 GB, so if you request 16 cores and 32 GB per core (a total of 16*32 = 512 GB) your job will likely go to a "large" computing node instead and will stay in the queue longer.
- **Monitor the progress of your job** by typing `qstat`. This commands lists the status of all active jobs. Status 'qw' means 'waiting', and 'r' means 'running. When the job has completed, it does not appear in the list of jobs.
- **To delete a running job**, type `qstat` to identify the job ID, then type `qdel <jobID>`, e.g. `qdel 340152`.
- **To view the status, running time, and other parameters of a job after it has finished**, type `qacct -j <jobID>`, e.g. `qacct -j 340152`.
- In general, **if you want to troubleshoot issues with a script**, you can run the script line-by-line interactively on the cluster. To request an interactive session for 1 hour with 8 GB of memory, type `qlogin -l h_vmem=8G -l h_rt=3600`. Then open the ".sh" script you want to test and copy the commands line by line to the terminal.

### Step 5. Copy processed files back from the cluster

- Connect to the cluster:

  `ssh atamm2@eddie3.ecdf.ed.ac.uk`

- Set the permission of all files to be copied back (in the fMRIPrep output folder) to "read, write, execute". This is to avoid potential file access issues later:
  `cd /exports/eddie/scratch/atamm2/emotion`
  `chmod 777 -R -v out`

- Log in to a data staging node that allows `sftp` connections:

  `qlogin -q staging -l h='node2c11'`

- Connect to DataStore from the cluster using `sftp` and port 22222:

  `sftp -P 22222 atamm2@chss.datastore.ed.ac.uk`

- Set your fMRIPrep output folder as the local folder, and "derivatives" folder on DataStore as the "remote folder:"

  `lcd /exports/eddie/scratch/atamm2/emotion/fmriprep/out`

  `cd /chss/datastore/chss/groups/hsscollege-shared/ppls/morcom02/E123456_Emotion/derivatives`

* Copy fMRIPrep outputs from cluster to DataStore. Note that instead of "get" you are using "put" and "*" means that all files are downloaded:

  `put -R *`

* You can use the same method to copy folders of individual subjects:

  `lcd /exports/eddie/scratch/atamm2/emotion/fmriprep/out`

  `cd /chss/datastore/chss/groups/hsscollege-shared/ppls/morcom02/E123456_Emotion/derivatives`

  `put -R sub-01`
  `put -R sub-02`

- Exit `sftp` and the staging node by typing `exit` twice.

  `exit`

  `exit`


### Step 6. Examine visual quality reports

* After downloading the .html quality reports to your 'derivatives' folder on DataStore, you can open them in a web browser to examine that preprocessing was successful. Usually, the following checks are displayed:
  * Processing of anatomical images
    * Were the anatomical images segmented successfully into tissue classes? Check "Brain mask and brain tissue segmentation of the T1w"
    * Was the anatomical image successfully normalised to standard MNI space? Check "Spatial normalization of the anatomical T1w reference"
  * Using fieldmaps for distortion correction
    * Was the magnitude image successfully skullstripped? Check "Skull stripped magnitude image"
    * Was the magnitude image successfully registered to BOLD reference image? Check "Fieldmap to EPI registration"
    * Does the fieldmap itself match the BOLD reference image well? Check "Fieldmap"
    * Were the BOLD images unwarped correctly? Check "Susceptibility distortion correction"
   * Matching anatomical and functional data
      * Was the anatomical image successfully matched to the BOLD reference image? Check "Alignment of functional and anatomical MRI data"
* Note that the html files of quality reports contain relative links to the 'figures' folder of each subject (e.g. ".../fmriprep/out/sub-01/figures". If figures are missing from that folder, quality report images won't show up.

## Software requirements
* MATLAB R2018a
* [Statistical Parametric Mapping (SPM) 12 v7487 (MATLAB toolbox)](https://github.com/spm/spm12) - only needed for defacing the raw images before these are tidied up into BIDS format.
* Python 2.7.10 (installed on the cluster)


