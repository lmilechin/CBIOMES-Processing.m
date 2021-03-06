%% Running Pipeline on sample* directories
clear all

% Put tools on path
p = genpath([pwd '/../../tools/']);
addpath(p);

setup_pathsflds_cs510

switch sampleType
    case 'sample1'
        outputPrefix = 'ptr_3d_set1';
        nfaces = 5;
        fileformat = 'compact';
        timeInterval = 30;
    case 'sample2'
        outputPrefix = '3d';
        nfaces = 1;
        fileformat = 'straight';
    case 'cs510'
        outputPrefix = '_';
        nfaces = 6;
        fileformat = 'cube';
        subdirPrefix = 'res_';
        timeInterval = 3;
    otherwise
        disp('Not a valid sample type')
end

selectFld = {};
%% Read in the Grid
disp('Reading in the grid')

gcmfaces_global;
if isempty(mygrid)
    fprintf(['loading grid from ' dirGrid '\n']);
    grid_load(dirGrid,nfaces,fileformat);
end

%% Interpolate Groups

% get filenames from one directory to determine time steps- for checkpointing
dirOutput = strrep(dirOutput_pat,'sample',fldTbl.source{1});
linkDir = strrep(linkDir_pat,'sample',fldTbl.source{1});
if strcmp(sampleType,'cs510')
    fnames = dir(fullfile(linkDir,[subdirPrefix '0000'],[outputPrefix '*.data'])); 
    prefix = subdirPrefix;
    nsteps = length(fnames);
else
    fnames = dir(fullfile(linkDir,[outputPrefix '*.data']));
    prefix = outputPrefix;
end

% Setup for Slurm Job Array to run time steps concurrently otherwise will run in serial
if ~isempty(getenv('SLURM_ARRAY_TASK_ID')) 
    taskID = str2num(getenv('SLURM_ARRAY_TASK_ID'));
    numTasks = str2num(getenv('SLURM_ARRAY_TASK_COUNT'));
    dirOutput_pat = strrep(dirOutput_pat,'sample',['sample_' num2str(taskID)]);
else
    taskID = 1;
    numTasks = 1;
end

% Go over table of fields
for i = 1:height(fldTbl)

    % Set linkDir and dirOutput for field
    linkDir = strrep(linkDir_pat,'sample',fldTbl.source{i});
    dirOutput = strrep(dirOutput_pat,'sample',fldTbl.source{i});
    if ~exist(dirOutput,'dir')
       mkdir(dirOutput)
       system(['ln -s ' linkDir ' ' dirOutput filesep fldTbl.source{i}]);
    end
    
    % Move inter_precomputed.mat into diags_interp_tmp
    interptmpdir = fullfile(dirOutput,'diags_interp_tmp');
    if ~exist(interptmpdir,'dir'); mkdir(interptmpdir); end
    if ~exist(fullfile(interptmpdir,'interp_precomputed.mat'))
        interpPrecomp = fullfile(precomp_interp_dir,'interp_precomputed.mat');
        if exist(interpPrecomp,'file')
            copyfile(interpPrecomp,[interptmpdir filesep]);
        end
    end
    
    % Put a metadata file in dirOutput and set interpDir
    system(['cp ' linkDir '/*.meta ' dirOutput]);
    interpDir = strrep(interpDir_pat,'group',fldTbl.group_name{i});

    fldname = fldTbl.field{i};
    disp(['Processing ' fldname])
    
    % Remove any leftover potentially half-formed files
    if ~isempty(dir(fullfile(dirOutput,'diags_interp_tmp',fldname,'*.data')))
        system(['rm ' fullfile(dirOutput,'diags_interp_tmp',fldname,'*.data')])
    end
    if ~isempty(dir(fullfile(dirOutput,'diags_interp_tmp',fldname,'*.meta')))
        system(['rm ' fullfile(dirOutput,'diags_interp_tmp',fldname,'*.meta')])
    end
    
    % Interpolate fields
    if strcmp(sampleType,'cs510') || strcmp(sampleType,'sample3')
        
        fnames = dir(fullfile(linkDir,[subdirPrefix '0000'],[outputPrefix '*.data']));
        
        % Add line to Available Diagnostics file if it isn't already there
        if ~isempty(fldTbl.sourcefields{i})
            sourcefields = fldTbl.sourcefields{i};
            levs = fldTbl.levs{i};
            mate = fldTbl.mate{i};
            code = fldTbl.code{i};
            units = fldTbl.units{i};
            title = fldTbl.title{i};
            
            % Add to Diags
            fldname = addLineAvailDiag(diagnosticFile, fldname, levs, mate, code, units, title);
            selectFld = [selectFld fldname];
        else
            selectFld = [selectFld fldname];
        end
        
        if ~exist(fullfile(interpDir,fldname),'dir')
            mkdir(fullfile(interpDir,fldname));
        end
        
        % For checkpointing
        if taskID == 1
            fnames_done = dir([interpDir fldname filesep '*.meta']);

            for j = 1:length(fnames_done)
                fname_done = strrep(strrep(fnames_done(j).name,'.meta',''),fldname,'_');
                idx_done = contains({fnames.name},strrep(strrep(fnames_done(j).name,'.meta',''),fldname,'_'));
                disp(['Skipping ' fnames(idx_done).name])
                fnames(idx_done)=[];
            end
            
            nsteps = length(fnames);
            
            if ~isempty(getenv('SLURM_ARRAY_TASK_ID'))
                save([getenv('SLURM_ARRAY_JOB_ID') '_' fldname '_fnames.mat'],'fnames','nsteps');
            end
        else
            load([getenv('SLURM_ARRAY_JOB_ID') '_' fldname '_fnames.mat'])
        end

        % Set time indices for this task, if serial this is 1:nsteps
        myidx = taskID:numTasks:nsteps;
        
        for t = myidx
            
            fparts = strsplit(fnames(t).name,'.');
            iStep = str2double(fparts{2});
            
            if isempty(dir([interpDir fldname filesep '*' fparts{2} '.meta'])) || doInterpForce % Skip if already interpolated
                
                fldfname = strjoin(fparts(1:2),'.');

                % If this field already exists, read it in, otherwise create it
                if isempty(fldTbl.sourcefields{i})
                    fld = cs510readtiles(linkDir,outputPrefix,iStep,fldname);
                else
                    disp(['Creating ' fldname])
                    savename = strjoin(fparts(1:2),'.');
                    
                    dirNewFld = strrep(dirNewFld_pat,'sample',group(1).source);
                    
                    % Calculate new field
                    tic
                    if strcmp(lower(fldTbl.operation{i}),'sum')
                        fld = calcSum(linkDir,prefix,iStep,sourcefields);
                    elseif strcmp(lower(fldTbl.operation{i}),'shannon')
                        fld = calcShannon(linkDir,dirNewFld,'PhyTotal',prefix,iStep,sourcefields);
                    elseif strcmp(lower(fldTbl.operation{i}),'top50avebiomass')
                        [biomass0to50ave,chl0to50ave] = calcTop50AveBiomass(linkDir,prefix,iStep);
                    elseif strcmp(lower(fldTbl.operation{i}),'integral-full')
                        fld = calcIntegralFull(linkDir,prefix,iStep,sourcefields);
                    else
                        disp(['Unsupported operation ' fldTbl.operation{i}])
                    end
                    toc
                    
                    % Save to Output
                    if ~isdir(dirNewFld); mkdir(dirNewFld); end
                    [dims,prec,tiles]=cs510readmeta(linkDir);
                    
                    %write binary field (masked)
                    write2file(fullfile(dirNewFld,[savename '.' fldname '.data']),convert2vector(fld),32,0);
                    
                    %create meta file
                    write2meta(fullfile(dirNewFld,[savename '.' fldname '.data']),dims(1:length(size(fld.f1))),32,{fldname});
                    
                end

                % Interpolate
                disp(['Interpolating ' fldname])
                process2interp(dirOutput,outputPrefix,{fldname},fld,fldfname);
                
                system(['mv ' dirOutput filesep 'diags_interp_tmp/' fldname '/* ' fullfile(interpDir,fldname)]);
            else
                disp(['skipping ' fnames(t).name])
            end
            
        end
    end
    
end
