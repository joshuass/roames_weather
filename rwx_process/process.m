function process

%WHAT: This modules takes odimh5 volumes (realtime or archive), regrids (cart_interpol6),
%applies identification (wdss_ewt), tracking (wdss_tracking), then archives the data for 
%use in climatology (wv_clim) or visualisation

%INPUT:
%see wv_process.config

%OUTPUT: Archive The processed data base of matfile, organised into daily track,
%ident and intp databases (no overheads).

%%Load VARS
clearvars
% general vars
restart_cofig_fn  = 'temp_process_vars.mat';
process_config_fn = 'process.config';
global_config_fn  = 'global.config';
local_tmp_path    = 'tmp/';
download_path     = [tempdir,'process_h5_download/'];
transform_path    = [local_tmp_path,'transforms/'];

%load blank vars
complete_h5_dt      = [];
complete_h5_fn_list = {};
nwp_extract_list    = [];
date_start_restart  = [];
date_list           = now;
date_idx            = 1;
pushover_flag       = 1;
restart_tries       = 0;
%start try
try
    
%create paths
if exist(local_tmp_path,'file') ~= 7
    mkdir(local_tmp_path)
    mkdir(transform_path)
end

% setup kill time (restart program to prevent memory fragmentation)
kill_wait  = 60*60*2; %kill time in seconds
kill_timer = tic; %create timer object
unix('touch tmp/kill_process');

% Add folders to path and read config files
if ~isdeployed
    addpath('/home/meso/dev/roames_weather/lib/m_lib');
    addpath('/home/meso/dev/roames_weather/etc')
    addpath('/home/meso/dev/shared_lib/jsonlab');
    addpath('/home/meso/dev/roames_weather/bin/json_read');
    addpath('/home/meso/dev/roames_weather/bin/mirt3D');
    addpath('etc')
    addpath('tmp')
    unix('touch tmp/kill_process');
else
    addpath('etc')
    addpath('tmp')
    %never include mex file paths in addpath when compiled!!!!!!!!!!!
end

% load process_config
read_config(process_config_fn);
load([local_tmp_path,process_config_fn,'.mat'])
% check for restart or first start
if exist([local_tmp_path,restart_cofig_fn],'file')==2
    %silent restart detected, load vars from reset and remove file
    try
        load([local_tmp_path,restart_cofig_fn]);
    catch
        %corrupt file
        delete([local_tmp_path,restart_cofig_fn]);
    end
    delete([local_tmp_path,restart_cofig_fn]);
end

% Load global config files
read_config(global_config_fn);
load([local_tmp_path,global_config_fn,'.mat']);

% site_info.txt
if realtime_flag == 0 %radar_id_list will always be a single int
    site_warning = read_site_info(site_info_fn,site_info_moved_fn,radar_id_list,datenum(date_start,'yyyy_mm_dd'),datenum(date_stop,'yyyy_mm_dd'),0);
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

%break if processing climatology for more than one radar
if realtime_flag==0 && length(radar_id_list)>1
    display('only run climatology processing for one radar at a time')
    display('halting')
    return
end

%% Preallocate regridding coordinates
if radar_id_list == mobile_id
    preallocate_mobile_grid(radar_id_list,transform_path,force_transform_update)
else
    preallocate_radar_grid(radar_id_list,transform_path,force_transform_update)
end
%load climate radar coordinates
if realtime_flag==0
    transform_fn = [transform_path,'regrid_transform_',num2str(radar_id_list,'%02.0f'),'.mat'];
    mat_out      = load(transform_fn,'radar_coords');
    clim_radar_coords = mat_out.radar_coords;
else
    clim_radar_coords = [];
end

%profile clear
%profile on
%% Primary Loop
while exist('tmp/kill_process','file')==2

    % create time span
    if realtime_flag == 1
        date_list = utility_utc_time;
    elseif isempty(date_start_restart) %new climatology processing instance
        date_list = datenum(date_start,'yyyy_mm_dd'):datenum(date_stop,'yyyy_mm_dd');
    else %restart climatology processing
        date_list = date_start_restart:datenum(date_stop,'yyyy_mm_dd');
    end
    %loop through target ffn's
    for date_idx = 1:length(date_list)
        %init download dir
        if exist(download_path,'file')==7
            delete([download_path,'*']);
        else
            mkdir(download_path);
        end
        
        %fetch files
        if realtime_flag == 1
            %Produce a list of filenames to process
            oldest_time                           = addtodate(date_list,realtime_offset,'hour');
            newest_time                           = date_list;
            [fetch_h5_ffn_list,~,~]               = sqs_process_staging(sqs_odimh5_prep,oldest_time,newest_time,radar_id_list);
            %update user
            disp(['Realtime processing downloading ',num2str(length(fetch_h5_ffn_list)),' files']);
            %loop through and download files
            for i=1:length(fetch_h5_ffn_list)
                file_cp(fetch_h5_ffn_list{i},download_path,0,1)
            end
            %wait for aws process to finish
            utility_aws_wait
        else
            disp(['Climatology processing downloading files from ',datestr(date_list(date_idx)),' for radar ',num2str(radar_id_list)]);
            %sync day of data from radar_id from s3 to local, radar_id_list must be a single number
            s3_sync(odimh5_s3_bucket,download_path,radar_id_list,year(date_list(date_idx)),month(date_list(date_idx)),day(date_list(date_idx)));
        end
        %build filelist
        download_path_dir = dir(download_path); download_path_dir(1:2) = [];
        pending_h5_fn_list = {download_path_dir.name};
        if isempty(pending_h5_fn_list)
            disp('no files present for target day')
            continue
        end
        
        %primary loop
        for i=1:length(pending_h5_fn_list)
            disp(['processing file of ',num2str(i),' of ',num2str(length(pending_h5_fn_list))])
            %init local filename for processing
            odimh5_ffn        = [download_path,pending_h5_fn_list{i}];
            if realtime_flag == 1
                remote_odimh5_ffn = fetch_h5_ffn_list{i};
            else
                remote_odimh5_ffn = '';
            end
            if exist(odimh5_ffn,'file')~=2
                continue
            end
            
            %QA the h5 file (attempt to read groups)
            [qa_flag,no_groups,radar_id,vel_flag,vol_dt] = process_qa_h5(odimh5_ffn,min_n_groups,radar_id_list);

            %QA exit
            if qa_flag==0
                disp(['Volume failed QA: ' pending_h5_fn_list{i}])
                complete_h5_fn_list = [complete_h5_fn_list;pending_h5_fn_list{i}];
                complete_h5_dt      = [complete_h5_dt;vol_dt];
                continue
            end

            %run regridding/interpolation
            grid_obj = process_vol_regrid(odimh5_ffn,transform_path,clim_radar_coords);
            
            %run cell identify if sig_refl has been detected
            if grid_obj.sig_refl==1
                %run EWT
                [ewtBasin,ewtBasinExtend,ewt_refl_image] = process_wdss_ewt(grid_obj);
                %extract sounding level data
                if realtime_flag == 1
                    %extract radar lat lon
                    %retrieve current GFS temperature data for above radar site
                    [nwp_extract_list,nn_snd_fz_h,nn_snd_minus20_h] = process_snding_gfs(nwp_extract_list,grid_obj.radar_lat,grid_obj.radar_lon,radar_id,eraint_ddb_table);
                else
                    %dummy radar for UQXPOL
                    if radar_id==99
                        nn_snd_fz_h      = 4500;
                        nn_snd_minus20_h = 7600;
                    else
                        %load era-interim fzlvl data from ddb
                        [nwp_extract_list,nn_snd_fz_h,nn_snd_minus20_h] = process_snding_eraint(nwp_extract_list,grid_obj.vol_dt,radar_id,eraint_ddb_table);
                    end
                end
                if isempty(nn_snd_fz_h)
                    disp('###sounding data missing###')
                    return
                end
                %run ident
                proc_obj = process_storm_analysis(grid_obj,ewt_refl_image,ewtBasin,ewtBasinExtend,nn_snd_fz_h,nn_snd_minus20_h);
            else
                proc_obj = {};
            end
            
            %update storm and odimh5 index ddb, plus create storm object h5
            %as needed
            update_archive(grid_obj,proc_obj,storm_ddb_table,realtime_flag,remote_odimh5_ffn)

            %append and clean h5_list for realtime processing
            if realtime_flag == 1
                complete_h5_fn_list = [complete_h5_fn_list;pending_h5_fn_list{i}];
                complete_h5_dt      = [complete_h5_dt;vol_dt];
                clean_idx           = complete_h5_dt < oldest_time;
                complete_h5_fn_list(clean_idx) = [];
                complete_h5_dt(clean_idx)      = [];
            end
            
            disp(['Added ',num2str(length(proc_obj)),' objects from ',pending_h5_fn_list{i},' Volume ',num2str(i),' of ',num2str(length(pending_h5_fn_list))])

            %Kill function
            if toc(kill_timer)>kill_wait
                date_start_restart = date_list(date_idx);
                save([local_tmp_path,restart_cofig_fn],'complete_h5_fn_list','complete_h5_dt','date_start_restart','nwp_extract_list')
                %update user
                disp(['@@@@@@@@@ wv_process restarted at ',datestr(now)])
                %restart
                if ~isdeployed
                    %not deployed method: trigger background restart command before
                    %kill
                    [~,~] = system(['matlab -desktop -r "run ',pwd,'/process.m" &'])
                else
                    %deployed method: restart controlled by run_wv_process sh
                    %script
                    disp('is deployed - passing restart to run script via temp_process_vars.mat existance')
                end
                quit force
            end
        end
    end
    
    %Update user and clear pending list
    disp(['Processing complete at ',datestr(now),10])
    
    %rotate ddb, cp_file, and qa logs to 200kB
    unix(['tail -c 200kB  tmp/log.qa > tmp/log.qa']);
    unix(['tail -c 200kB  tmp/log.ddb > tmp/log.ddb']);
    unix(['tail -c 200kB  tmp/log.cp > tmp/log.cp']);
    unix(['tail -c 200kB  tmp/log.rm > tmp/log.rm']);
    unix(['tail -c 200kB  tmp/log.sqs > tmp/log.sqs']);
    unix(['tail -c 200kB  tmp/log.sns > tmp/log.sns']);
    
    %break loop if cts_loop=0
    if realtime_flag==0
        delete('tmp/kill_process')
        message = ['COMPLETED radar_id ',num2str(radar_id_list,'%02.0f'),' form ',date_start,' to ',date_stop,' in ',num2str(toc(kill_timer)/60/60),'hrs'];
        utility_pushover(['process ',pushover_tag],message);
        break
    end
    
    %clear restart tries
    restart_tries = 0;
    %pause
    disp('pausing for 5s')
    pause(5)
    
end
catch err
    display(err)
    %save error and log
    message = [err.identifier,10,10,getReport(err,'extended','hyperlinks','off')];
    utility_log_write('tmp/log.crash','',['crash error at ',datestr(now)],[err.identifier,' ',err.message]);
    save(['tmp/crash_',datestr(now,'yyyymmdd_HHMMSS'),'.mat'],'err')
    %send push notification
    if pushover_flag == 1
        utility_pushover(['process ',pushover_tag],message)
    end
    %check restart tries
    restart_tries = restart_tries+1;
    if restart_tries > max_restart_tries
        display('number of restart tries has exceeded max_restart_tries, killing script')
        %removing kill script prevents restart
        delete('tmp/kill_vis')
    end
    %save vars
    date_start_restart = date_list(date_idx);
    save([local_tmp_path,restart_cofig_fn],'complete_h5_fn_list','complete_h5_dt','date_start_restart','nwp_extract_list','restart_tries')
    %rethrow error and crash script
    rethrow(err)
end

%soft exit display
if exist([local_tmp_path,restart_cofig_fn],'file')==2
    delete([local_tmp_path,restart_cofig_fn])
end
disp([10,'@@@@@@@@@ Soft Exit at ',datestr(now),' runtime: ',num2str(toc(kill_timer)),' @@@@@@@@@'])
%profile off
%profile viewer

function update_archive(grid_obj,storm_obj,storm_ddb_table,realtime_flag,odimh5_ffn)
%WHAT: Updates the ident_db and intp_db database mat files fore
%that day with the additional entires from input

%INPUT:
%archive_dest: path to archive destination
%vol_dt:       new entires for vol_dt from cart_interpol6
%storm_obj:    new entires for storm_obj from ewt2ident

%% Update vol_db and vol_data

load('tmp/global.config.mat')

%setup paths and tags
date_vec     = datevec(grid_obj.vol_dt);
radar_id     = grid_obj.radar_id;
vol_dt       = grid_obj.vol_dt;
radar_id_str = num2str(radar_id,'%02.0f');
arch_path    = [radar_id_str,...
    '/',num2str(date_vec(1)),'/',num2str(date_vec(2),'%02.0f'),...
    '/',num2str(date_vec(3),'%02.0f'),'/'];
dest_path    = [stormh5_s3_bucket,arch_path];
data_tag     = [num2str(radar_id,'%02.0f'),'_',datestr(vol_dt,r_tfmt)];

%create local data path
if ~strcmp(stormh5_s3_bucket(1:2),'s3') && exist(dest_path,'file') ~= 7
    mkdir(dest_path)
end

if ~isempty(storm_obj)
    %% volume data
    tar_fn          = [data_tag,'.wv.tar'];
    h5_fn           = [data_tag,'.storm.h5'];
    tmp_h5_ffn      = [tempdir,h5_fn];
    stormh5_ffn     = [dest_path,h5_fn];

    %delete h5 if exists
    if exist(tmp_h5_ffn,'file') == 2
        delete(tmp_h5_ffn)
    end

    %delete storm ddb entries for this volume if they already exist
    %since indicates volumes was previous processed for storms
    if clean_stormobj_index == 1
        storm_atts      = 'date_id,sort_id';
        oldest_time_str = datestr(addtodate(vol_dt,-1,'minute'),ddb_tfmt);
        newest_time_str = datestr(addtodate(vol_dt,1,'minute'),ddb_tfmt); %buffer time for between function to remove volumes which may have seconds removed
        %query for storm_ddb entries
        delete_jstruct  = ddb_query('date_id',datestr(vol_dt,ddb_dateid_tfmt),'sort_id',oldest_time_str,newest_time_str,storm_atts,storm_ddb_table);
        for i=1:length(delete_jstruct)
            %remove items
            ddb_rm_item(delete_jstruct(i),storm_ddb_table);
        end
    end
    
    %init struct
    ddb_put_struct  = struct;
    for i=1:length(storm_obj)
        subset_id  = i;
        %round datasets
        storm_llb      = roundn(storm_obj(i).subset_latlonbox,-4);
        storm_dcent    = roundn(storm_obj(i).z_latloncent,-4);
        storm_stats    = roundn(storm_obj(i).stats,-1);
        %append and write db
        tmp_jstruct                     = struct;
        tmp_jstruct.date_id.N           = datestr(vol_dt,ddb_dateid_tfmt);
        tmp_jstruct.sort_id.S           = [datestr(vol_dt,ddb_tfmt),'_',num2str(radar_id,'%02.0f'),'_',num2str(i,'%03.0f')];
        tmp_jstruct.domain_mask.N       = '1';
        tmp_jstruct.radar_id.N          = num2str(radar_id,'%02.0f');
        tmp_jstruct.subset_id.N         = num2str(i,'%03.0f');
        tmp_jstruct.data_ffn.S          = stormh5_ffn;
        tmp_jstruct.start_timestamp.S   = datestr(vol_dt,ddb_tfmt);
        tmp_jstruct.storm_ijbox.S       = num2str(storm_obj(i).subset_ijbox);
        tmp_jstruct.storm_latlonbox.S   = num2str(storm_llb,'%03.4f ');
        tmp_jstruct.storm_z_centlat.N   = num2str(storm_dcent(1),'%03.4f ');
        tmp_jstruct.storm_z_centlon.N   = num2str(storm_dcent(2),'%03.4f ');
        tmp_jstruct.h_grid.N            = num2str(grid_obj.h_grid_deg);
        tmp_jstruct.v_grid.N            = num2str(grid_obj.v_grid);
        %append stats
        for j=1:length(storm_stats)
            tmp_jstruct.(storm_obj(i).stats_labels{j}).N = num2str(storm_stats(j));
        end
        %append to put struct
        [ddb_put_struct,tmp_sz] = utility_addtostruct(ddb_put_struct,tmp_jstruct);
        %write if needed
        if tmp_sz==25 || i == length(storm_obj)
            %batch write
            ddb_batch_write(ddb_put_struct,storm_ddb_table,1);
            %clear ddb_put_struct
            ddb_put_struct  = struct;
        end
        %write data to h5
        data_struct = struct('refl_vol',storm_obj(i).subset_refl,...
            'tops_h_grid',storm_obj(i).tops_h_grid,'sts_h_grid',storm_obj(i).sts_h_grid,...
            'MESH_grid',storm_obj(i).MESH_grid,'POSH_grid',storm_obj(i).POSH_grid,...
            'max_dbz_grid',storm_obj(i).max_dbz_grid,'vil_grid',storm_obj(i).vil_grid);
        if ~isempty(grid_obj.vradh_grid)
            data_struct.vel_vol = storm_obj(i).subset_vel;
        end
        h5_data_write(h5_fn,tempdir,subset_id,data_struct,r_scale);
    end
    %move h5 file to destination if exists
    if exist(tmp_h5_ffn,'file') == 2
		file_mv(tmp_h5_ffn,stormh5_ffn);
    end
end

%add new entry to staging sns for realtime processing
if realtime_flag == 1
    sns_publish(sns_odimh5_process,odimh5_ffn)
end
