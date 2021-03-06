function qc_odimh5
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Joshua Soderholm, Fugro ROAMES, 2017
%
% WHAT: applies several qc processed to odimh5-archive on s3
%(1) remove_cappi, uses min_vol_size to remove files
%(2) nowcasting_rename_flag, renames files in nowcasting format
%(3) timestamp_rename_flag, renames files missing seconds (old error)
%(4) duplicate_flag, removes duplicated using largest file
%(5) vol_count_flag, generates log containing number of volumes + step
%
% INPUT 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
try
%check if is deployed
if ~isdeployed
    addpath('/home/meso/dev/roames_weather/lib/m_lib');
    addpath('/home/meso/dev/roames_weather/etc');
    addpath('/home/meso/dev/shared_lib/jsonlab');
end
addpath('etc')

%configs
local_tmp_path   = 'tmp/';
local_log_path   = 'log';
config_input_fn  = 'qc.config';
global_config_fn = 'global.config';

%ensure temp directory exists
if exist(local_tmp_path,'file') ~= 7
    mkdir(local_tmp_path)
end

%ensure log directory exists
if exist(local_log_path,'file') == 7
    disp('old log folder renamed')
    movefile(local_log_path,[local_log_path,'_',datestr(now,'yyyymmdd_HHMMSS')]);
end
mkdir(local_log_path)

% Load global config files
read_config(global_config_fn);
load([local_tmp_path,global_config_fn,'.mat'])

%load qc config file
read_config(config_input_fn);
load([local_tmp_path,'/',config_input_fn,'.mat'])

%init vars
prefix_cmd     = 'export LD_LIBRARY_PATH=/usr/lib; ';
year_list      = [year_start:1:year_stop];

%use generate list for all radar
if strcmp(radar_id_list,'all')
    radar_id_list = [1:99];
end

%loop through each year
for i=1:length(year_list)
    %loop through each radar
    for j=1:length(radar_id_list)
        %set path to odimh5 data (id/year)
        s3_odimh5_path = [s3_odimh5_root,num2str(radar_id_list(j),'%02.0f'),'/',num2str(year_list(i))];
        %get listing
        display(['s3 ls for: ',s3_odimh5_path])
        cmd         = [prefix_cmd,'aws s3 ls ',s3_odimh5_path,' --recursive'];
        [sout,eout] = unix(cmd);
        if isempty(eout)
            display(['no files for ',s3_odimh5_path]);
            continue
        end
        %read s3 listing
        C           = textscan(eout,'%*s %*s %u %s');
        h5_name     = C{2};
        h5_size     = C{1};
        
        %% (1) remove empty files (smaller than 10kB)
        if remove_cappi == 1
            disp('removing cappi files')
            remove_idx = [];
            for k = 1:length(h5_name)
                %check for cappi files using size
                if h5_size(k) < empty_vol_size
                    %remove these files
                    disp([h5_name{k},' of size ',num2str(h5_size(k)),' removed'])
                    file_rm([s3_bucket,h5_name{k}],0,1)
                    pause(0.1)
                    utility_aws_wait(200)
                    remove_idx = [remove_idx,k];
                end
            end
            %remove deleted files
            h5_name(remove_idx)  = [];
            h5_size(remove_idx)  = [];
        end

        %% (2) remove seconds to create volume time
        if timestamp_rename_flag == 1
            disp('renaming filenames to remove seconds')
            %rename volumes to remove seconds
            for k = 1:length(h5_name)
                h5_ffn = [s3_bucket,h5_name{k}];
                [h5_path,h5_fn,h5_ext] = fileparts(h5_ffn);
                %skip files with 00 seconds
                if strcmp(h5_fn(end-1:end),'00')
                    %display('file already renamed, skipping')
                    continue
                end
                new_fn      = [h5_fn(1:end-2),'00',h5_ext];
                new_ffn     = [h5_path,'/',new_fn];
                %if new ffn is different, mv to rename
                disp(['renaming ',h5_ffn,' to remove seconds'])
                cmd         = [prefix_cmd,'aws s3 mv ',h5_ffn,' ',new_ffn,' >> log.mv 2>&1 &'];
                [sout,eout] = unix(cmd);
                h5_name{k}  = [h5_path,'/',new_fn];
                pause(0.1)
                utility_aws_wait(200)
            end
        end

        %% (3) rename incorrect (nowcast filenames in yyyymmddHHMMSS)
        if nowcasting_rename_flag == 1
            disp('renaming nowcast server files')
            for k = 1:length(h5_name)
                h5_ffn = [s3_bucket,h5_name{k}];
                [h5_path,h5_fn,~] = fileparts(h5_ffn);
                if strcmp(h5_fn(3),'_')
                    %display('file already renamed, skipping')
                    continue
                end
                h5_date     = datenum(h5_fn(1:14),'yyyymmddHHMMSS');
                new_tag     = [num2str(radar_id_list(j),'%02.0f'),'_',datestr(h5_date,'yyyymmdd'),'_',datestr(h5_date,'HHMMSS'),'.h5'];
                new_ffn     = [h5_path,'/',new_tag];
                cmd         = [prefix_cmd,'aws s3 mv ',h5_ffn,' ',new_ffn,' >> log.mv 2>&1 &'];
                disp(['renaming ',h5_ffn,' to remove nowcast filename'])
                pause(0.1)
                utility_aws_wait(200)
                [sout,eout] = unix(cmd);
                h5_name{k}  = [h5_path,'/',new_tag];
            end
        end
        %% (4) remove duplicates by removing seconds and comparing size
        if duplicate_flag == 1
            %create file name without seconds to check for unique files
            disp('removing duplicates')
            h5_name_custom = cell(length(h5_name),1);
            for k=1:length(h5_name)
                h5_name_custom{k} = [h5_name{k}(1:end-5)]; %remove seconds
            end
            [uniq_h5_name,~,ic] = unique(h5_name_custom);
            out_h5_name        = cell(length(uniq_h5_name),1);
            out_h5_size        = zeros(length(uniq_h5_name),1);
            for k=1:length(uniq_h5_name)
                duplicate_idx           = find(ic==k);
                %skip is no duplicates
                if length(duplicate_idx)<2
                    out_h5_size(k) = h5_size(duplicate_idx);
                    out_h5_name(k) = h5_name(duplicate_idx);
                    continue
                end
                %find size and sort
                [duplicate_sz,sort_idx] = sort(h5_size(duplicate_idx),'descend');
                duplicate_idx           = duplicate_idx(sort_idx);
                %write largest size to matrix
                out_h5_size(k) = h5_size(duplicate_idx(1));
                out_h5_name(k) = h5_name(duplicate_idx(1));
                %remove files less than the largest
                for l = 2:length(duplicate_sz)
                    cmd             = [prefix_cmd,'aws s3 rm ',s3_bucket,h5_name{duplicate_idx(l)},' &'];
                    [sout,eout]     = unix(cmd);
                    pause(0.1)
                    utility_aws_wait(200)
                    display(['removing ',h5_name{duplicate_idx(l)}])
                end
            end
            h5_name = out_h5_name;
            h5_size = out_h5_size;
        end
           
        %% (5) generate vol_count log
        if vol_log_flag == 1
            %generate a log file that contains three columns,
            %[yyyymmdd,vol_count,vol_count_with_size_threshold,mode_step];
            %build h5_Date
            disp('running vol count log')
            date_list = zeros(length(h5_name),1);
            for k = 1:length(h5_name)
                h5_ffn       = [s3_bucket,h5_name{k}];
                [~,h5_fn,~]  = fileparts(h5_ffn);
                try
                    date_list(k) = datenum(h5_fn(4:end),'yyyymmdd_HHMMSS');
                catch
                    keyboard %WHY?
                end
            end
            %generate dateonly and uniq lists
            dateonly_list       = floor(date_list);
            index_date_list     = datenum(year_list(i),1,1):datenum(year_list(i),12,31);
            vol_count_list      = zeros(length(index_date_list),1);
            vol_size_count_list = zeros(length(index_date_list),1);
            vol_size_var        = zeros(length(index_date_list),1);
            vol_step_list       = zeros(length(index_date_list),1);
            vol_video_list      = zeros(length(index_date_list),1);
            %for each unique date, count the number of volumes ang the
            %number of steps
            for k = 1:length(index_date_list)
                %count number of volumes
                daily_mask             = dateonly_list == index_date_list(k);
                date_subset            = date_list(daily_mask);
                if isempty(date_subset); continue; end
                size_subset            = h5_size(daily_mask);
                vol_count_list(k)      = length(date_subset);
                vol_size_count_list(k) = sum(size_subset>=thresh_vol_size);
                vol_size_var(k)        = round(mean(size_subset(2:end)-size_subset(1:end-1)));
                %calc radar step
                if length(date_subset) > 1
                    vol_diff          = round((date_subset(2:end)-date_subset(1:end-1))*24*60);
                    vol_step          = mode(vol_diff);
                    if vol_step > 10
                        vol_step = 10;
                    end
                else
                    vol_step = 10; %default
                end
                vol_step_list(k) = vol_step;
                % (6) generate index of video levels using first file for a radar day
                if vol_log_video_flag == 1
                    first_vol_idx = find(daily_mask,1,'first');
                    first_vol_ffn = h5_name{first_vol_idx};
                    try
                        file_cp([s3_bucket,first_vol_ffn],[tempdir,'tempodim.h5'],0,0)
                        vol_video_list(k) = h5readatt([tempdir,'tempodim.h5'],'/dataset1/data1/how','rapic_VIDRES');
                    catch err
                        disp(err)
                        vol_video_list(k) = 0;
                    end
                end                      
            end
            %write to log file
            log_fn = [local_log_path,'/vol_count_',num2str(radar_id_list(j),'%02.0f'),'.log'];
            fid = fopen(log_fn,'at');
            for k = 1:length(index_date_list)
                fprintf(fid,'%s %d %d %d %d %d \n',datestr(index_date_list(k),'yyyymmdd'),vol_count_list(k),vol_size_count_list(k),vol_step_list(k),vol_size_var(k),vol_video_list(k));
            end
        end
    end
end
display(['qc complete for ',num2str(radar_id_list)])
utility_pushover('qc_odimh5',['qc complete for ',num2str(radar_id_list)])
catch err
    utility_pushover('qc_odimh5',['qc CRASHED for ',num2str(radar_id_list)])
    rethrow(err)
end

function utility_aws_wait(limit)

%wait for aws processes to finish
while true
    [~,eout] = unix('pgrep aws | wc -l');
    if str2num(eout)>limit
        pause(0.2);
        disp(['aws jobs running: ',eout,' , waiting']);
    else
        break
    end
end
