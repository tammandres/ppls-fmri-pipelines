%---------------------------------
% MULTI ECHO PREPROCESSING: Motion and slice timing correction
%
% NB. Image folders must be organised according to the BIDS 1.2.0 format
%     https://bids-specification.readthedocs.io/en/stable/
%
% Input
% - 4D time series of multiple echos, named analogously to
%  'sub-01_task-meaning_run-1_echo-1_bold.nii'
% - Metadata files of these time series, named analogously to 
%  'sub-01_task-meaning_run-1_echo-1_bold.json'
% - 'paths.mat' file that contains folder paths and some other relevant
%   variables, created by the 'step1_prepareEnvironment*.m' script
%
% Main outputs
% - Six motion parameters for each task-run combination in .txt files, prefix 'rp'
% - Plots of motion parameters, named analogously to 'sub-01_plot-motion.png'.
%   The plots show movements with respect to first image in each task-run combination 
%   (absolute displacement), and movements with respect to previous time point (relative displacement).
%   The latter is recommended in https://doi.org/10.1017/CBO9780511895029.004
%   and indicates how sudden the movements are.
% - List of volumes with large motion, named analogously to 'sub-01_outliers-motion.tsv'
% - Slice time corrected 4D time series of each echo, default prefix 'a'.
% - Realigned and slice time corrected time series of each echo, default prefix 'ra'.
%   The images from different task-run combinations and echos have same voxel size and orientation,
%   they are in the same "space".
%
% Method
% - Time series of echo-1 images are realigned (but not resliced) using spm_realign.
%   In this process, voxel-to-world matrices in headers of echo-1 images are updated.
%   If there are multiple task-run combinations (e.g. a single task with multiple runs,
%   or multiple tasks with at least 1 run each), all task-run combinations will be aligned to each other
% - The updated voxel-to-world matrices of each volume in echo 1 are
%   applied to the corresponding volumes in other echos, so that
%   corresponding images from all echos are realigned in the same way.
%   This was recommended by the developers of the multi-echo denoising algorithm
%   that will be used later in the pipeline:
%   https://tedana.readthedocs.io/en/latest/usage.html#constructing-me-epi-pipelines.
% - Time series of all echos are slice time corrected
% - Time series of all echos are resliced such that they will be in
%   the same space (using realignment parameters that were estimated previously)
% - Finally, the script adds the Repetition Time (TR) value back to the NIfTI headers
%   of preprocessed images: this seems to get lost when SPM functions are applied
%   and is necessary for the tedana denoising algorithm to produce diagnostic plots
%   If you disable this feature, you need to remove the '--png' flag from tedana calls
%   so that tedana would not try to create figures (in 'p4_tedana_main.py' script)
% - The script first reads in paths and variables from a "paths.mat" file:
%   work_path : path to a folder that contains subjects' image folders in BIDS format
%   spm_path  : path to SPM12 folder
%   code_path : path to a folder that contains these scripts (and the "paths.mat" file)
%   sprefix, rprefix : prefixes for slice-time and motion-corrected images
%   mode      : indicates whether to run the script for all subjects in "work_paths" (see below)
%   subs      : lists a subject IDs for which to run the script for (see below)
%   thrAbs, thrRel : thresholds for absolute and relative motion in millimeters/degrees. 
%      Horisontal lines will be drawn at these values in motion plots.
%      Volume numbers of images that cross these thresholds will be saved in a .tsv file.
%      E.g., if thrAbs = 2, then 2mm threshold is applied to translations and 2 degrees to rotations
%
% Notes
% - Slice times and Repetition Time (TR) are read from the .json metadata files.
% - If there are multiple subjects, they are processed in parallel using MATLAB's
%   parfor function
% - The script first unpacks 4D images to 3D, performs the procedures, and
%   then packs the images back to 4D. This is to avoid any potential issues that 
%   can arise with voxel-to-world matrices when SPM functions are applied to 4D images
%
% Author(s) : Andres Tamm (The University of Edinburgh), using functions from SPM12; 
%             motion plot legend code is based on snippets from SPM functions
% Software  : MATLAB R2018b, SPM12 v7219
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
%
% % Specify motion thresholds in millimeters/degrees
% % E.g., if thrAbs = 2, then 2mm threshold is applied to translations and 2 degrees to rotations.
% thrAbs = 3
% thrRel = 2

% Load the paths and variables necessary for running the script, see step0_prepare_environment.m
load('paths.mat')

% Add SPM and code folder to path
addpath(spm_path)
addpath(code_path)

% Start printing the console output to an external file (log)
logFileName = ['log_p1_func_' date '.txt'];
logFilePath = [work_path filesep logFileName];
diary(logFilePath);

% In slice timing correction, should time series be interpolated to TR/2 or
% to the middle slice in time?
%  If ref_tr = 1, then it is interpolated to TR/2
%  If ref_tr = 0, then interpolated to the actual middle slice
% The motivation for this option is the following: slice times of different
% subjects can differ by about 2.5 milliseconds, so if an actual slice is
% used as a reference slice, this will introduce very small differences
% between images of subjects. On the other hand, if TR/2 is chosen as the
% reference time, this will introduce slightly more interpolation error
% because TR/2 does not correspond to any real slice and thus all slices
% are interpolated.
ref_tr2 = 1;

% Do you have a multiecho dataset? 1 = yes, 0 = no
mecho = 1;

% Add TR back to the headers of slice time and motion corrected images? 1 = yes, 0 = no
% Without TR in the headers, tedana denoising workflow will not create
% diagnostic plots
addTR = 1;

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
    % Prepare functional images and collect information about scans 
    %---------------------

    % Go to func path
    cd(func_path)

    % Identify image files
    imgfiles  = dir('sub*_bold.nii');
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
    
    % Identify number of echos
    disp([subj ': Identifying echos...'])
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
    
    % Convert 4D images to corresponding 3D images: each cell of 4D images in imgfiles
    % will have a corresponding cell of 3D images in imgfiles3d
    disp([subj ': Converting 4D to 3D...'])
    imgfiles3d = imgfiles;
    for j = 1:nTaskRun
        for k = 1:necho
            tmp = imgfiles{taskRunIndex == taskRunLevels(j) & echoindex == echolevels(k)};
            vtmp = spm_file_split(tmp);
            imgfiles3d{taskRunIndex == taskRunLevels(j) & echoindex == echolevels(k)} = vertcat(vtmp.fname);
        end
    end

    % Extract imaging information (image metadata) for all images
    disp([subj ': Extracting imaging information for each image...'])
    imgmeta = cell(numel(imgfiles), 1);
    for j = 1:nTaskRun
        for k = 1:necho
            funcName = imgfiles{echoindex == echolevels(k) & taskRunIndex == taskRunLevels(j)};
            [~,fpart,~] = fileparts(funcName);
            jsonName = [fpart '.json'];
            str = fileread(jsonName); 
            scanInfo = jsondecode(str);  % struct that contains information about the scan
            imgmeta{echoindex == echolevels(k) & taskRunIndex == taskRunLevels(j)} = scanInfo;
        end
    end

    % Extract echo times
    echotimes = [];
    for k = 1:necho
        tmp = imgmeta{echoindex == k & taskRunIndex == 1};
        echotimes(1, k) = tmp.EchoTime*1000;
    end

    % Display echo times
    disp([subj ': Echo times are:'])
    disp(round(echotimes, 3))
    
    %---------------------
    % 1. Estimate realignment parameters for echo 1
    %---------------------

    % Message
    disp([subj ': Estimating realignment parameters for echo 1...'])
    
    % Extract echo-1 images for realignment
    v = imgfiles3d(echoindex == echolevels(1));
    
    % Realign the 3D volumes
    % Images of each task-run combination need to be in separate cells
    % Ref: https://github.com/neurodebian/spm12/blob/master/spm_realign.m
    flags     = {}; % necessary for a parallel for-loop to work
    flags.rtm = 1;  % use a two-pass procedure
    spm_realign(v, flags);

    % Get information (in SPM format) about the realigned volumes
    rvols = cell(1, numel(v));
    for j = 1:numel(v)
        rvols{j} = spm_vol(v{j});
    end

    %---------------------
    % 2. Apply realignment parameters from echo 1 to echos 2 and 3
    %---------------------
	
    % Skip this if you have only 1 echo
    if numel(echolevels) > 1

        % Create an empty matrix that will store logical tests for quality check
        test = [];

        % Update the volumes of each task-run combination
        for j = 1:nTaskRun

            % Message
            disp([subj ': Applying realignment parameters to other echos for task-run combination:' ' ' num2str(j)])

            % Get realigned volumes
            rvolsrun = rvols{j};

            % Extract the different echo images for k-th task-run combination, excluding echo 1
            imgrun = imgfiles3d(echoindex ~= 1 & taskRunIndex == taskRunLevels(j));

            % Update the voxel-to-world matrices of each echo 4D image
            for k = 1:numel(imgrun)

                % Read in the volumes of this task-run combination and echo
                volsrun = spm_vol(imgrun{k});

                % Update the voxel-to-world matrix of each 3D volume
                for l = 1:numel(volsrun)
                    spm_get_space(volsrun(l).fname, rvolsrun(l).mat);
                end

                % Double check that echos have same voxel-to-world matrices
                volsrun = spm_vol(vertcat(volsrun.fname));  % read in the images again to get updated v-t-m matrices
                test_k = [rvolsrun.mat] == [volsrun.mat];
                test_k = all(test_k(:));
                test(j, k) = test_k;
            end  % loop over different echos in each task-run combination
        end  % loop over task-run combinations

        % Quality check
        test = all(test(:));
        if test == 1
            disp([subj ': Quality check for applying realignment parameters passed'])
        else
            error([subj ': Quality check for realignment parameters failed: Check the code'])
        end
        
    end
	    
   %---------------------
    % 3. Plot motion parameters
    %---------------------

    % Message
    disp([subj ': Plotting motion parameters...'])

    % Get names of motion parameter files
    cd(func_path)
    motionfiles  = dir('rp*');
    motionfiles  = {motionfiles.name}';
    motiontables = cell(1, nTaskRun);
    
    % Read in motion parameters for each task-run combination
    % And also get ...
    %  *total number of volumes (parameters) per task-run combination nScanTaskRun)
    %  *volumes at task-run boundaries (boundInd)
    %  *vector that indicates volume number of each volume (volIdx)
    %  *vector that indicates run number of each volume (runIdx)
    %  *cell that indicates task label of each volume (taskIdx)
    % Note that on motion plots, all task-run combinations are combined on
    % a single axis (as if they were a big single run) and boundary lines
    % are drawn where each new task-run combination starts; the volIdx,
    % runIdx and taskIdx variables are useful for later identifying where
    % the outlier volumes are located
    cd(func_path)
    nScanTaskRun = [];
    boundInd     = [];
    volIdx       = [];
    runIdx       = [];
    taskIdx      = {};
    for k = 1:numel(motionfiles)
        
        % Read in the motion parameter table and store
        mtab = dlmread(motionfiles{k});
        motiontables{k} = mtab;
        
        % Get number of volumes and store
        nvol = size(mtab, 1);
        nScanTaskRun(k) = nvol;
        
        % Get indicator for run boundaries
        boundInd(k) = sum(nScanTaskRun(1:k)) + 1;
        
        % Get volume numbers (assuming ...)
        volIdx = vertcat(volIdx, [1:nvol]');
        
        % Get run numbers for each volume
        runNum = regexp(motionfiles{k},'run-(\d{1,2})', 'tokens');
        runNum = str2double(runNum{1});
        runIdx = vertcat(runIdx, ones(nvol, 1)*runNum);
        
        % Get task labels for each volume
        taskLabel  = regexp(motionfiles{k},'task-(.*)_run', 'once', 'tokens');
        taskValues = repmat(taskLabel, nvol, 1);
        taskIdx    = vertcat(taskIdx, taskValues);
        
    end
    nscan = sum(nScanTaskRun);
    scan  = 1:nscan;
    
    % Combine motion parameters of different runs into a single table
    motiondata = vertcat(motiontables{:});

    % Specify size of figure window
    set(gcf, 'Position',  [100, 100, 1000, 1000])
        
    % Plot absolute translation
    subplot(2,2,1)

        % Plot translation parameters
        translation = motiondata(:, 1:3);
        plot(scan, translation(:, 1), 'b', ...
             scan, translation(:, 2), 'g', ...
             scan, translation(:, 3), 'r')
        ylim([-(thrAbs+0.5) thrAbs+0.5]);
        xlim([0, max(scan)+1]);
        hold on

        % Add vertical lines that distinguish task-run combinations
        for k = 1:nTaskRun
            line([boundInd(k) boundInd(k)], [-(thrAbs+1) (thrAbs+1)], 'color', [0.8 0.8 0.8]);
        end

        % Add horizontal lines that distinguish allowable thresholds
        hline = refline([0 thrAbs]);
        hline.Color = 'k';
        hline = refline([0 -thrAbs]);
        hline.Color = 'k';
        hline = refline([0 0]);
        hline.Color = 'k';

        % Add title, axis labels, legend
        % Legend according to https://github.com/spm/spm12/blob/master/spm_realign.m
        title('Translation (absolute)')
        xlabel('Scan')
        ylabel('mm')
        labs  = {'x translation','y translation','z translation'};
        legend(labs, 'Location', 'best', 'color', 'none');

    % Plot absolute rotation (radians converted to degrees)
    subplot(2,2,2)

        % Plot rotation parameters
        rotationdeg = motiondata(:, 4:6)*360/(2*pi);
        plot(scan, rotationdeg(:, 1), 'b', ...
             scan, rotationdeg(:, 2), 'g', ...
             scan, rotationdeg(:, 3), 'r')
        ylim([-(thrAbs+0.5) thrAbs+0.5]);
        xlim([0, max(scan)+1]);
        hold on

        % Add vertical lines that distinguish task-run combinations
        for k = 1:nTaskRun
            pos = nScanTaskRun*k;
            line([boundInd(k) boundInd(k)], [-(thrAbs+1) (thrAbs+1)], 'color', [0.8 0.8 0.8]);
        end

        % Add horizontal lines that distinguish allowable thresholds
        hline = refline([0 thrAbs]);
        hline.Color = 'k';
        hline = refline([0 -thrAbs]);
        hline.Color = 'k';
        hline = refline([0 0]);
        hline.Color = 'k';

        % Add title and axis labels
        title('Rotation (absolute)');
        xlabel('Scan');
        ylabel('Degrees');
        labs  = {'pitch','roll','yaw'};
        legend(labs, 'Location', 'best', 'color', 'none');

    % Shorten index files to plot relative motion
    diffscan = scan;
    diffscan(end) = [];
    diffindex = taskRunIndex;
    diffindex(end) = [];

    % Plot relative translation, disinguishing runs
    subplot(2,2,3)

        % Plot translation parameters
        difftransl = diff(translation);
        plot(diffscan, difftransl(:, 1), 'b', ...
             diffscan, difftransl(:, 2), 'g', ...
             diffscan, difftransl(:, 3), 'r')
        ylim([-(thrRel+0.5) thrRel+0.5]);
        xlim([0, max(scan)]);
        hold on

        % Add vertical lines that distinguish task-run combinations
        for k = 1:nTaskRun
            pos = nScanTaskRun*k;
            line([boundInd(k) boundInd(k)], [-(thrAbs+1) (thrAbs+1)], 'color', [0.8 0.8 0.8]);
        end

        % Add horizontal lines that distinguish allowable thresholds
        hline = refline([0 thrRel]);
        hline.Color = 'k';
        hline = refline([0 -thrRel]);
        hline.Color = 'k';
        hline = refline([0 0]);
        hline.Color = 'k';
        
        % Add title, axis labels, legend
        % Legend according to https://github.com/spm/spm12/blob/master/spm_realign.m
        title('Translation (derivative)')
        xlabel('Scan')
        ylabel('mm')
        labs  = {'x translation','y translation','z translation'};
        legend(labs, 'Location', 'best', 'color', 'none');

    % Plot relative rotation (note that radians are converted to degrees)
    subplot(2,2,4)

        % Plot rotation parameters
        rotationdeg = motiondata(:, 4:6)*360/(2*pi);
        diffrot = diff(rotationdeg);
        plot(diffscan, diffrot(:, 1), 'b', ...
             diffscan, diffrot(:, 2), 'g', ...
             diffscan, diffrot(:, 3), 'r')
        ylim([-(thrRel+0.5) thrRel+0.5]);
        xlim([0, max(scan)]);
        hold on

        % Add vertical lines that distinguish task-run combinations         
        for k = 1:nTaskRun
            pos = nScanTaskRun*k;
            line([boundInd(k) boundInd(k)], [-(thrAbs+1) (thrAbs+1)], 'color', [0.8 0.8 0.8]);
        end

        % Add horizontal lines that distinguish allowable thresholds
        hline = refline([0 thrRel]);
        hline.Color = 'k';
        hline = refline([0 -thrRel]);
        hline.Color = 'k';
        hline = refline([0 0]);
        hline.Color = 'k';

        % Add title and axis labels
        title('Rotation (derivative)')
        xlabel('Scan')
        ylabel('Degrees')
        labs  = {'pitch','roll','yaw'};
        legend(labs, 'Location', 'best', 'color', 'none');

    % Add subject ID as the overall title of the plot
    name = subj;
    t = annotation('textbox', [0 0.9 1 0.1], ...
        'String', name, ...
        'EdgeColor', 'none', ...
        'HorizontalAlignment', 'center');
    t.FontSize = 14;
    t.FontWeight = 'bold';

    % Save the figure into that subject's directory
    saveas(gcf, [subj '_plot-motion.png'])

    % Close the figure
    close
    
    %--------
    % 4. Identify volumes with large motion
    %--------
    disp([subj ': Identifying motion outliers...'])
        
    % Combine into a single table
    motiondata = vertcat(motiontables{:});
        
    % Convert radians to degrees
    motiondata(:, 4:6) = motiondata(:, 4:6)*360/(2*pi);
        
    % Index motion outliers based on absolute motion
    indicators_abs = motiondata > thrAbs | motiondata  < -thrAbs;
    indicators_abs = sum(indicators_abs,2);
    
    % Index motion outliers based on relative motion
    motion_relative = diff(motiondata);
    indicators_rel = motion_relative > thrRel | motion_relative  < -thrRel;
    indicators_rel = sum(indicators_rel,2);
    
    % Adjust the relative motion indicator to match with scan numbers
    indicators_rel = vertcat(0, indicators_rel);
    
    % Combine indicators
    indicator = double(indicators_abs) + double(indicators_rel);
    indicator = indicator > 0;
         
    % Extract motion outliers
    motionoutliers = [taskIdx(indicator == 1) num2cell(runIdx(indicator == 1)) num2cell(volIdx(indicator == 1))];
    
    % Write to file
    % Variables need to be submitted separately to table() to avoid
    % transparency violation error in parfor loop
    t = table(motionoutliers(:,1), motionoutliers(:,2), motionoutliers(:,3));  % NB (:,1) needed to handle empty motionoutliers file
    t.Properties.VariableNames = {'task' 'run' 'volume'};
    tname1 = [subj '_outliers-motion.txt'];
    tname2 = [subj '_outliers-motion.tsv'];
    writetable(t, tname1, 'Delimiter', 'tab');
    movefile(tname1, tname2);

    %---------------------
    % 5. Slice timing correction
    %---------------------
    
    % Run slice timing correction separately for each task/run/echo combination
    disp([subj ': Running slice timing correction...'])
    for j = 1:numel(imgfiles3d)
        
        % Extract slice times
        slicetimes = imgmeta{j}.SliceTiming;
        slicetimes = transpose(slicetimes);  % as SPM requires 1*X array
        slicetimes = slicetimes*1000;        % convert to milliseconds
        
        % Specify additional slice timing parameters that SPM requires
        % 'timing' variable is specified as [0 TR] as slice order is specified in time units not scans
        TR     = scanInfo.RepetitionTime;  % Repetition time in seconds
        timing = [0 TR];                   % Timing argument of spm_slice_timing function
        %sprefix = 'a';                    % Prefix of slice time corrected image files
        
        % Identify the time of the reference slice
        if ref_tr2 == 1
            % Reference point for slice timing correction is TR/2
            refslice = (TR/2)*1000;
        elseif ref_tr2 == 0
            % Reference point for slice timing correction is the slice that is "middle in time"
            slicetimes_length = length(slicetimes);
            slicetimes_sorted = sort(slicetimes);
            if mod(slicetimes_length, 2) == 0
               refslice = slicetimes_sorted(slicetimes_length/2);
            else
               refslice = median(slicetimes);
            end
        else
            error('ref_tr2 argument specified incorrectly at the beginning of the script')
        end
        
        % Call spm_slice_timing
        spm_slice_timing(imgfiles3d{j}, slicetimes, refslice, timing, sprefix);
    end

    %---------------------
    % 6. Reslice the slice-time corrected and realigned images
    %---------------------
    
    % Get names of slice time corrected and (to-be) realigned images
    % I am adding prefixes to retain exactly the same array structure as
    % for uncorrected images
    imgfiles3dSlice = {};         % necessary for a parallel for-loop to work
	imgfiles3dSliceReslice = {};  % necessary for a parallel for-loop to work
    for j = 1:numel(imgfiles3d)
        tmp  = cellstr(imgfiles3d{j});
        tmp2 = cellstr(imgfiles3d{j});
        for k = 1:numel(tmp)
            [~,name, ext] = fileparts(tmp{k});
            tmp{k}  = [sprefix name ext];
            tmp2{k} = [rprefix sprefix name ext];
        end
        imgfiles3dSlice{j,1} = cell2mat(tmp);
        imgfiles3dSliceReslice{j,1} = cell2mat(tmp2);
    end
    
    % Reslice
    % Ref: https://github.com/spm/spm12/blob/master/spm_reslice.m
    % NB - all imgfiles to be resliced must be submitted at once so
    % that they will all be resliced into the same space
    disp([subj ': Reslicing the preprocessed images...'])
    flags = [];
    flags.prefix = rprefix;
    spm_reslice(imgfiles3dSlice, flags)
        
    % Check that all resliced images have same voxel size and orientation
    P = char(imgfiles3dSliceReslice);
    V = spm_vol(P);
    [test,~] = spm_check_orientations(V);
    if test == 1
        disp([subj ': Quality check for reslicing passed: images have same voxel size and orientation'])
    else
        error([subj ': Quality check for reslicing failed: Check the code'])
    end
    
    % Compute median functional image for echo 1 across all task-run combinations
    disp([subj ': Computing median image of preprocessed echo-1 images...'])
    img        = char(imgfiles3dSliceReslice(echoindex == echolevels(1)));
    outname    = ['median' rprefix sprefix subj '_task-all_run-all_echo-1.nii'];
    flags.dmtx = 1;
    f          = 'median(X)';
    spm_imcalc(img, outname, f, flags);
    
    % Compute mean functional image for echo 1 across all runs
    disp([subj ': Computing mean image of preprocessed echo-1 images...'])
    img        = char(imgfiles3dSliceReslice(echoindex == echolevels(1)));
    outname    = ['mean' rprefix sprefix subj '_task-all_run-all_echo-1.nii'];
    flags.dmtx = 1;
    f          = 'mean(X)';
    spm_imcalc(img, outname, f, flags);

    % Compute mean functional image across all task-run combinations and echos
%   disp([subj ': Computing mean image of preprocessed images...'])
% 	if necho ~= 1
% 		img        = char(imgfiles3dSliceReslice);
% 		outname    = ['mean' rprefix sprefix subj '_task-all_run-all_echo-all.nii'];
% 		flags.dmtx = 1;
% 		f          = 'mean(X)';
% 		spm_imcalc(img, outname, f, flags);
% 	end
    
    %---------------------
    % 7. Convert all images to 4D, delete 3D
    %---------------------
    for j = 1:numel(imgfiles)
        
        % Message
        disp([subj ': Merging 3D back to 4D for time series:' ' ' num2str(j)])
         
        % Delete original 4D images
        if exist(imgfiles{j}, 'file') == 2
            delete(imgfiles{j});
        end
            
        % Merge 3D into 4D
        mergename = [imgfiles{j}]; 
        spm_file_merge(imgfiles3d{j}, mergename);
        
        mergename = [sprefix imgfiles{j}]; 
        spm_file_merge(imgfiles3dSlice{j}, mergename);
        
        mergename = [rprefix sprefix imgfiles{j}]; 
        spm_file_merge(imgfiles3dSliceReslice{j}, mergename);
        
        % Delete all 3D
        for k = 1:size(imgfiles3d{j}, 1)
            if exist(imgfiles3d{j}(k,:), 'file') == 2
                delete(imgfiles3d{j}(k,:))
            end
            if exist(imgfiles3dSlice{j}(k,:), 'file') == 2
                delete(imgfiles3dSlice{j}(k,:))
            end
            if exist(imgfiles3dSliceReslice{j}(k,:), 'file') == 2
                delete(imgfiles3dSliceReslice{j}(k,:))
            end
        end
    end  % loop over 4D time series

    %---------------------
    % 8. Add TR back to image headers of preprocessed images (if requested)
    %---------------------
    imgfiles = [];
    TR = [];
    h = [];
    v = [];
    if addTR == 1
        
        % Get TR, assuming it is correctly specified in .json files
        TR = imgmeta{1}.RepetitionTime;
        
        % Get all preprocessed images
        imgfiles  = dir([rprefix sprefix 'sub*_bold.nii']);
        imgfiles  = {imgfiles.name}';
        
        for j = 1:numel(imgfiles)
      
            % Message
            disp([subj ': Adding TR to NIfTI header of preprocessed image number:' ' ' num2str(j)])

            % Read the header and data matrix of the NIfTI image
            h  = niftiinfo(imgfiles{j});
            v  = niftiread(h);
            
            % Add TR (the 4th pixel dimension)
            h.PixelDimensions(4) = TR;
            
            % Write the image with updated header into a temporary file
            % This is to avoid any issues with opening and writing to the
            % same image that can happen, for example, when using NiBabel
            niftiwrite(v, 'tmp.nii', h);
            
            % Replace the original image with the temporary file
            movefile('tmp.nii', imgfiles{j});
        end
    end

    % Display total time taken
    time_taken = toc;
    disp([subj ': p1_func: time taken:' ' ' num2str(time_taken/60) ' ' 'minutes =' ' ' num2str(time_taken/3600) ' ' 'hours'])
end  % loop over subjects

% Stop logging output
diary off
        
       
