%---------------------------------
% MULTI ECHO PREPROCESSING: Prepare images
%
% NB. This script assumes that
%  - Each subject has a folder that contains their raw image folders,
%    and there is one raw image folder for each scanner sequence run:
%      subjectFolder\sequence1
%      subjectFolder\sequence2
%      subjectFolder\sequence3
%
%    Specifically, it assumes there is a separate folder for T1 images, T2
%    images, fieldmap phase difference image, fieldmap magnitude images,
%    and for each fMRI run. For example, the folder of each subject may 
%    contain a folder '5_t1_mprage_sag_p3_iso_Munich_0-8mm' that contains
%    T1 images, a folder '6_fMRI_PSN_TR_p3_s2_3mm' that contains fMRI images 
%    from the first fMRI run, and '7_fMRI_PSN_TR_p3_s2_3mm' that contains 
%    images from the second fMRI run.
%
%    As it assumes a folder for phase difference image and a folder for
%    mangitude images, it is compatible with Siemens scanners such as
%    Prisma or Skyra.
%
% Main inputs
%  - Path to your study folder
%  - Subject IDs for which to run the script for in a cell array.
%    For example:
%    {'sub-03'
%     'sub-04'}
%  - Paths to the raw image folders of each subject in a cell array.
%    For example:
%    {'Y:\E182021_SemanticEncoding_RO\Skyra_fit\3\20190520_111222.277000'
%     'Y:\E182021_SemanticEncoding_RO\Skyra_fit\4\20190521_140201.640000'};
%
% Main outputs
%  - BIDS formatted data set in folder: [studyfolder]/BIDS
%  - Copy of the BIDS formatted data set in folder: [studyfolder]/derivatives
%  - Each subject will have their own folder in the BIDS folder, e.g.
%    [studyfolder]/BIDS/sub-01
%
% What the script does
%  - Converts DICOM images to NIfTI using dcm2niix
%  - Renames NIfTI images according to BIDS format
%  - Adds 'EchoTime1' and 'EchoTime2' fields to .json file of phasediff image
%  - Adds 'TaskName' field to .json file of functional images
%  - Adds 'DefaceMethod' field to .json file of T1 and T2 images
%  - Creates a 'dataset_description.json' file
%  - Removes dummy scans from BIDS formatted images
%  - Defaces T1 and T2 images using spm_deface
%
% Additional notes
%  - If your study folder and raw image folders are on a network share, I
%    recommend mapping the folder that contains your study folder with a
%    drive letter such as 'Z'  Then path to your study folder on Windows
%    is 'Z:\YourStudyFolder\'. You can google 'Mapping a network drive' for
%    more information. 
%    If you map a network drive and are not fully sure what the correct
%    path to your folder is after that, you can navigate to the folder 
%    in file explorer, click on any file, select properties, and look up the path.
%  - If NIfTI conversion does not run ('access denied'), 
%    check that the permissions of the 'dcm2niix.exe' file in the code folder
%    are set to read, write, execute 
%  - Only functional image folders with size greater than 100 mb 
%    (or another specified size) are included; 
%    other folders are considered as failed runs or test runs.
%  - After running the script, BIDS validator can be used to check 
%    that the files are properly formatted
%    http://bids-standard.github.io/bids-validator/
%  - For specification of BIDS format, see
%    https://bids-specification.readthedocs.io/en/stable/
%
% Author   : Andres Tamm
% Software : MATLAB R2018b, dcm2niix, SPM12 v7219
%--------------------------------- 

%% Clear variables
clear variables

%% Input : Things that need to be specified to run the script

% Create an empty struct
S = struct();

% Specify task label that will be added to names of functional images
% If different runs have different task labels, you can ignore this step
S.taskLabel = 'nback';

% If different runs have different tasks, specify path to a tab-delimited
% file that has columns 'subject', 'run1', 'run2', 'run3', etc.
% The 'subject' column must contain subject IDs in format, e.g. 'sub-01', 'sub-02', etc
% Each 'run' column must contain a task label in BIDS format for that run, e.g. 'nback'
%----------
% NB. If different runs have the same task, 'taskLabelPath' must be set to empty 
%     like this: taskLabelPath = []
%     And task label must be specified in the 'taskLabel' variable above.
%----------
%S.taskLabelPath = 'Z:\[localStudyFolder]\code\taskLabels.txt';
S.taskLabelPath = [];

% How many usable task-run combinations should be in the data? (Does not include failed runs)
% If there is one task with 4 runs, for example, then this number should be 4
% If there are say two tasks with 3 runs each, then this number should be 2*3 = 6
S.nTaskRunExpected = 4;

% How many different echos should be in the data set?
S.nEchoExpected = 3;

% Specify path to your study folder on DataStore
S.study_path = 'Z:\[localStudyFolder]\';

% Specify path to your code folder; it should contain dcm2niix.exe
S.code_path = 'Z:\[localStudyFolder]\code';

% Specify path to SPM folder
S.spm_path = 'Z:\Shared_resources\spm12';

% Convert DICOM images to nifti? 1 = yes, 0 = no
% This needs to be set to "1" for all studies expect Sentence Code
S.nifticonv = 1;

% Number of dummy volumes to discard in the BIDS-formatted data set
S.ndiscard = 3;

% Specify size of a functional image folder in megabytes above which it is
% considered a proper run; folders with smaller size are considered as failed or test
% runs and their data will not be copied over
S.sizelim = 200;

% Do you have a multi-echo data set? 1 = yes, 0 = no; if multi-echo, then
% currently works for three echos.
S.mecho = 1;

% Specify subject IDs for which to run the script for in a MATLAB cell array
% Example: subjList = {'sub-01'; 'sub-02'; 'sub-03'};
S.subjList = {'sub-02' 
              'sub-04' 
              'sub-05'};

% Specify paths to the image folders for each of your subjects in a MATLAB cell array
% These must be paths to folders that contain  raw image folders.
% A raw T1 image folder could be, for example, '5_t1_mprage_sag_p3_iso_Munich'
S.subjFolders = {'Y:\E182021_SemanticEncoding_RO\Skyra_fit\3\20190520_111222.277000'
                 'Y:\E182021_SemanticEncoding_RO\Skyra_fit\4\20190521_140201.640000'
                 'Y:\E182021_SemanticEncoding_RO\Skyra_fit\5\20190604_125024.983000'};

% Deface T1 and T2 images with "spm_deface"? 1 = yes, 0 = no
S.deface = 1;

% String of text in raw image folder names that identifies a particular
% imaging sequence
S.funcLabel = 'fMRI';  % string contained in all fMRI folder names
S.t1Label   = 't1';    % string contained in all T1 folder names
S.t2Label   = 't2';    % string contained in all T2 folder names
S.fmapLabel = 'field_mapping';  % string contained in all field map folder names

% Specify the name of your data set, BIDS standard version, and authors 
% Authors must be specified in a cell array.
% Later, a 'dataset_description.json' file will be created using this information
S.dataSetName = 'YourDataSet';
S.BIDSVersion = '1.2.0';
S.Authors = {'Author 1' 'Author 2' 'Author 3'};

%% Run the script

% Get structure fields as variables in the environment
cd(S.code_path)
save('tmp.mat', '-struct', 'S')
load('tmp.mat')
delete('tmp.mat')

% Start printing the console output to an external file (log)
logFileName = ['log_step1_prepareImages_' date '.txt'];
logFilePath = [study_path filesep logFileName];
diary(logFilePath);

% Message
disp('Running step1_prepareImages with settings:');
disp(S);

% Get path to BIDS folder and create it
bids_path = [study_path filesep 'BIDS'];
mkdir(bids_path)

% Add SPM and code to path
addpath(spm_path);
addpath(code_path);

% Get number of subjects
nsub = numel(subjList);

% If task labels for runs come from a file, read them in
if isempty(taskLabelPath) == 0
    taskLabelInfo = readtable(taskLabelPath);
end

% Loop over subjects
for i = 1:nsub  
    %% Copy images to 'BIDS/sub-XX' folder and rename according to BIDS format
    
    % Start counting time
    tic
    
    %------------------------------
    % Get subject information
    %------------------------------
    
    % Subject ID
    subj = subjList{i};
    disp([subj ': Starting processing...']);

    % Get path to subject's folder that directly contains their raw image folders
    base_path = subjFolders{i};

    %------------------------------
    % Get paths to folders that contain raw images (on imaging centre)
    %------------------------------
    
    % Message
    disp([subj ': Getting paths to folders that contain raw images...'])

    % Folder that contains T1 images
    cd(base_path)
    t1_dir = dir(['*' t1Label '*']);
    if isempty(t1_dir) == 1
        error('t1 folder not found, check folder names')
    end
    t1_dir = t1_dir.name;
    %t1_dir =  % or specify manually here

    % Folder that contains T2 images
    t2_dir = dir(['*' t2Label '*']);
    if isempty(t2_dir) == 1
        warning('t2 folder not found')
    else
        t2_dir = t2_dir.name;
    end
    %t2_dir =  % or specify manually here

    % Get names of fieldmap folders, sorted according to folder number
    % Assuming that magnitude images folder comes first
    fmap_dirs = dir(['*' fmapLabel '*']);
    fmap_dirs = {fmap_dirs.name}';
    folderNum = regexp(fmap_dirs, '^\d{1,2}', 'match');
    folderNum = vertcat(folderNum{:});
    folderNum = cellfun(@str2num, folderNum);
    [~,idx]   = sort(folderNum);
    fmap_dirs = fmap_dirs(idx);

    % Folder that contains fieldmap magnitude images
    fmap_magnitude_dir = fmap_dirs{1};
    %fmap_magnitude_dir = ['10_gre_field_mapping_3mm'];  % or specify manually

    % Folder that contains fieldmap phase difference image
    fmap_phase_dir = fmap_dirs{2};
    %fmap_phase_dir = ['11_gre_field_mapping_3mm'];;  % or specify manually

    % Create a cell array of names of folders that contain functional images
    % Will be ordered according to run number (i.e. first run is in the first folder, etc)
    % Note that folders with size less than will be discarded

    % Get names of all func directories
    cd(base_path)
    func_dirs = dir(['*' funcLabel '*']);
    func_dirs = {func_dirs.name}';
    func_size = [];

    % Get total sizes of all func directiories
    for j = 1:numel(func_dirs)
        cd([base_path filesep func_dirs{j}])
        f = dir('*');
        f = f(3:end);
        s = sum([f.bytes])/(10^6);
        func_size(j,1) = s;
    end

    % Remove those directories from the list whose size is less tahn 100 mb
    func_dirs = func_dirs(func_size > sizelim);

    % Sort functional directories in chronological order
    folderNum = regexp(func_dirs, '^\d{1,2}', 'match');
    folderNum = vertcat(folderNum{:});
    folderNum = cellfun(@str2num, folderNum);
    [~,idx]   = sort(folderNum);
    func_dirs = func_dirs(idx);

    % Or specify functional directories manually if the above does not work
    %func_dirs = {
    %     '7_fMRI_PSN_TR_p3_s2_3mm' 
    %     '8_fMRI_PSN_TR_p3_s2_3mm' 
    %     };
    
    % Gather relevant image folders in a cell
    if ~isempty(t2_dir) == 1                           % If T2 image exists
        dirs = [t1_dir; t2_dir; fmap_dirs; func_dirs];
    else
        dirs = [t1_dir; fmap_dirs; func_dirs];         % If T2 image does not exist
    end
    
    % Get paths to all relevant raw image folders
    rawPaths = strcat(base_path, filesep, dirs);

    %------------------------------
    % Convert raw images from DICOM to nifti if requested
    %------------------------------    
    if nifticonv == 1
        
        % Message
        disp([subj ': Starting DICOM to NIfTI conversion...'])
        
        % Create a 'nifti' folder in BIDS folder for this subject
        nifti_path = [bids_path filesep subj filesep 'nifti'];
        mkdir(nifti_path)
        
        % Specify destination folders inside nifti folder and create them
        destinationPaths = strcat(nifti_path, filesep, dirs);
        for j = 1:numel(destinationPaths)
            mkdir(destinationPaths{j})
        end

        % Specify path to the dcm2niix.exe file
        % Note that ".exe" must be omitted
        dcm_path = [code_path filesep 'dcm2niix'];
        
        % Generate dcm2niix code
        % The "-f %p_s%s_e%e" command formats the output file names.
        %   Most importantly, "_e%e" means that all images have a suffix
        %   "_e1", "_e2", "_e3" etc according to echo number. If that is
        %   not specified, echo number is occassionally dropped.
        % The " -o" flag is followed by output folder paths
        % Finally, input folder paths are given as the last argument
        % Also see: https://github.com/rordenlab/dcm2niix/issues/101
        x = char(34);
        dcm_code = strcat(x, dcm_path, x, " -f %p_s%s_e%e", " -o ", x, destinationPaths, x, " ", x, rawPaths, x);

        % Save the code to the code folder for reference
        % cd(code_path)
        % fname = ['step0_dcm2niix_code_' date '.txt'];
        % fid = fopen(fname,'wt');
        % fprintf(fid, '%s\n', dcm_code);
        % fclose(fid);

        % Run the code
        for j = 1:numel(dcm_code)
            [status, cmdout] = dos(dcm_code(j,:));
            disp(cmdout)
            if status ~= 0
                error('dcm2niix did not run successfully, check the code')
            end
        end
    end

    %------------------------------
    % Specify new image folders in BIDS format
    %------------------------------
    
    % Names of folders to be created for the current subject inside their folder
    new_anat_dir   = 'anat';  % will contain anatomical images
    new_fmap_dir   = 'fmap';  % will contain fieldmap data
    new_func       = 'func';  % will contain functional images

    % Get paths to target folders and create them
    new_anat_path = [bids_path filesep subj filesep new_anat_dir];
    new_fmap_path = [bids_path filesep subj filesep new_fmap_dir];
    new_func_path = [bids_path filesep subj filesep new_func];

    mkdir(new_anat_path)
    mkdir(new_fmap_path)
    mkdir(new_func_path)
    
    % Get path from which to copy raw images over
    if nifticonv == 1
        base_path_copy = nifti_path;
    else
        base_path_copy = base_path;
    end

    %--------
    % Copy and rename anatomical images 
    %--------

    % Copy and rename T1
    disp([subj ': Copying and renaming T1 from' ' ' t1_dir ' ' 'to' ' ' new_anat_path])
    cd([base_path_copy filesep t1_dir]);
    nii  = dir('*.nii');
    json = dir('*.json');
    copyfile(nii.name,  [new_anat_path filesep subj '_T1w.nii'])
    copyfile(json.name, [new_anat_path filesep subj '_T1w.json'])

    % Copy and rename T2
    if ~isempty(t2_dir) == 1
        disp([subj ': Copying and renaming T2 from' ' ' t2_dir ' ' 'to' ' ' new_anat_path])
        cd([base_path_copy filesep t2_dir]);
        nii  = dir('*.nii');
        json = dir('*.json');
        copyfile(nii.name, [new_anat_path filesep subj '_T2w.nii'])
        copyfile(json.name, [new_anat_path filesep subj '_T2w.json'])
    end

    %--------
    % Copy and rename fieldmaps
    %--------

    % Magnitude images
    disp([subj ': Copying and renaming fieldmap magnitude images from' ' ' fmap_magnitude_dir ' ' 'to' ' ' new_fmap_path])
    cd([base_path_copy filesep fmap_magnitude_dir]);
    
    f = dir('*');
    f = f([f(:).isdir] == 0);
    
    if numel(f) == 2
        nii_1  = dir('*.nii');
        json_1 = dir('*.json');
        copyfile(nii_1.name,  [new_fmap_path filesep subj '_magnitude1.nii'])
        copyfile(json_1.name, [new_fmap_path filesep subj '_magnitude1.json'])
    elseif numel(f) == 4
        nii_1  = dir('*e1.nii');
        json_1 = dir('*e1.json');
        copyfile(nii_1.name,  [new_fmap_path filesep subj '_magnitude1.nii'])
        copyfile(json_1.name, [new_fmap_path filesep subj '_magnitude1.json'])

        nii_2  = dir('*e2.nii');
        json_2 = dir('*e2.json');
        copyfile(nii_2.name, [new_fmap_path filesep subj '_magnitude2.nii'])
        copyfile(json_2.name, [new_fmap_path filesep subj '_magnitude2.json']) 
    else
        error('Incorrect number of images in the fieldmap magnitude images folder')
    end
    
    % Phase difference image
    disp([subj ': Copying and renaming phase difference image from' ' ' fmap_phase_dir ' ' 'to' ' ' new_fmap_path])
    cd([base_path_copy filesep fmap_phase_dir]);
    nii  = dir('*.nii');
    json = dir('*.json');
    copyfile(nii.name, [new_fmap_path filesep subj '_phasediff.nii'])
    copyfile(json.name, [new_fmap_path filesep subj '_phasediff.json'])

    %--------
    % Copy and rename functional images
    % NB -- assumes that different echos always have 'e1.nii', 'e2.nii' etc
    % at the end of the file names. This can be requested when running
    % dcm2niix conversion.
    %--------
    
    % If task labels for runs come from a file, 
    % extract the labels of current subject
    if isempty(taskLabelPath) == 0
        
        % Get task label info for this subject
        idx = strcmp(taskLabelInfo.subject, subj);
        tmp = taskLabelInfo(idx, :);
        
        % Convert to long format
        tmp = stack(tmp, 2:size(tmp, 2), 'IndexVariableName', 'run', 'NewDataVariableName', 'tlabel');

        % Extract chronological run numbers of tasks
        taskRun = regexp(cellstr(tmp.run), '\d{1,2}', 'once', 'match');
        taskRun = str2double(taskRun);
        
        % Extract task labels of tasks
        taskLabels  = tmp.tlabel;
        taskLevels = unique(taskLabels);
    
        % Get new run numbers for each task, such that each unique task will have
        % run numbers counting from 1 onwards.
        taskRunNew = taskRun;
        for k = 1:numel(taskLevels)
            task      = taskLevels{k};
            taskIdx   = ismember(taskLabels, task);
            runNumber = taskRun(taskIdx);
            runNumberNew = [1:numel(runNumber)]';
            taskRunNew(taskIdx) = runNumberNew;
        end
    end

    % Loop over functional image folders
    for j = 1:numel(func_dirs)

        % Message
        disp(['Copying and renaming func images from' ' ' func_dirs{j} ', as run:' ' ' num2str(j)])
        
        % Get run number
        runNumber = j;
        
        % If task labels come from file, get task label and run label for this run
        if isempty(taskLabelPath) == 0

            % Get task label for this run
            taskLabel = taskLabels{taskRun == j};
            disp(['Task label for this run is:' ' ' task])
            
            % Get run number for this run
            runNumber = taskRunNew(taskRun == j);
            disp(['Run number in image file names for this run is:' ' ' num2str(runNumber)])          
        end
                
        % Go to image folder
        cd([base_path_copy filesep func_dirs{j}])

        % If you have a multi-echo dataset
        if mecho == 1
 
            % Echo 1
            nii  = dir('*e1.nii');
            json = dir('*e1.json');
            copyfile(nii.name,  [new_func_path filesep subj '_task-' taskLabel '_run-' num2str(runNumber) '_echo-1_bold' '.nii'])
            copyfile(json.name, [new_func_path filesep subj '_task-' taskLabel '_run-' num2str(runNumber) '_echo-1_bold' '.json'])

            % Echo 2
            nii  = dir('*e2.nii');
            json = dir('*e2.json');
            copyfile(nii.name,  [new_func_path filesep subj '_task-' taskLabel '_run-' num2str(runNumber) '_echo-2_bold' '.nii'])
            copyfile(json.name, [new_func_path filesep subj '_task-' taskLabel '_run-' num2str(runNumber) '_echo-2_bold' '.json'])

            % Echo 3
            nii  = dir('*e3.nii');
            json = dir('*e3.json');
            if isempty(nii) == 1
                nii  = dir(['*_' fnum '.nii']);
                json = dir(['*_' fnum '.json']);
            end
            copyfile(nii.name,  [new_func_path filesep subj '_task-' taskLabel '_run-' num2str(runNumber) '_echo-3_bold' '.nii'])
            copyfile(json.name, [new_func_path filesep subj '_task-' taskLabel '_run-' num2str(runNumber) '_echo-3_bold' '.json'])
        else
            % Echo 1
            nii  = dir('*.nii');
            json = dir('*.json');
            copyfile(nii.name,  [new_func_path filesep subj '_task-' taskLabel '_run-' num2str(runNumber) '_bold' '.nii'])
            copyfile(json.name, [new_func_path filesep subj '_task-' taskLabel '_run-' num2str(runNumber) '_bold' '.json'])
        end
    end  % Loop over functional image folders

    %% Check that functional images were renamed correctly
    
    % Message
    disp([subj ': Starting quality checks...'])
    
    % Get names of functional images
    cd(new_func_path)
    imgfiles = dir('sub*_bold.nii');
    imgfiles = {imgfiles.name}';

    % Identify task-run combinations
    taskRunValues    = regexp(imgfiles,'task-.*run-\d{1,2}', 'once', 'match');
    [~,taskRunIndex] = ismember(taskRunValues, unique(taskRunValues));
    taskRunLevels    = unique(taskRunIndex);
    nTaskRun         = numel(taskRunLevels);

    % Check that number of task-run combinations is expected
    if nTaskRun ~= nTaskRunExpected
        warning([subj ': Number of task-run combinations is not equal to' ' ' num2str(nTaskRunExpected) ', check the data!'])
    else
        disp([subj ': Number of task-run combinations is as expected']);
    end
 
    % Get names of metadata files
    cd(new_func_path)
    imgmeta = dir('sub*_bold.json');
    imgmeta = {imgmeta.name}';
    
    % Extract metadata for images
    hdr = struct();
    for j = 1:numel(imgmeta)
        str = fileread(imgmeta{j});
        scanInfo = jsondecode(str);
        hdr(j).scanInfo = scanInfo;
    end

    % Check that images from earlier runs and echos have earlier acquisition times
    % Note that images in "imgfiles" should be sorted chronologically (earlier
    % runs and echos appear earlier). The code below compares whether the
    % acquisition times of these images as given in the metadata file are also ordered chronologically.
    % NB. Currently, this check is not performed when multiple task labels are present
    if nTaskRun > 1 && isempty(taskLabelPath) == 1
        
        % Read in acquisition times of images
        acqTimes = {};
        for j = 1:numel(imgmeta)
            t = hdr(j).scanInfo.AcquisitionTime;
            acqTimes{j,1} = datetime(t, 'InputFormat', 'HH:mm:s.SSSSSS');
        end

        % Test if acquisition time of each image is greater than of previous image
        test = [];
        ncomp = numel(acqTimes) - 1;
        for j = 1:ncomp
            t1 = acqTimes{j};
            t2 = acqTimes{j+1};
            test(j) = t1 < t2;
        end

        % Test whether this is the case for all images
        if all(test) ~= 1
            error('Echo or run labels of functional images are incorrect: images collected at an earlier time are labelled as if they were acquired later')
        else
            disp('Quality check for run and echo labels based on acquisition times PASSED');
        end
    end
    
    % Check if correct number of echos is present 
    if mecho == 1
        
        % Identify number of echos
        if mecho == 0
            echoindex  = ones(numel(imgfiles), 1);
            echolevels = unique(echoindex);
            necho      = size(unique(echoindex), 1);
        elseif mecho == 1
            echoindex  = regexp(imgfiles,'echo-\d{1,2}', 'once', 'match');
            echoindex  = regexp(echoindex, '\d{1,2}', 'once', 'match');
            echoindex  = str2double(echoindex);
            echolevels = unique(echoindex);
            necho      = size(unique(echoindex), 1);
        else
            error('mecho variable specified incorrectly')
        end
        
        % Check number of echos
        if necho ~= nEchoExpected
            error([subj ': Number of echos is not correct, check the script']);
        else
            disp([subj ': Number of echos is as expected']);
        end
        
        % Extract and display echo times
        echotimes = [];
        for k = 1:necho
            tmp = hdr(echoindex == k & taskRunIndex == 1);
            tmp = tmp.scanInfo;
            echotimes(1, k) = tmp.EchoTime*1000;
        end
        disp([subj ': Echo times (in milliseconds) are:'])
        disp(round(echotimes, 3))
    end

    %% Remove dummy volumes

    % Identify 4D image files
    disp([subj ': Identifying image files...'])
    cd(new_func_path)
    imgfiles = dir('sub*_bold.nii');
    imgfiles = {imgfiles.name}';

    % Remove dummy volumes from each 4D image
    for j = 1:numel(imgfiles)
        
        % Message
        disp([subj ': Removing first' ' ' num2str(ndiscard) ' ' 'dummy volumes from image:' ' ' imgfiles{j}])

        % Read the header and data matrix of the NIfTI image
        h  = niftiinfo(imgfiles{j});
        v  = niftiread(h);
        
        % Check size of the data matrix
        disp(['Image size:' ' ' num2str(size(v))]);
        
        % Update the data matrix such that dummy volumes are excluded
        vnew = v(:,:,:,ndiscard+1:end);
        disp(['Image size after dummy volumes removed:' ' ' num2str(size(vnew))]);
        
        % Update the header such that it reflects new image size
        h.ImageSize = size(vnew);
        
        % Write the image with updated header into a temporary file
        % This is to avoid any issues with opening and writing to the
        % same image that can happen, for example, when using NiBabel
        tmpname = ['tmp_' imgfiles{j} '.nii'];
        niftiwrite(vnew, tmpname, h);
        
        % Double check that header was updated in all places
        %h = niftiinfo(['tmp_' imgfiles{j} '.nii']);  
        %disp(h.ImageSize);
        %disp(h.raw.dim);
        
        % Replace the original image with new image
        movefile(tmpname, imgfiles{j});
        
        % Clear data objects from memory
        v = [];
        vnew = [];
    end

    %% Add echo times and IntendedFor to phasediff .json file
    
    % Message
    disp([subj ': Adding EchoTime1, EchoTime2, IntendedFor to phasediff .json file...'])
    
    % Identify the 4D functional image for which fieldmaps intended for
    cd(new_func_path)
    img = dir('sub*_bold.nii');
    img = {img.name}';
    imgpath = strcat('func/', img);
    
    % Get paths to magnitude1 and magnitude2 images
    cd(new_fmap_path)
    jsonMag1 = [new_fmap_path filesep subj '_magnitude1.json'];
    jsonMag2 = [new_fmap_path filesep subj '_magnitude2.json'];
    
    % Get short and long echo times of magnitude images
    str = fileread(jsonMag1); 
    infoMag1 = jsondecode(str);
    str = fileread(jsonMag2); 
    infoMag2 = jsondecode(str);
    
    te1 = infoMag1.EchoTime;  % shorter echo
    te2 = infoMag2.EchoTime;  % longer echo
    if te1 > te2
        warning('ERROR: Magnitude 1 image has shorter echo time, check file naming')
    end
    
    % Read in the .json file of phase difference image
    cd(new_fmap_path)
    jsonPhasediff = [new_fmap_path filesep subj '_phasediff.json'];
    str = fileread(jsonPhasediff); 
    infoPhasediff = jsondecode(str);
    
    % Add EchoTime1 and EchoTime2 fields in seconds
    infoPhasediff.EchoTime1 = te1;
    infoPhasediff.EchoTime2 = te2;
    infoPhasediff.IntendedFor = imgpath;
 
    % Create new .json formatted string
    % And format it so that it is better to look at
    txt = jsonencode(infoPhasediff);
    tmp = jsonparse(txt);

    % Save a new .json file
    tmpName = 'tmp.txt';
    fid = fopen(tmpName,'wt');
    fprintf(fid, '%s', tmp);
    fclose all;

    % Rename
    movefile(tmpName, jsonPhasediff)
    
    %% Add TaskName to .json files of func images
    
    % Message
    disp([subj ': Adding TaskName to .json files of func images...'])
    
    % Go to func images folder
    cd(new_func_path)
    
    % Get json files
    f = dir('*bold.json');
    f = {f.name}';
    
    % Get task labels from json files and modify .json
    % This piece of code identifies task labels from image names, so it
    % works whether there is just one label or different labels
    for j = 1:numel(f)
        
        % Get task label
        tName = regexp(f{j}, 'task-(.*?)_', 'once', 'tokens');
        tName = tName{1};
        
        % Read in the .json file and add TaskName
        str = fileread(f{j}); 
        infoFunc = jsondecode(str);
        infoFunc.TaskName = tName;

        % Create new .json formatted string
        % And format it so that it is better to look at
        txt = jsonencode(infoFunc);
        tmp = jsonparse(txt);
                
        % Save a new .json file
        tmpName = ['tmp_' f{j}];
        fid = fopen(tmpName,'wt');
        fprintf(fid, '%s', tmp);
        fclose all;
        
        % Rename
        movefile(tmpName, f{j})
    end

    %% Deface images
    if deface == 1

        % Message
        disp([subj ': Defacing T1 and T2 images using spm_deface...'])

        % Go to the anatomical image folder and get names of images
        cd(new_anat_path)
        t1 = [subj '_T1w.nii'];
        t2 = [subj '_T2w.nii'];
        t1json = [subj '_T1w.json'];
        t2json = [subj '_T2w.json'];
        
        % Deface T1, rename
        spm_deface(t1);
        movefile(['anon_' t1], t1);
        
        % Update .json of T1
        txt = fileread(t1json);
        s = jsondecode(txt);
        s.DefaceMethod = 'spm_deface';
        txt = jsonencode(s);
        txt = jsonparse(txt);
        fid = fopen('tmp.txt','wt');
        fprintf(fid, '%s', txt);
        fclose all;
        movefile('tmp.txt', t1json);
        
        % Deface T2, if exists
        if exist(t2, 'file') == 2
            
            % Deface T2
            cd(new_anat_path)
            spm_deface(t2);
            movefile(['anon_' t2], t2);

            % Update .json of T2
            txt = fileread(t2json);
            s = jsondecode(txt);
            s.DefaceMethod = 'spm_deface';
            txt = jsonencode(s);
            txt = jsonparse(txt);
            fid = fopen('tmp.txt','wt');
            fprintf(fid, '%s', txt);
            fclose all;
            movefile('tmp.txt', t2json);
        end
    end

    %% Remove nifti folder, create derivatives folder

    % Delete the nifti folder if you used DICOM to NIfTI conversion
    if nifticonv == 1
        rmdir(nifti_path, 's')
    end
    
    % Create an empty subject's folder in the derivatives folder
    derivatives_path = [study_path filesep 'derivatives' filesep subj];
    mkdir(derivatives_path)  

    % Copy subject's files into his/her derivatives folder
    disp([subj ': Copying subject''s files to the derivatives folder'])
    cd(bids_path);
    copyfile(subj, derivatives_path)
    
    % Display total time taken
    time_taken = toc;
    disp([subj ': step1_prepareImages took' ' ' num2str(time_taken/60) ' ' 'minutes =' ' ' num2str(time_taken/3600) ' ' 'hours'])

end

%% Add data set description file

% Go to BIDS path
cd(bids_path)

% Create a struct that describes the data set
dset = struct();
dset.Name = S.dataSetName;
dset.BIDSVersion = S.BIDSVersion;
dset.Authors = S.Authors;

% Generate filename
fname = 'dataset_description.json';

% Create new .json formatted string
% And format it so that it is better to look at
txt = jsonencode(dset);
tmp = jsonparse(txt);

% Save a new .json file
tmpName = 'tmp.txt';
fid = fopen(tmpName,'wt');
fprintf(fid, '%s', tmp);
fclose all;
     
% Rename
movefile(tmpName, fname)

% Stop logging console output
diary off
