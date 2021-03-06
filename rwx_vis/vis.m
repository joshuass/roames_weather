function vis
try
%WHAT: This module pulls data from storm_archive and create kml objects for
%GE

%INPUT:
%see wv_kml.config

%OUTPUT: kml visualisation of selected mat file archive

% general vars
vis_config_fn     = 'vis.config';
global_config_fn  = 'global.config';
restart_vars_fn   = 'tmp/vis_restart_vars.mat';
local_tmp_path    = 'tmp/';
pushover_flag     = 1;
transform_path    = [local_tmp_path,'transforms/'];
kmlobj_struct     = [];
vol_struct        = [];
storm_jstruct     = [];
radar_id_list     = [];
restart_tries     = 0;
restart_flag      = false;
%init tmp path
if exist(local_tmp_path,'file') ~= 7
    mkdir(local_tmp_path)
end
    
% setup kill time (restart program to prevent memory fragmentation)
kill_wait  = 60*60*2; %kill time in seconds
kill_timer = tic; %create timer object
unix('touch tmp/kill_vis');

% Add folders to path and read config files
if isdeployed
    addpath('etc/geo_data')
    addpath('etc')
    addpath('etc/impact_maps')
    addpath('tmp')
    addpath('py_lib')
else
    addpath('/home/meso/dev/roames_weather/lib/m_lib')
    addpath('/home/meso/dev/roames_weather/lib/ge_lib')
    addpath('/home/meso/dev/shared_lib/jsonlab')
    addpath('/home/meso/dev/roames_weather/etc')
    addpath('/home/meso/dev/roames_weather/rwx_vis/etc/geo_data')
    addpath('/home/meso/dev/roames_weather/bin/json_read')
    addpath('/home/meso/dev/roames_weather/rwx_vis/etc')
    addpath('/home/meso/dev/roames_weather/rwx_vis/etc/impact_maps')
    addpath('/home/meso/dev/roames_weather/rwx_vis/tmp')
    addpath('/home/meso/dev/roames_weather/rwx_vis/py_lib')
end

% load kml_config
read_config(vis_config_fn);
load([local_tmp_path,vis_config_fn,'.mat'])

%clear tmp
delete('/tmp/*dae')
delete('/tmp/*kml')
delete('/tmp/*png')

%init download path
if exist(download_path,'file')~=7
    mkdir(download_path);
end

%build paths strings
if local_dest_flag==1
    dest_root = local_dest_root;
else
    dest_root = s3_dest_root;
end

%load colourmaps for png generation
utility_colormap_interp('refl24bit.txt','vel24bit.txt');

% Load global config files
read_config(global_config_fn);
load([local_tmp_path,global_config_fn,'.mat'])

% site_info.txt
if realtime_flag == 0 %radar_id_list will always be a single and list of int
    site_warning = read_site_info(site_info_fn,site_info_moved_fn,radar_id_list,datenum(date_start,ddb_tfmt),datenum(date_stop,ddb_tfmt),0);
    if site_warning == 1
        disp('site id list and contains ids which exist at two locations (its been reused or shifted), fix using stricter date range (see site_info_old)')
        return
    end
else
    [~] = read_site_info(site_info_fn);
end
load([local_tmp_path,site_info_fn,'.mat']);
% check if all sites are needed
if strcmp(radar_id_list,'all')
    radar_id_list = siteinfo_id_list;
end

%load ignore radar id list for realtime data
if realtime_flag == 1
    %read ignore list
    fid = fopen(site_info_ignore_fn);
    ignore_list = textscan(fid, '%f %*s','CommentStyle','#','MultipleDelimsAsOne',true); ignore_list=ignore_list{1};
    fclose(fid);
    %apply ignore list
    radar_id_list = setxor(radar_id_list,ignore_list);
end

%init vars
% check for restart or first start
if exist(restart_vars_fn,'file')==2
    %silent restart detected, load vars from reset and remove file
    try
        %attempt to load restart vars
        load(restart_vars_fn);
        delete(restart_vars_fn);
    catch
        %corrupt file
        delete(restart_vars_fn);
        vis_build_kml(dest_root,radar_id_list,local_dest_flag);
    end
else
    %build root kml
    vis_build_kml(dest_root,radar_id_list,local_dest_flag);
    %clear impact maps folder
    rmdir(impact_tmp_root,'s')
end

%build asset data
asset_data(asset_data_fn)

% Preallocate regridding coordinates
if radar_id_list == mobile_id
    preallocate_mobile_grid(radar_id_list,transform_path,force_transform_update)
else
    preallocate_radar_grid(radar_id_list,transform_path,force_transform_update)
end


%% Primary code
%cat daily databases for times between oldest and newest time,
%allows for mulitple days to be joined
%profile clear
%profile on

while exist('tmp/kill_vis','file')==2
    
    %pause
    disp('pausing for 5s')
    pause(5)
    
    % Calculate time limits from time options
    if realtime_flag == 1
        oldest_time = addtodate(utility_utc_time,realtime_length,'hour');
        newest_time = utility_utc_time;
    else
        oldest_time = datenum(date_start,ddb_tfmt);
        newest_time = datenum(date_stop,ddb_tfmt);
    end
    
    %% download odimh5/storm data
    %empty download path
    delete([download_path,'*'])
    %read staging index
    if realtime_flag == 1
        [download_odimh5_list,odimh5_datelist,odimh5_radaridlist] = sqs_process_staging(sqs_odimh5_process,oldest_time,newest_time,radar_id_list);
        download_stormh5_list                                     = ddb_filter_stormh5(storm_ddb_table,odimh5_datelist,odimh5_radaridlist);
    else
        download_odimh5_list   = s3_ls_filter(odimh5_s3_bucket,oldest_time,newest_time,radar_id_list);
        date_id_list           = floor(oldest_time):1:floor(newest_time);
        download_stormh5_list  = ddb_filter_index(storm_ddb_table,'date_id',date_id_list,'sort_id',oldest_time,newest_time,radar_id_list);
    end
    if isempty(download_odimh5_list)
        %break on no odimh5 data
        disp('download_odimh5_list is empty')
        continue
    end
    download_list = [download_odimh5_list;download_stormh5_list];
    for i=1:length(download_list)
        %download data file and untar into download_path
        display(['s3 cp of ',download_list{i}])
        file_cp(download_list{i},download_path,0,1);
    end
    %wait for aws processes to finish
    utility_aws_wait
    
    %% update vol object
    vol_struct                   = update_vol_struct(vol_struct,download_odimh5_list,download_path,oldest_time);
    vol_proced_idx               = find([vol_struct.proced]==false);

    %% clean kmlobj_struct
    [kmlobj_struct,remove_radar_id] = clean_kmlobj_struct(kmlobj_struct,oldest_time);
    
    %% check for new volumes or removed kml
    update_radar_id_list            = unique([[vol_struct(vol_proced_idx).radar_id],remove_radar_id]);
    if isempty(update_radar_id_list)
        %no new updates are required, continue while loop
        continue
    end
    
    %% Update storm object
    storm_jstruct                   = update_storm_jstruct(storm_jstruct,download_stormh5_list,download_path,oldest_time);
    %% process current volumes to kml objects and generate masking
    %loop through radar id list
    for i=1:length(vol_proced_idx)
        %update proced flag
        vol_struct(vol_proced_idx(i)).proced = true;
        %extract file vars
        radar_id               = vol_struct(vol_proced_idx(i)).radar_id;
        start_timestep         = vol_struct(vol_proced_idx(i)).start_timestamp;
        odimh5_ffn             = vol_struct(vol_proced_idx(i)).local_odimh5_ffn;
        %extract radar timestep
        radar_step             = utility_radar_step(vol_struct,radar_id);
        %create domain mask
        [ppi_mask,geo_coords]  = process_radar_mask(radar_id,start_timestep,vol_struct,transform_path);
        %create ppi kml (also generate impact map data for single doppler)
        kmlobj_struct          = vis_odimh5(kmlobj_struct,odimh5_ffn,ppi_mask,radar_id,radar_step,dest_root,transform_path,options);
        %create mask information for storm cells in storm_jstruct
        storm_jstruct          = mask_storm_cells(radar_id,start_timestep,storm_jstruct,ppi_mask,geo_coords);
    end
    
    %% process storm and track objects
    if ~isempty(storm_jstruct)
        %remove storm entries outside of domain
        filt_mask          = utility_jstruct_to_mat([storm_jstruct.domain_mask],'N');
        storm_jstruct_filt = storm_jstruct(logical(filt_mask));
        if ~isempty(storm_jstruct_filt)
            %generate storm tracking
            track_id_list  = nowcast_wdss_tracking(storm_jstruct_filt,vol_struct,true);

            %use tracks, cell masks to generate storm and track kml
            kmlobj_struct  = vis_storm(kmlobj_struct,vol_struct,storm_jstruct_filt,track_id_list,dest_root,transform_path,options);

            %mark everything as processed in original storm_struct
            proced_idx            = find([storm_jstruct.proced]==false);
            for i=1:length(proced_idx)
                storm_jstruct(proced_idx(i)).proced = true;
            end
        else
            %no storm objects inside domain mask, so track list is empty
            track_id_list  = [];
        end
    else
        %no storm objects
        storm_jstruct_filt = [];
        track_id_list      = [];
    end
    
    %check for restart and force update for all radar ids (fixes crash
    %issues with data)
    if restart_flag
        restart_flag         = false;
        update_radar_id_list = radar_id_list;
    end
    
    %update kml from kmlobj_struct
    vis_update_nl(kmlobj_struct,storm_jstruct_filt,track_id_list,dest_root,update_radar_id_list,options);
    
    %generate impact maps
    if impact_flag
        impact_output(update_radar_id_list,newest_time,transform_path);
    end

    %% ending loop
    %Update user
    disp([10,'vis pass complete. ',num2str(length(update_radar_id_list)),' radars updated at ',datestr(now),10]);
    
    %break loop for not realtime
    if realtime_flag == 0
        delete('tmp/kill_vis')
        break
    end
    
    %rotate ddb, cp_file, and qa logs to 200kB
    unix('tail -c 200kB  tmp/log.qa > tmp/log.qa');
    unix('tail -c 200kB  tmp/log.ddb > tmp/log.ddb');
    unix('tail -c 200kB  tmp/log.cp > tmp/log.cp');
    unix('tail -c 200kB  tmp/log.rm > tmp/log.rm');
    unix('tail -c 200kB  tmp/log.sqs > tmp/log.sqs');
	unix('tail -c 200kB  tmp/log.singledop > tmp/log.singledop');
    %Kill function
    if toc(kill_timer)>kill_wait
        %update user
        disp(['@@@@@@@@@ rwx_vis restarted at ',datestr(now)])
        %update restart flag
        restart_flag = true;
        %update restart_vars_fn on kml update for realtime processing
        save(restart_vars_fn,'kmlobj_struct','vol_struct','storm_jstruct','restart_tries','restart_flag')
        %restart
        if ~isdeployed
            %not deployed method: trigger background restart command before
            %kill
            [~,~] = system(['matlab -desktop -r "run ',pwd,'/vis.m" &']);
        else
            %deployed method: restart controlled by run_wv_process sh
            %script
            disp('is deployed - passing restart to run script via temp_vis_vars.mat existance')
        end
        quit force
    end

    %clear restart tries
    restart_tries = 0;
    
end
catch err
    %display and log error
    display(err)
    message = [err.identifier,10,10,getReport(err,'extended','hyperlinks','off')];
    utility_log_write('tmp/log.crash','',['crash error at ',datestr(now)],[err.identifier,' ',err.message]);
    save(['tmp/crash_',datestr(now,'yyyymmdd_HHMMSS'),'.mat'],'err')
    %push notification
    if pushover_flag == 1
        utility_pushover('vis',message)
    end
    %check restart tries
    restart_tries = restart_tries+1;
    if restart_tries > max_restart_tries
        disp('number of restart tries has exceeded max_restart_tries, killing script')
        %removing kill script prevents restart
        delete('tmp/kill_vis')
    end
    %update restart flag
    restart_flag = true;
    %save vars
	if save_object_struct == 1
    	save(restart_vars_fn,'kmlobj_struct','vol_struct','storm_jstruct','restart_tries','restart_flag')
	end
    %rethrow and crash script
    rethrow(err)
end

%profile off
%profile viewer

%soft exit display
disp([10,'@@@@@@@@@ Soft Exit at ',datestr(now),' runtime: ',num2str(toc(kill_timer)),' @@@@@@@@@'])



function storm_jstruct = mask_storm_cells(radar_id,start_timestep,storm_jstruct,ppi_mask,geo_coords)
load('tmp/global.config.mat')

if isempty(storm_jstruct)
    return
end

%init
storm_date_id         = utility_jstruct_to_mat([storm_jstruct.date_id],'N');
storm_sort_id         = utility_jstruct_to_mat([storm_jstruct.sort_id],'S');
storm_mask            = utility_jstruct_to_mat([storm_jstruct.domain_mask],'N');
storm_radar_id        = utility_jstruct_to_mat([storm_jstruct.radar_id],'N');
storm_start_timestamp = datenum(utility_jstruct_to_mat([storm_jstruct.start_timestamp],'S'),ddb_tfmt);
storm_lat             = utility_jstruct_to_mat([storm_jstruct.storm_z_centlat],'N');
storm_lon             = utility_jstruct_to_mat([storm_jstruct.storm_z_centlon],'N');

%filter out radar_id and start_timestep
filter_idx            = find(storm_radar_id==radar_id & storm_start_timestamp==start_timestep);

%loop through cells at correct time and site
for i=1:length(filter_idx)
    %find nearest lat lon grid point in ppi mask
    target_lat = storm_lat(filter_idx(i));
    target_lon = storm_lon(filter_idx(i));
    [~,i_idx]  = min(abs(geo_coords.radar_lat_vec - target_lat));
    [~,j_idx]  = min(abs(geo_coords.radar_lon_vec - target_lon));
    %extract ppi mask and update storm_mask
    target_mask = ppi_mask(i_idx,j_idx);
    %check storm_jstruct against target_mask
    if storm_mask(filter_idx(i)) ~= target_mask
        %update local jstruct and ddb
        part_value   = num2str(storm_date_id(filter_idx(i)));
        sort_value   = storm_sort_id{filter_idx(i)};
        update_value = num2str(target_mask);
        storm_jstruct(filter_idx(i)).domain_mask.N = update_value;
        ddb_update('date_id','N',part_value,'sort_id','S',sort_value,'domain_mask','N',num2str(target_mask),storm_ddb_table);
    end
end
    
function [kmlobj_struct,remove_radar_id] = clean_kmlobj_struct(kmlobj_struct,oldest_time)
%removed entries and associated files (using links) from kmlobj_struct
%using oldest time
load('tmp/global.config.mat')
remove_radar_id = [];
if ~isempty(kmlobj_struct)
    %find old files
    remove_idx      = find([kmlobj_struct.start_timestamp]<oldest_time);
    if ~isempty(remove_idx)
        %clean out files
        remove_ffn_list = {kmlobj_struct(remove_idx).ffn};
        remove_radar_id = [kmlobj_struct(remove_idx).radar_id];
        for i=1:length(remove_ffn_list)
            file_rm(remove_ffn_list{i},0,1);
        end
        %remove entries
        kmlobj_struct(remove_idx) = [];
    end
end

function storm_jstruct = update_storm_jstruct(storm_jstruct,download_stormh5_list,download_path,oldest_time)
%sources stormh5 ddb entries for each stormh5 file and adds this to
%storm_jstruct. Removes entries older than oldest_time
load('tmp/global.config.mat')
disp('extract required data from stormh5 ddb')
%clean storm_jstruct
if ~isempty(storm_jstruct)
    %find old entries
    storm_jstruct_dates = datenum(utility_jstruct_to_mat([storm_jstruct.start_timestamp],'S'),ddb_tfmt);
    remove_idx         = find(storm_jstruct_dates<oldest_time);
    if ~isempty(remove_idx)
        storm_jstruct(remove_idx) = [];
    end
end

temp_ffn_list     = {};
ddb_read_struct   = struct;
for i=1:length(download_stormh5_list)
    [~,stormh5_name,ext] = fileparts(download_stormh5_list{i});
    local_stormh5_ffn    = [download_path,stormh5_name,ext];
    if exist(local_stormh5_ffn,'file') == 2
        %read basic atts
        stormh5_rid        = str2double(stormh5_name(1:2));
        stormh5_start_td   = datenum(stormh5_name(4:18),r_tfmt);
        h5_info            = h5info(local_stormh5_ffn);
        stormh5_groups     = length(h5_info.Groups);
        %loop through groups
        for j=1:stormh5_groups
            %query storm ddb
            tmp_jstruct            = struct;
            tmp_jstruct.date_id.N  = datestr(stormh5_start_td,ddb_dateid_tfmt);
            tmp_jstruct.sort_id.S  = [datestr(stormh5_start_td,ddb_tfmt),'_',num2str(stormh5_rid,'%02.0f'),'_',num2str(j,'%03.0f')];
            %create entry for batch read for current storm
            [ddb_read_struct,tmp_sz] = utility_addtostruct(ddb_read_struct,tmp_jstruct);
            %parse batch read if size is 25 or last cell of last file for
            %current day
			if tmp_sz==25 || (i == length(download_stormh5_list) && j == stormh5_groups)
		        %temp path
		        temp_path = [tempdir,'vis_jstorm_read/',datestr(stormh5_start_td,'yyyymmdd'),'/'];
		        if exist(temp_path,'file')~=7
		        	mkdir(temp_path)
		        end
				%batch background fetch
				temp_ffn = ddb_batch_read(ddb_read_struct,storm_ddb_table,temp_path,'');
				pause(0.1)
				%add read filename to list
		        temp_ffn_list     = [temp_ffn_list;temp_ffn];
		        %clear ddb_put_struct
		        ddb_read_struct  = struct;
			end
        end
    end
end
%wait for aws batch read to finish
utility_aws_wait
%read back in ddb local files
for i=1:length(temp_ffn_list)
	%read out ddb data	
	jstruct_out = json_read(temp_ffn_list{i});
	delete(temp_ffn_list{i})
	%abort file if it contains unprocessed keys
    if ~isempty(fieldnames(jstruct_out.UnprocessedKeys))
    	disp('UnprocessedKeys present')
    	keyboard
    end
	%loop through entries
	for j=1:length(jstruct_out.Responses.(storm_ddb_table))
		%extract names for entry j
        jnames      = fieldnames(jstruct_out.Responses.(storm_ddb_table)(j));
		%abort if field names are not equal to ddb_fields
        if length(jnames) ~= stormddb_fields
        	disp(['jnames not correct length for ',temp_ffn_list{i}])
            continue
        end
        %remove field types from struct and append to storm_struct
        clean_struct = struct;
        %loop though fields and add to clean_struct
        for m=1:length(jnames)
        	field_name                = jnames{m};
            field_struct              = jstruct_out.Responses.(storm_ddb_table)(j).(field_name);
            clean_struct.(field_name) = field_struct;
        end
		%add proced flag
        clean_struct.proced = false;
		%append h5 ffn
		[~,fn,ext] = fileparts(clean_struct.data_ffn.S);
		local_stormh5_ffn = [download_path,fn,ext];
		group_id          = str2double(clean_struct.subset_id.N);
        clean_struct.local_stormh5_ffn = local_stormh5_ffn;
        %append mesh grid
        storm_data_struct      = h5_data_read(local_stormh5_ffn,'',group_id);
        mesh_grid              = double(storm_data_struct.MESH_grid)./r_scale;
        clean_struct.mesh_grid = mesh_grid;

        %append clean_struct to storm_jstruct
        storm_jstruct = [storm_jstruct,clean_struct];
	end
end

disp('stormh5 ddb extract complete')

function vol_struct = update_vol_struct(vol_struct,download_odimh5_list,download_path,oldest_time)
%builds vol_struct using hdf5 atts for entries in odimh5 list, filters out
%old entries using oldest_time and returns radar_ids which have been
%cleaned (for updating kml)
load('tmp/global.config.mat')

%clean vol_struct
if ~isempty(vol_struct)
    %find old entries
    remove_idx      = find([vol_struct.start_timestamp]<oldest_time);
    if ~isempty(remove_idx)
        %preserve removed radar_ids
        vol_struct(remove_idx) = [];
    end
end

for i=1:length(download_odimh5_list)
    [~,odimh5_name,ext] = fileparts(download_odimh5_list{i});
    local_odimh5_ffn     = [download_path,odimh5_name,ext];
    if exist(local_odimh5_ffn,'file') == 2
        %read basic atts
        odimh5_rid          = str2double(odimh5_name(1:2));
        odimh5_start_td     = read_odimh5_time(local_odimh5_ffn);
        %read range for masking
        [~,rng_vec]         = read_odimh5_ppi_dims(local_odimh5_ffn,1,true);
        radar_rng           = floor(max(rng_vec)/10)*10; %round to 10s of km
        %add to vol struct
        tmp_struct          = struct('radar_id',odimh5_rid,'start_timestamp',odimh5_start_td,'local_odimh5_ffn',local_odimh5_ffn,'radar_rng',radar_rng,'proced',false);
        vol_struct          = [vol_struct,tmp_struct];
    end
end
