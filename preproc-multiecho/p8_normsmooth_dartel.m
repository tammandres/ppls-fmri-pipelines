%---------------------------------
% MULTI ECHO PREPROCESSING:
% Spatially normalises functional images to MNI space and smooths them
% using SPM's DARTEL
%
% NB. Image folders must be organised according to the BIDS 1.2.0 format
%     https://bids-specification.readthedocs.io/en/stable/
%
% Input
%  - Preprocessed 4D time series of functional images (from each echo,
%    and combinations of echos), named as 'urasub-[X]_task-[X]_run-[X]_echo-[1,2,3,oc,dnoc].nii'
%  - 'paths.mat' file that contains folder paths and some other relevant
%    variables, created by the 'step1_prepareEnvironment*.m' script
%
% Main outputs
%  - DARTEL template images in 'derivatives/dartel_templates'
%  - DARTEL flow fields for each subject in 'derivatives/sub-XX/u_rc1*.nii'
%  - Spatially smoothed and normalised time series of echos specified in the 'targetechos'
%    variable. By default, these are the optimal combination and denoised
%    optimal combiantion of echos.
%    Spatially normalised time series are named by default as
%    'wurasub-[X]_task-[X]_run-[X]_echo-[X]_bold.nii',
%    where prefix 'w' indicates spatial normalisation and
%    prefixes 'u', 'r' and 'a' are added in previous preprocessing steps.
%    Normalised and smoothed time series are named analogously to
%    's4wurasub-[X]_task-[X]_run-[X]_echo-[X]_bold.nii'
%    where 's4' indicates smoothing with 4mm FWHM and 'wd' indicates spatial normalisation
%
% Note about voxel sizes and bounding box
%  - Currently, the bounding box is set at [-75 -112 -60; 75 76 84] as this worked well for our data
%  - Voxel size of normalised images is set at [3 3 3] as this also worked well
%  - These settings can be changed at 'mni_norm.bb =' and 'mni_norm.vox =' lines below.
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
% nprefix      = 'w'; % normalisation prefix
% smoothPrefix = 's'; % smoothing prefix
%
% % Specify smoothing kernels here in a cell format
% % Must be a cell array of integers, e.g. s = {4 8 12}
% s = {4 8};

% Load the paths and variables necessary for running the script, see
% 'step1_prepareEnvironment.m'
load('paths.mat')

% Add SPM and code folder to path
addpath(spm_path)
addpath(code_path)

% Start printing the console output to an external file (log)
logFileName = ['log_p8_normsmooth_dartel_' date '.txt'];
logFilePath = [work_path filesep logFileName];
diary(logFilePath);

% Specify echo labels of images to be normalised and smoothed
% Use a template: targetechos = {'echo-1'; 'echo-2'; 'echo-3'; 'echo-oc'; 'echo-dnoc'}
% Leave out any of the listed echos if you like, e.g. targetechos = {'echo-oc'; 'echo-dnoc'}
targetechos = {'echo-oc'; 'echo-dnoc'};

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

%% 1. Create DARTEL templates

% Message
disp('Creating DARTEL templates using anatomical images of all subjects...')

% Start counting time
tic

% Get paths to DARTEL-compatible grey and white matter images for each subject
gmPaths = {};
wmPaths = {};
for i = 1:nsub
    
    % Subject ID and path to anatomical images folder
    subj = subjList{i};
    anat_path = [work_path filesep subj filesep 'anat'];
    
    % Get path to grey matter image
    cd(anat_path);
    gmImage = dir('rc1*.nii');
    gmImage = gmImage.name;
    gmImage = [anat_path filesep gmImage];
    
    % Get path to white matter image
    wmImage = dir('rc2*.nii');
    wmImage = wmImage.name;
    wmImage = [anat_path filesep wmImage];
    
    % Store
    gmPaths{i, 1} = gmImage;
    wmPaths{i, 1} = wmImage;
end

% Combine these paths into two 'channels' for SPM segment
imgPaths = {gmPaths wmPaths};

% Set up batch and run
% Note that flow fields will be saved to each subject's 'anat' folder
% and DARTEL templates will be saved to the first subject's 'anat' folder
matlabbatch = {};
matlabbatch{1}.spm.tools.dartel.warp.images = imgPaths;
matlabbatch{1}.spm.tools.dartel.warp.settings.template = 'Template';
matlabbatch{1}.spm.tools.dartel.warp.settings.rform = 0;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(1).its = 3;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(1).rparam = [4 2 1e-06];
matlabbatch{1}.spm.tools.dartel.warp.settings.param(1).K = 0;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(1).slam = 16;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(2).its = 3;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(2).rparam = [2 1 1e-06];
matlabbatch{1}.spm.tools.dartel.warp.settings.param(2).K = 0;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(2).slam = 8;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(3).its = 3;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(3).rparam = [1 0.5 1e-06];
matlabbatch{1}.spm.tools.dartel.warp.settings.param(3).K = 1;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(3).slam = 4;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(4).its = 3;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(4).rparam = [0.5 0.25 1e-06];
matlabbatch{1}.spm.tools.dartel.warp.settings.param(4).K = 2;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(4).slam = 2;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(5).its = 3;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(5).rparam = [0.25 0.125 1e-06];
matlabbatch{1}.spm.tools.dartel.warp.settings.param(5).K = 4;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(5).slam = 1;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(6).its = 3;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(6).rparam = [0.25 0.125 1e-06];
matlabbatch{1}.spm.tools.dartel.warp.settings.param(6).K = 6;
matlabbatch{1}.spm.tools.dartel.warp.settings.param(6).slam = 0.5;
matlabbatch{1}.spm.tools.dartel.warp.settings.optim.lmreg = 0.01;
matlabbatch{1}.spm.tools.dartel.warp.settings.optim.cyc = 3;
matlabbatch{1}.spm.tools.dartel.warp.settings.optim.its = 3;

% Run the batch
spm_jobman('run', matlabbatch);

% Create a new folder in the 'derivatives' folder for storing DARTEL templates
dartel_path = [work_path filesep 'dartel_templates'];
mkdir(dartel_path);

% Move templates from the folder of the first subject to the templates folder
anat_path_1 = [work_path filesep subjList{1} filesep 'anat'];
cd(anat_path_1);
movefile('Template*', dartel_path);

% Display time taken
time_taken = toc;
disp(['p8_normsmooth_dartel: Creating DARTEL templates took' ' ' num2str(time_taken/60) ' ' 'minutes =' ' ' num2str(time_taken/3600) ' ' 'hours'])

%% Normalise the images of each subject to MNI and smooth
% NB, be mindful of the hierarchy of for-loop indices:
% 1.  i,
% 2.   j,
% 3.    k,
% 4.     l,
% 5.      m.

% Message
disp('Normalising images to MNI space and smoothing them...')

% Get path to DARTEL template image
dtemplate = [dartel_path filesep 'Template_6.nii'];

parfor i = 1:nsub
    % NB, index = 3 not necessarily sub-03, but third subject in the folder
    % Useful if some subjects are excluded from the folder
    
    % Start counting time
    tic
    
    %---------------------
    % Get subject information
    %---------------------
    
    % Subject ID
    subj = subjList{i};
    
    % Paths to 'func' and 'anat' folders
    disp([subj ': Extracting image paths'])
    func_path = [work_path filesep subj filesep 'func'];
    anat_path = [work_path filesep subj filesep 'anat'];
    
    % Get names of preprocessed functional images
    cd(func_path)
    disp([subj ': Identifying image files...'])
    imgfiles  = dir([uprefix rprefix '*sub*bold.nii']);
    imgfiles  = {imgfiles.name}';
    
    % Identify echos (including optimal combination and denoised optimal
    % combination of echos)
    tmp = regexp(imgfiles,'echo-[^_]{1,4}', 'once', 'match');
    echolevels     = unique(tmp);
    necho          = numel(echolevels);
    echolevels_num = [1:necho]';
    [~,echoindex]  = ismember(tmp, echolevels);
    
    % Extract only those echos that are requested to be normalised
    idx  = ismember(echolevels, targetechos)
    idx2 = ismember(echoindex, echolevels_num(idx));
    imgfiles = imgfiles(idx2);
    disp('Image files to be normalised are:')
    disp(imgfiles)
    
    % Convert image file names to full image paths so that you wouldn't
    % have to set your current folder for running DARTEL
    imgfiles = strcat(func_path, filesep, imgfiles);
    
    %---------
    % Spatial normalisation without smoothing
    %---------
    
    % Message
    disp([subj ': Spatially normalising images (no smoothing)...'])
    
    % Get paths to DARTEL flow field
    cd(anat_path)
    flowField = dir('u_rc1*.nii');
    flowField = flowField.name;
    flowField = [anat_path filesep flowField];
    
    % Set up MATLAB batch and run
    % Note that DARTEL's batch requires 3D images as input
    matlabbatch = {};
    
    matlabbatch{1}.spm.tools.dartel.mni_norm.template = {dtemplate};
    matlabbatch{1}.spm.tools.dartel.mni_norm.data.subj.flowfield = {flowField};
    matlabbatch{1}.spm.tools.dartel.mni_norm.data.subj.images = imgfiles;
    
    matlabbatch{1}.spm.tools.dartel.mni_norm.vox = [3 3 3];
    matlabbatch{1}.spm.tools.dartel.mni_norm.bb  = [-75 -112 -60; 75 76 84]; % Default is [-78 -112 -70; 78 76 85]
    matlabbatch{1}.spm.tools.dartel.mni_norm.preserve = 0;
    matlabbatch{1}.spm.tools.dartel.mni_norm.fwhm = [0 0 0];
    
    spm_jobman('run', matlabbatch);
    
    % Change the prefix of normalised images, if requested
    % This is because by default DARTEL adds a 'w' prefix to normalised images,
    % but this bit code adds a prefix 'nprefix'
    cd(func_path)
    imgNameOld = [];
    imgNameNew = [];
    if strcmp(nprefix, 'w') ~= 1
        for k = 1:numel(imgfiles)
            [~,f,ext] = fileparts(imgfiles{k});
            imgNameOld = ['w' f ext];
            imgNameNew = [nprefix f ext];
            movefile(imgNameOld, imgNameNew)
        end
    end
    
    %---------
    % Spatial normalisation with smoothing
    %---------
    
    % Get paths to DARTEL flow field
    cd(anat_path)
    flowField = dir('u_rc1*.nii');
    flowField = flowField.name;
    flowField = [anat_path filesep flowField];
    
    % Loop over smoothing kernels
    for j = 1:numel(s)
        
        % Message
        disp([subj ': Spatially normalising images using smoothing kernel:' ' ' num2str(s{j})])
        
        % Get smoothing kernel for current iteration
        fwhm = ones(1, 3)*s{j};
        
        % Set up MATLAB batch and run
        % Note that DARTEL's batch requires 3D images as input
        matlabbatch = {};
        
        matlabbatch{1}.spm.tools.dartel.mni_norm.template = {dtemplate};
        matlabbatch{1}.spm.tools.dartel.mni_norm.data.subj.flowfield = {flowField};
        matlabbatch{1}.spm.tools.dartel.mni_norm.data.subj.images = imgfiles;
        
        matlabbatch{1}.spm.tools.dartel.mni_norm.vox = [3 3 3];
        matlabbatch{1}.spm.tools.dartel.mni_norm.bb  = [-75 -112 -60; 75 76 84]; % Default is [-78 -112 -70; 78 76 85]
        matlabbatch{1}.spm.tools.dartel.mni_norm.preserve = 0;
        matlabbatch{1}.spm.tools.dartel.mni_norm.fwhm = fwhm;
        
        spm_jobman('run', matlabbatch);
        
        % Change the prefix of normalised images
        % This is because by default DARTEL adds 'sw' prefix to normalised
        % and smoothed images, but I want the smoothing kernel to be
        % included in prefix (e.g. 's4' instead of default 's')
        disp([subj ': Adding kernel size to image prefix'])
        cd(func_path)
        for k = 1:numel(imgfiles)
            [~,f,ext] = fileparts(imgfiles{k});
            imgNameOld = ['sw' f ext];
            imgNameNew = [smoothPrefix num2str(s{j}) nprefix f ext];
            movefile(imgNameOld, imgNameNew)
        end
    end  % loop over smoothing kernels
    
    % Display total time taken
    time_taken = toc;
    disp([subj ': p8_normsmooth_dartel: time taken' ' ' num2str(time_taken/60) ' ' 'minutes =' ' ' num2str(time_taken/3600) ' ' 'hours'])
    
end  % Loop over subjects

% Stop logging console output
diary off
