%---------------------------------
% MULTI ECHO PREPROCESSING: Get grey-plus-white matter mask in EPI space
% This mask will be used later to create a mask for multi-echo denoising
%
% NB. Image folders must be organised according to the BIDS 1.2.0 format
%     https://bids-specification.readthedocs.io/en/stable/
%
% Input
%  - Anatomical T1 image, named analogously to 'sub-01_T1w.nii'
%  - Median echo-1 preprocessed functional image, 
%    named similarly to 'medianrasub-01_task-sentence_run-all_echo-1_bold_00001.nii'
%    That image will be created when running the p1_func*.m script
%  - 'paths.mat' file that contains folder paths and some other relevant
%    variables, created by the 'step1_prepareEnvironment*.m' script
%
% Main outputs
%  - A copy of the T1 image, coregistered to median preprocessed echo-1 functional image,
%    named analogously to 'sub-01_T1w_orient-epi.nii'.
%  - Grey-plus-white matter mask in the space of the median preprocessed functional image, 
%    named analogously to 'sub-01_mask-gmwm_space-epi_spm.nii'
%
% Method
%  - A copy of the T1 image will be first created, named 'sub-01_T1w_orient-epi.nii'
%  - Copy of the T1 will be coregistered to the median functional image using SPM batch
%  - Coregistered T1 image will be segmented using SPM batch,
%    number of Gaussians set to 2
%  - The resulting grey and white matter tissue class images ('c1*' and 'c2*') 
%    will be combined to a single mask using spm_imcalc,
%    'sub-01_mask-gmwm_orient-epi_spm.nii'
%  - The grey-plus-white matter mask will then be resliced to the space
%    of median functional image using spm_reslice and trilinear interpolation
%    and thresholded at 0.25 to binarise it. The output will be named similarly to
%    'sub-01_mask-gmwm_space-epi_spm.nii'
%
% Author   : Andres Tamm (The University of Edinburgh), using functions from SPM12
% Software : MATLAB R2018a, SPM12 v7487
%---------------------------------

%% Input - make changes here to run the script on another machine

% % Clear the workspace
% clear variables;
%  
% % Set path to 'derivatives' folder
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

% Load the paths and variables necessary for running the script, see step0_prepare_environment.m
load('paths.mat')

% Add SPM and code folder to path
addpath(spm_path)
addpath(code_path)

% Start printing the console output to an external file (log)
logFileName = ['log_p2_gmwm_' date '.txt'];
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
    disp([subj ': Extracting image paths'])
    func_path = [work_path filesep subj filesep 'func'];
    anat_path = [work_path filesep subj filesep 'anat'];
    
    %---------------------
    % 1. Coregister the anatomical image to the median resliced image of echo 1
    %---------------------
    disp([subj ': Coregistering a copy of anatomical image to median image of motion corrected and slice time corrected echo-1 images...'])
    
    % Get path to anatomical image and create a renamed copy of it
    t1w     = [anat_path filesep subj '_T1w.nii'];
    t1wCopy = [anat_path filesep subj '_T1w_orient-epi.nii'];
    copyfile(t1w, t1wCopy);
    
    % Get path to reference image - median image of echo 1
    cd(func_path)
    ref = dir(['median' rprefix '*echo-1*.nii']);
    if isempty(ref)
        error([subj ': Median echo-1 functional image missing: check that previous scripts ran successfully'])
    else
        ref = ref.name;
    end
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
    % 2. Segment the anatomical image to get three tissue class images in native space
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
    matlabbatch{1}.spm.spatial.preproc.tissue(1).native = [1 0];  % Saving only a native space image
    matlabbatch{1}.spm.spatial.preproc.tissue(1).warped = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(2).tpm = {[tpm_path ',2']};
    matlabbatch{1}.spm.spatial.preproc.tissue(2).ngaus = 2;       % Number of Gaussians set to 2 as suggested in SPM manual
    matlabbatch{1}.spm.spatial.preproc.tissue(2).native = [1 0];  % Saving only a native space image
    matlabbatch{1}.spm.spatial.preproc.tissue(2).warped = [0 0];
    matlabbatch{1}.spm.spatial.preproc.tissue(3).tpm = {[tpm_path ',3']};
    matlabbatch{1}.spm.spatial.preproc.tissue(3).ngaus = 2;       % Number of Gaussians set to 2 as suggested in SPM manual
    matlabbatch{1}.spm.spatial.preproc.tissue(3).native = [1 0];  % Saving only a native space image
    matlabbatch{1}.spm.spatial.preproc.tissue(3).warped = [0 0];
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
    matlabbatch{1}.spm.spatial.preproc.warp.write = [0 0];  % do not save deformation fields here

    % Run the batch
    spm_jobman('run', matlabbatch)
    disp([subj ': Segmenting the coregistered T1 image completed'])
    
    %---------------------
    % 3. Create grey matter plus white matter mask in EPI space
    %    Precisely, in the space of minimally preprocessed EPI images (rasub*)
    %---------------------
    
    % Message
    disp([subj ': Creating a grey-plus-white matter mask...'])
    
    % Combine tissue class images into a brain mask
    % Here, I use tissue classes that are already in MNI space, with the 'wc*' prefix
    cd(anat_path)
    c1 = ['c1' subj '_T1w_orient-epi.nii'];
    c2 = ['c2' subj '_T1w_orient-epi.nii'];
    c  = [c1; c2];
    bmask = [subj '_mask-gmwm_orient-epi_spm.nii'];
    spm_imcalc(c, bmask, '(i1 + i2)>0');
        
    % Reslice the brain mask to be in the space of functional images
    % Ref: https://github.com/spm/spm12/blob/master/spm_reslice.m
    cd(func_path)
    ref = dir(['median' rprefix sprefix '*.nii']);
    ref = ref.name;
    ref = [func_path filesep ref];
    images = {ref bmask};
    
    cd(anat_path)
    flags = struct();
    flags.prefix = 'r';
    flags.which  = 1;  % don't reslice the first image (reference image)
    flags.mean   = 0;  % don't write mean image
    flags.interp = 1;  % use trilinear (note that nearest neighbour is option 0)
    spm_reslice(images, flags);
        
    % Rename the brain mask image
    bmaskNew = [subj '_mask-gmwm_space-epi_spm.nii'];
    movefile(['r' bmask], bmaskNew);
    
    % Binarise
    spm_imcalc(bmaskNew, bmaskNew, 'i1>0.25');
        
    % Double check that brain mask has same dimensions as reference image
    t1 = spm_vol(bmaskNew);
    t2 = spm_vol(ref);
    disp([subj ': Dimensions of brain mask are:'])
    disp(t1.dim)
    disp([subj ': Dimensions of reference image (median preprocessed echo-1 image) are:'])    
    disp(t2.dim)

    % Double check that brain mask is binary
    disp([subj ': Voxels in the brain mask take values:'])   
    unique(spm_read_vols(t1))
    
    % Display total time taken
    time_taken = toc;
    disp([subj ': p2_gmwm: time taken:' ' ' num2str(time_taken/60) ' ' 'minutes =' ' ' num2str(time_taken/3600) ' ' 'hours'])
    
end  % Loop over subjects

% Stop logging console output
diary off
