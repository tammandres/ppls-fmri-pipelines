%---------------------------------
% MULTI ECHO PREPROCESSING: folder paths and other settings
%
% Input
%  - Specify folder paths on the computer cluster, so that other
%    preprocessing scripts can find the brain images
%  - Additional settings for the preprocessing scripts, such as prefixes
%    attached to preprocessed images, echo times for TE-dependent analysis,
%    smoothing kernel FWHM for spatial smoothing, blip-direction for
%    unwarping, thresholds for identifying motion outliers.
%
% Output
%  - 'paths.mat' file in the '[studyFolder]/code' folder that contains
%    these paths and variables.
%
% Author   : Andres Tamm
% Software : MATLAB R2018a
%---------------------------------

%% Clear the workspace
clear variables;

%% Specify settings inside a struct "S"

% Initialise
S = struct();

% Specify echo times here as a character object
S.echotimes = '13.00 31.26 49.52';

% Specify prefixes of preprocessed images
S.sprefix      = 'a'; % slice timing correction prefix
S.rprefix      = 'r'; % realignment prefix
S.uprefix      = 'u'; % unwarp prefix
S.nprefix      = 'w'; % normalisation prefix
S.smoothPrefix = 's'; % smoothing prefix (smoothing kernel size will be appended to it)

% Specify smoothing kernels here in a cell format
% Must be a cell array of integers, e.g. s = {4 8 12}
S.s = {4 8};

% Specify blip direction (must be 1 or -1) for Voxel Displacement Map calculation
S.blipdir = 1;

% Specify path to 'derivatives' folder on the cluster
%   Replace my university username (atamm2) with yours
%   NB, file paths on the CLUSTER must contain right dashes '/', not '\'
%   Later, when you are running the script "step2_copy2cluster", you are
%   creating these folders on the cluster
S.work_path = '/exports/eddie/scratch/[userName]/[clusterStudyFolder]/derivatives';

% Specify path to 'SPM' folder on the cluster
S.spm_path = '/exports/eddie/scratch/[userName]/[clusterStudyFolder]/spm12_v7487/';

% Specify path to 'code' folder on the cluster
S.code_path = '/exports/eddie/scratch/[userName]/[clusterStudyFolder]/code/';

% Specify path to 'code' folder in your study folder
S.code_path_local = 'Z:\[localStudyFolder]\code';

% Specify if you are running your scripts to all or some subjects
%  mode = 'all'    : to run the script for all subjects
%  mode = 'subset' : to run the script for a subset of subjects
%
%  If you choose mode = 'subset', you must specify the IDs of subjects in a
%  'subs' variable. It must be a column cell of strings. For example:
%  subs = {'sub-01'; 'sub-02'; 'sub-10'};
%  Note that if mode = 'all', subs variable will be ignored
S.mode = 'all';
S.subs = {'sub-01'; 'sub-03'; 'sub-04'};

% Specify thresholds for absolute and relative motion in millimeters/degrees. 
% Horisontal lines will be drawn at these values in motion plots.
% Volume numbers of images that cross these thresholds will be saved in a .tsv file.
% E.g., if thrAbs = 2, then 2mm threshold is applied to translations and 2 degrees to rotations
S.thrAbs = 3;
S.thrRel = 2;

%% Save the environment variables

% Message
disp('Running step1_prepareEnvironment with settings:');
disp(S);

% Save variables into a .mat file
cd(S.code_path_local)
fname = 'paths.mat';
save(fname, '-struct','S');
