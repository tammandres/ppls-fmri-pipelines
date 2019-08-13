%---------------------------------
% MULTI ECHO PREPROCESSING: Distortion correction of functional images
%
% NB. Image folders must be organised according to the BIDS 1.2.0 format
%     https://bids-specification.readthedocs.io/en/stable/
%
% Input
%  - Preprocessed 4D time series of functional images (from each echo,
%    and combinations of echos), named by default as 'rasub-[X]_task-[X]_run-[X]_echo-[1,2,3,oc,dnoc].nii'
%  - 'paths.mat' file that contains folder paths and some other relevant
%    variables, created by the 'step1_prepareEnvironment*.m' script
% 
% Main outputs
%  - Unwarped 4D time series, named as 'urasub-[X]_task-[X]_run-[X]_echo-[1,2,3,oc,dnoc].nii'
%  - Median image of unwarped echo-1 images, named as 'medianurasub-[X]_task-[X]_run-all_echo-1.nii'
%
% Method
%  - Voxel Displacement Map (VDM) is calculated based on a phase difference and magnitude image
%    and coregistered to the first echo-1 3D volume in the first task-run combination.
%    Computation is done using SPM's calculate VDM tool.
%    Echo times are read in from the .json files of fieldmap magnitude images,
%    blip direction is read from the 'paths.mat' file, 
%    total epi readout time is calculated from the metadata file of the first image
%    from the first task-run combination.
%  - The VDM is then applied to all echos of all task-run combinations, so that 
%    all realigned images are unwarped in exactly the same way. 
%    This is accomplished using SPM's apply VDM tool.
%
% Author   : Andres Tamm
% Software : MATLAB R2018b, SPM12 v7219
%---------------------------------

%% Input - make changes here to run the script on another machine

% % Clear the workspace
% clear variables;
%  
% % Get path to 'derivatives' folder
% work_path = '';
% 
% % Add SPM to path 
% spm_path = '';
% addpath(spm_path);
% 
% % Add code to path 
% code_path = '';
% addpath(code_path);
% 
% % Set the mode of running the sript:
% %  mode = 'all'    : run the script for all subjects
% %  mode = 'subset' : run the script for a subset of subjects
% % If you choose mode = 'subset', you must specify the IDs of subjects in a
% % 'subs' variable. It must be a column cell of strings. For example:
% % subs = {'sub-01'; 'sub-02'; 'sub-10'};
% % Note that if mode = 'all' then it does not matter what the 'subs'
% % variable is set to, it will be ignored.
% mode = 'all';
% subs = {'sub-01'; 'sub-02'; 'sub-10'};
%
% % Specify image file prefixes
% sprefix      = 'a'; % slice timing correction prefix
% rprefix      = 'r'; % realignment prefix
% uprefix      = 'u'; % unwarp prefix
%
% % Specify blip direction (must be 1 or -1)
% blipdir = 1;
    
% Load the paths and variables necessary for running the script, see step0_environment.m
load('paths.mat')

% Add SPM and code folder to path
addpath(spm_path)
addpath(code_path)

% Start printing the console output to an external file (log)
logFileName = ['log_p6_unwarp_' date '.txt'];
logFilePath = [work_path filesep logFileName];
diary(logFilePath);

%% Preparations

% Identify subject IDs and the number of subjects
if strcmp(mode, 'all') == 1
    cd(work_path)
    subjList = dir('sub*');
    subjList = {subjList.name};
    nsub     = numel(subjList);
    subjIdx  = [1:nsub]';
elseif strcmp(mode, 'subset') == 1
    cd(work_path)
    subjList = subs;
    nsub     = numel(subjList);
    subjIdx  = [1:nsub]';
else
    error('Mode variable specified incorrectly')
end

%% Preprocess the images of each subject
% NB, be mindful of the hierarchy of for-loop indices: 
% 1.  i, 
% 2.   j, 
% 3.    k, 
% 4.     l,
% 5.      m.

parfor i = 1:nsub  
    % NB, index = 3 not necessarily sub-03, but third subject in the folder
    % Useful if some subjects are excluded from the folder

    % Start counting time
    tic
    
    %% Get subject information and image paths
    
    % Subject ID
    subj = subjList{i};
    
    % Subject image paths
    disp([subj ': Extracting image paths'])
    func_path = [work_path filesep subj filesep 'func'];
    anat_path = [work_path filesep subj filesep 'anat'];
    fmap_path = [work_path filesep subj filesep 'fmap'];
        
    % Identify image files
    cd(func_path)
    imgfiles  = dir([rprefix sprefix 'sub*_bold.nii']);
    imgfiles  = {imgfiles.name}';
    
    % Identify task-run combinations
    % Originally, the script just identified the number of runs.
    % But if there are multiple tasks, each having their own runs,
    % the script needs to loop over task-run combinations.
    disp([subj ': Identifying task-run combinations...'])
    taskRunValues    = regexp(imgfiles,'task-.*run-\d{1,2}', 'once', 'match');
    [~,taskRunIndex] = ismember(taskRunValues, unique(taskRunValues));
    taskRunLevels    = unique(taskRunIndex);
    nTaskRun         = numel(taskRunLevels);

    % Identify number of echos (including optimal combination of echos and
    % denoised optimal combination of echos)
    tmp           = regexp(imgfiles,'echo-[^_]{1,4}', 'once', 'match');
    echolevels    = unique(tmp);
    [~,echoindex] = ismember(tmp, echolevels);
    necho         = size(echolevels, 1);    
       
    % Prepare paths to mangitude and phase images
    imgPhase = [fmap_path filesep subj '_phasediff.nii'];
    imgMag   = [fmap_path filesep subj '_magnitude1.nii'];
    
    % Paths to metadata files of magnitude images
    jsonMag1 = [fmap_path filesep subj '_magnitude1.json'];
    jsonMag2 = [fmap_path filesep subj '_magnitude2.json'];
    
    % Path to metadata file of the first image of the first task-run combination
    % This will be used to calculate total EPI readout time
    cd(func_path)
    tmp = dir([subj '_' taskRunValues{1} '*bold.json']);
    jsonRun1 = tmp(1).name;

    % Path to fieldmap template and anatomical image
    templatePath = [spm_path filesep 'toolbox' filesep 'FieldMap' filesep 'T1.nii'];
    T1w = [anat_path filesep subj '_T1w.nii'];
   
    %% Compute Voxel Displacement Maps
    
    % Read in metadata for short and long echo time magnitude images
    str      = fileread(jsonMag1);
    infoMag1 = jsondecode(str);
    str      = fileread(jsonMag2);    
    infoMag2 = jsondecode(str);
    
    % Get short and long echo times from magnitude image metadata
    te1 = infoMag1.EchoTime*1000;  % shorter echo time in ms
    te2 = infoMag2.EchoTime*1000;  % longer echo time in ms
    if te1 > te2
        error('ERROR: Magnitude 1 image has shorter echo time, check file naming')
    end
        
    % Read in metadata for the first image of the first task-run combination, 
    % and compute total epi readout time
    str      = fileread(jsonRun1);
    infoRun1 = jsondecode(str);
    tert     = 1/infoRun1.BandwidthPerPixelPhaseEncode*1000;  % total epi readout time in milliseconds
   
    % The Voxel Displacement Map should be coregistered to the first 3D echo-1 EPI image
    % from the first task-run combination. Later, this coregistered VDM will be applied to all 
    % echos and task-run combinations. The lines below create a struct() in a format required
    % by SPM batch. Here, the same functional image is passed to the "epi" field of each session.
    % This is redundant, but is useful if one wanted to change these lines of code in the future
    % such that each session has a different image.
    session = struct();
    for j = 1:nTaskRun
        session(j).epi = { [imgfiles{taskRunIndex == 1 & echoindex == 1} ',1'] };
    end
    
    % Set up batch for VDM calculation
    matlabbatch = {};
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.data.presubphasemag.phase = {imgPhase};
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.data.presubphasemag.magnitude = {imgMag};
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.et = [te1 te2];
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.maskbrain = 1;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.blipdir = blipdir;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.tert = tert;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.epifm = 0;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.ajm = 0;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.uflags.method = 'Mark3D';
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.uflags.fwhm = 10;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.uflags.pad = 0;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.uflags.ws = 1;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.mflags.template = {templatePath};
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.mflags.fwhm = 5;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.mflags.nerode = 2;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.mflags.ndilate = 4;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.mflags.thresh = 0.5;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.defaults.defaultsval.mflags.reg = 0.02;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.session = session;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.matchvdm = 1;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.sessname = 'taskRunCombination-';
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.writeunwarped = 0;  % Don't write any unwarped images yet
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.anat = '';
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj.matchanat = 0;
        
    % Run the batch
    disp([subj ': Computing a Voxel Displacement Map using blip direction:' ' ' num2str(blipdir)])
    spm_jobman('run', matlabbatch);
    
    %% Unwarp images using VDM
    
    % Get names of VDM files
    % Note that a single VDM file will be used for all task-run combinations
    cd(fmap_path)
    f = dir('vdm*taskRunCombination*.nii');
    f = {f.name}';
    
    % Gather VDM files and images into a struct required for matlabbatch
    data = struct();
    for j = 1:nTaskRun
        data(j).scans   = {imgfiles{taskRunIndex == j}}';
        data(j).vdmfile = {[fmap_path filesep f{j}]};
    end
          
    % Set up SPM batch for unwarping
    matlabbatch = {};
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.data = data;
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.roptions.pedir = 2;
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.roptions.which = [2 1];
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.roptions.rinterp = 4;
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.roptions.wrap = [0 0 0];
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.roptions.mask = 1;
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.roptions.prefix = uprefix;
    
    % Run the batch
    cd(func_path)  % Go to the func images folder, because scans do not have absolute paths
    disp([subj ': Unwarping images...'])
    spm_jobman('run', matlabbatch);
       
    %% Compute median of unwarped functional image for echo 1 across all runs
    
    % Identify unwarped image files
    imgfiles  = dir([uprefix rprefix sprefix 'sub*_bold.nii']);
    imgfiles  = {imgfiles.name}';
    
    % Identify task-run combinations
    % Originally, the script just identified the number of runs.
    % But if there are multiple tasks, each having their own runs,
    % the script needs to loop over task-run combinations.
    taskRunValues    = regexp(imgfiles,'task-.*run-\d{1,2}', 'once', 'match');
    [~,taskRunIndex] = ismember(taskRunValues, unique(taskRunValues));
    taskRunLevels    = unique(taskRunIndex);
    nTaskRun         = numel(taskRunLevels);

    % Identify number of echos
    tmp           = regexp(imgfiles,'echo-[^_]{1,4}', 'once', 'match');
    echolevels    = unique(tmp);
    [~,echoindex] = ismember(tmp, echolevels);
	necho         = size(echolevels, 1);    

    % Compute a median image of unwarped echo-1 image: T1 image will later
    % be coregistered to this
    disp([subj ': Computing median image of preprocessed echo-1 images...'])
    img        = char(imgfiles(echoindex == 1));
    outname    = ['median' uprefix rprefix sprefix subj '_task-all_run-all_echo-1.nii'];
    flags      = {};  % necessary for the parallel for loop
    flags.dmtx = 1;
    f          = 'median(X)';
    spm_imcalc(img, outname, f, flags);
    
    % Compute mean image of unwarped echo-1 images
    disp([subj ': Computing mean image of preprocessed echo-1 images...'])
    img        = char(imgfiles(echoindex == 1));
    outname    = ['mean' uprefix rprefix sprefix subj '_task-all_run-all_echo-1.nii'];
    flags      = {};  % necessary for the parallel for loop
    flags.dmtx = 1;
    f          = 'mean(X)';
    spm_imcalc(img, outname, f, flags);
    
    % Display total time taken
    time_taken = toc;
    disp([subj ': p6_unwarp: time taken:' ' ' num2str(time_taken/60) ' ' 'minutes =' ' ' num2str(time_taken/3600) ' ' 'hours'])
    
end  % Loop over subjects

% Stop logging console output
diary off
