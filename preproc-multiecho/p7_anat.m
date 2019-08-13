%---------------------------------
% MULTI ECHO PREPROCESSING: 
% Anatomical preprocessing for spatial normalisation
%
% NB. Image folders must be organised according to the BIDS 1.2.0 format
%     https://bids-specification.readthedocs.io/en/stable/
%
% Input
%  - Anatomical T1 image, named analogously to 'sub-01_T1w.nii'
%  - Median echo-1 preprocessed unwarped functional image, 
%    named similarly to 'medianurasub-[X]_task-sentence_run-all_echo-1*.nii'
%    That image will be created when running the p6_unwarp*.m script
%  - 'paths.mat' file that contains folder paths and some other relevant
%    variables, created by the 'step1_prepareEnvironment*.m' script
%
% Main outputs
%  - A copy of the T1 image, coregistered to median unwarped echo-1 functional image,
%    named as 'sub-[X]_T1w_orient-uepi.nii'.
%  - Forward deformation field that maps to MNI space, nemad as 'y_sub-[X]*.nii'
%  - DARTEL-compatible tissue class images, with prefixes 'rc1*', 'rc2*', 'rc3*'
% 
% Method
%  - A copy of the T1 image will be first created, named 'sub-01_T1w_orient-uepi.nii'
%  - Copy of the T1 will be coregistered to the median preprocessed image using SPM batch
%  - Coregistered T1 image will be segmented using SPM batch,
%    number of Gaussians set to 2
%
% Author   : Andres Tamm
% Software : MATLAB R2018a, SPM12 v7487
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
% % Set prefixes for preprocessed images
% sprefix = 'a';  % slice timing prefix
% rprefix = 'r';  % realignment (reslicing) prefix
% uprefix = 'u';  % unwarp prefix

% Load the paths and variables necessary for running the script, see step0_environment.m
load('paths.mat')

% Add SPM and code folder to path
addpath(spm_path)
addpath(code_path)

% Start printing the console output to an external file (log)
logFileName = ['log_p7_anat_' date '.txt'];
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
    
    %---------------------
    % Get subject information
    %---------------------
    
    % Subject ID
    subj = subjList{i};
    
    % Subject image paths
    disp([subj ': Extracting image paths...'])
    func_path = [work_path filesep subj filesep 'func'];
    anat_path = [work_path filesep subj filesep 'anat'];
    
    %---------------------
    % 1. Coregister the anatomical image to the median resliced and UNWARPED image of echo 1
    %---------------------
    disp([subj ': Coregistering a copy of anatomical image to median image of unwarped, motion corrected and slice time corrected echo-1 images...'])
    
    % Get path to anatomical image and create a renamed copy of it
    t1w     = [anat_path filesep subj '_T1w.nii'];
    t1wCopy = [anat_path filesep subj '_T1w_orient-uepi.nii'];
    copyfile(t1w, t1wCopy);
     
    % Get path to reference image - median image of echo 1
    cd(func_path)
    ref = dir(['median' uprefix '*.nii']);
    if isempty(ref)
        error([subj ': Median echo-1 preprocessed functional image missing: check that previous scripts ran successfully'])
    end
    ref = ref.name;
    ref = [func_path filesep ref];
    
    % Set up batch to coregister the copy of T1w to the reference image
    matlabbatch = {};
    matlabbatch{1}.spm.spatial.coreg.estimate.ref = {ref};
    matlabbatch{1}.spm.spatial.coreg.estimate.source = {t1wCopy};
    matlabbatch{1}.spm.spatial.coreg.estimate.other = {''};
    matlabbatch{1}.spm.spatial.coreg.estimate.eoptions.cost_fun = 'nmi';
    matlabbatch{1}.spm.spatial.coreg.estimate.eoptions.sep = [4 2];
    matlabbatch{1}.spm.spatial.coreg.estimate.eoptions.tol = [0.02 0.02 0.02 0.001 0.001 0.001 0.01 0.01 0.01 0.001 0.001 0.001];
    matlabbatch{1}.spm.spatial.coreg.estimate.eoptions.fwhm = [7 7];

    % Run the batch
    spm_jobman('run', matlabbatch)
    
    % Double check that voxel-to-world matrix was updated
    v_before = spm_vol(t1w);
    v_after  = spm_vol(t1wCopy);
    disp([subj ': Voxel-to-world matrix before coregistration:'])
    disp(v_before.mat)
    disp([subj ': Voxel-to-world matrix after coregistration:'])
    disp(v_after.mat)
    disp([subj ': Coregistering anatomical image to median echo-1 functional image completed'])
    
    %---------------------
    % 2. Segment the anatomical image
    %    get forward deformation field
    %    get native space, DARTEL imported, and normalised tissue class images
    %    only save images of first three tissue classes (gm, wm, csf)
    %---------------------
    disp([subj ': Segmenting the coregistered T1 image...'])
    
    % Path to SPM tissue probability maps (a 4D file)
    tpm_path = [spm_path filesep 'tpm' filesep 'TPM.nii'];
    
    % Set up batch
    matlabbatch = {};
    matlabbatch{1}.spm.spatial.preproc.channel.vols = {t1wCopy};
    matlabbatch{1}.spm.spatial.preproc.channel.biasreg = 0.001;
    matlabbatch{1}.spm.spatial.preproc.channel.biasfwhm = 60;
    matlabbatch{1}.spm.spatial.preproc.channel.write = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(1).tpm = {[tpm_path ',1']};
    matlabbatch{1}.spm.spatial.preproc.tissue(1).ngaus = 2;       % Number of Gaussians set to 2 as suggested in SPM manual
    matlabbatch{1}.spm.spatial.preproc.tissue(1).native = [1 1];  % Saving both native space and DARTEL imported
    matlabbatch{1}.spm.spatial.preproc.tissue(1).warped = [1 0];  % Saving unmodulated MNI space version
    matlabbatch{1}.spm.spatial.preproc.tissue(2).tpm = {[tpm_path ',2']};
    matlabbatch{1}.spm.spatial.preproc.tissue(2).ngaus = 2;       % Number of Gaussians set to 2 as suggested in SPM manual
    matlabbatch{1}.spm.spatial.preproc.tissue(2).native = [1 1];
    matlabbatch{1}.spm.spatial.preproc.tissue(2).warped = [1 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(3).tpm = {[tpm_path ',3']};
    matlabbatch{1}.spm.spatial.preproc.tissue(3).ngaus = 2;
    matlabbatch{1}.spm.spatial.preproc.tissue(3).native = [1 1];
    matlabbatch{1}.spm.spatial.preproc.tissue(3).warped = [1 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(4).tpm = {[tpm_path ',4']};
    matlabbatch{1}.spm.spatial.preproc.tissue(4).ngaus = 3;
    matlabbatch{1}.spm.spatial.preproc.tissue(4).native = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(4).warped = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(5).tpm = {[tpm_path ',5']};
    matlabbatch{1}.spm.spatial.preproc.tissue(5).ngaus = 4;
    matlabbatch{1}.spm.spatial.preproc.tissue(5).native = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(5).warped = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(6).tpm = {[tpm_path ',6']};
    matlabbatch{1}.spm.spatial.preproc.tissue(6).ngaus = 2;
    matlabbatch{1}.spm.spatial.preproc.tissue(6).native = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(6).warped = [0 0];
    matlabbatch{1}.spm.spatial.preproc.warp.mrf = 1;
    matlabbatch{1}.spm.spatial.preproc.warp.cleanup = 1;
    matlabbatch{1}.spm.spatial.preproc.warp.reg = [0 0.001 0.5 0.05 0.2];
    matlabbatch{1}.spm.spatial.preproc.warp.affreg = 'mni';
    matlabbatch{1}.spm.spatial.preproc.warp.fwhm = 0;
    matlabbatch{1}.spm.spatial.preproc.warp.samp = 3;
    matlabbatch{1}.spm.spatial.preproc.warp.write = [0 1];

    % Run the batch
    spm_jobman('run', matlabbatch)
    disp([subj ': Segmenting the coregistered T1 image completed'])
    
    % Display total time taken
    time_taken = toc;
    disp([subj ': p7_preproc_anat: time taken:' ' ' num2str(time_taken/60) ' ' 'minutes =' ' ' num2str(time_taken/3600) ' ' 'hours'])
        
end  % Loop over subjects

% Stop logging console output
diary off
