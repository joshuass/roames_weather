function process
%WHAT: This modules takes odimh5 volumes (realtime or archive), regrids (cart_interpol6),
%applies identification (wdss_ewt), tracking (wdss_tracking), then archives the data for 
%use in climatology (wv_clim) or visualisation

%INPUT:
%see wv_process.config

%OUTPUT: Archive The processed data base of matfile, organised into daily track,
%ident and intp databases (no overheads).

%%Load VARS
% general vars
restart_cofig_fn  = 'temp_process_vars.mat';
process_config_fn = 'process.config';
global_config_fn  = 'global.config';
site_info_fn      = 'site_info.txt';
tmp_config_path   = 'tmp/';
download_path     = [tempdir,'h5_download/'];

if exist(tmp_config_path,'file') ~= 7
    mkdir(tmp_config_path)
end

% setup kill time (restart program to prevent memory fragmentation)
kill_wait  = 60*60*2; %kill time in seconds
kill_timer = tic; %create timer object
unix('touch tmp/kill_process');

% Add folders to path and read config files
if ~isdeployed
    addpath('/home/meso/dev/wv/lib/m_lib');
    addpath('/home/meso/dev/wv/etc')
    addpath('/home/meso/dev/shared_lib/jsonlab');
    addpath('/home/meso/dev/wv/bin/json_read');
    addpath('/home/meso/dev/wv/bin/mirt3D');
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
load([tmp_config_path,process_config_fn,'.mat'])
% check for restart or first start
if exist(restart_cofig_fn,'file')==2
    %silent restart detected, load vars from reset and remove file
    load(restart_cofig_fn);
    delete(restart_cofig_fn);
else
    %new start
    complete_h5_dt      = [];
    complete_h5_fn_list = {};
    gfs_extract_list    = [];
    hist_oldest_restart = [];
end

% Load global config files
read_config(global_config_fn);
load([tmp_config_path,global_config_fn,'.mat']);

%load colourmaps for png generation
colormap_interp('refl24bit.txt','vel24bit.txt');

% site_info.txt
read_site_info(site_info_fn); load([tmp_config_path,site_info_fn,'.mat']);
% check if all sites are needed
if strcmp(radar_id_list,'all')
    radar_id_list = site_id_list;
end

%break if processing climatology for more than one radar
if realtime_flag==0 && length(radar_id_list)>1
    display('only run climatology processing for one radar at a time')
    display('halting')
    return
end

%create/update daily archives/objects from ident and intp objects
if local_dest_flag == 1
    dest_root = local_dest_root;
else
    dest_root = s3_dest_root;
end
if local_src_flag == 1 %only used for climatology processing
    src_root = local_src_root;
else
    src_root = s3_src_root;
end

%% Preallocate cartesian regridding coordinates
[aazi_grid,sl_rrange_grid,eelv_grid] = process_create_inv_grid(['tmp/',global_config_fn,'.mat']);
%profile clear
%profile on
%% Primary Loop
try
while exist('tmp/kill_process','file')==2

    % create time span
    if realtime_flag == 1
        date_list = utc_time;
    elseif isempty(hist_oldest_restart) %new climatology processing instance
        date_list = datenum(hist_oldest,'yyyy_mm_dd'):datenum(hist_newest,'yyyy_mm_dd');
    else %restart climatology processing
        date_list = hist_oldest_restart:datenum(hist_newest,'yyyy_mm_dd');
    end
    %loop through target ffn's
    for d = 1:length(date_list)
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
            fetch_h5_ffn_list                     = ddb_filter_staging(staging_ddb_table,oldest_time,newest_time,radar_id_list,'prep_odimh5');
            %update user
            disp(['Realtime processing downloading ',num2str(length(fetch_h5_ffn_list)),' files']);
        else
            oldest_time                           = date_list(d);
            newest_time                           = addtodate(date_list(d)+1,-1,'minute');            
            fetch_h5_ffn_list                     = ddb_filter_s3h5(odimh5_ddb_table,'start_timestamp',oldest_time,newest_time,radar_id_list);
            %update user
            disp(['Climatology processing downloading files from ',s3_path]);
        end
        %loop through and download files
        for i=1:length(fetch_h5_ffn_list)
             file_cp(fetch_h5_ffn_list{i},download_path,0,1)
        end
        %wait for aws process to finish
        wait_aws_finish
        %build filelist
        download_path_dir = dir(download_path); download_path_dir(1:2) = [];
        pending_h5_fn_list = {download_path_dir.name};

        %primary loop
        for i=1:length(pending_h5_fn_list)
            display(['processing file of ',num2str(i),' of ',num2str(length(pending_h5_fn_list))])
            %init local filename for processing
            h5_ffn = [download_path,pending_h5_fn_list{i}];
            if exist(h5_ffn,'file')~=2
                continue
            end

            %QA the h5 file (attempt to read groups)
            [qa_flag,no_groups,radar_id,vel_flag,start_dt] = process_qa_h5(h5_ffn,min_n_groups,radar_id_list);

            %QA exit
            if qa_flag==0
                disp(['Volume failed QA: ' pending_h5_fn_list{i}])
                complete_h5_fn_list = [complete_h5_fn_list;pending_h5_fn_list{i}];
                complete_h5_dt       = [complete_h5_dt;start_dt];
                continue
            end

            %run regridding/interpolation
            [vol_obj,refl_vol,vel_vol] = process_vol_regrid(h5_ffn,aazi_grid,sl_rrange_grid,eelv_grid,no_groups,vel_flag);
            if isempty(vol_obj)
                disp(['Volume datasets missing: ' pending_h5_fn_list{i}])
                complete_h5_fn_list = [complete_h5_fn_list;pending_h5_fn_list{i}];
                complete_h5_dt      = [complete_h5_dt;start_dt];
                continue
            end
            %run cell identify if sig_refl has been detected
            if vol_obj.sig_refl==1

                %extract ewt image for processing using radar transform
                ewt_refl_image = max(refl_vol,[],3); %allows the assumption only shrinking is needed.
                ewt_refl_image = medfilt2(ewt_refl_image, [ewt_kernel_size,ewt_kernel_size]);       
                %run EWT
                ewtBasinExtend = process_wdss_ewt(ewt_refl_image);
                %extract sounding level data
                if realtime_flag == 1
                    %extract radar lat lon
                    %retrieve current GFS temperature data for above radar site
                    [gfs_extract_list,nn_snd_fz_h,nn_snd_minus20_h] = gfs_latest_analysis_snding(gfs_extract_list,vol_obj.r_lat,vol_obj.r_lon);
                else
                    %load era-interim fzlvl data from ddb
                    [nn_snd_fz_h,nn_snd_minus20_h] = ddb_eraint_extract(vol_obj.start_timedate,radar_id,eraint_ddb_table);
                end
                %run ident
                prc_obj = process_ewt2ident(vol_obj,ewt_refl_image,refl_vol,vel_vol,ewtBasinExtend,nn_snd_fz_h,nn_snd_minus20_h);
            else
                prc_obj = {};
            end
            
            update_archive(src_root,dest_root,vol_obj,prc_obj,odimh5_ddb_table,storm_ddb_table,realtime_flag,h5_ffn)

            %run tracking algorithm if sig_refl has been detected
            if vol_obj.sig_refl==1 && ~isempty(prc_obj)
                %tracking
                updated_storm_jstruct = process_wdss_tracking(vol_obj.start_timedate,vol_obj.radar_id);
                %generate nowcast json on s3 for realtime data
                if realtime_flag == 1
                     storm_nowcast_json_wrap(dest_root,updated_storm_jstruct,vol_obj);
                     %storm_nowcast_svg_wrap(dest_root,updated_storm_jstruct,vol_obj);
                end
            else
                %remove nowcast files is no prc_objects exist anymore
                nowcast_root = [dest_root,num2str(radar_id,'%02.0f'),'/nowcast.'];
                file_rm([nowcast_root,'json'],0,1)
                %file_rm([nowcast_root,'wtk'],0)
                %file_rm([nowcast_root,'svg'],0)
            end

            %append and clean h5_list for realtime processing
            if realtime_flag == 1
                complete_h5_fn_list = [complete_h5_fn_list;pending_h5_fn_list{i}];
                complete_h5_dt      = [complete_h5_dt;start_dt];
                clean_idx           = complete_h5_dt < oldest_time;
                complete_h5_fn_list(clean_idx) = [];
                complete_h5_dt(clean_idx)   = [];
            end
            
            disp(['Added ',num2str(length(prc_obj)),' objects from ',pending_h5_fn_list{i},' Volume ',num2str(i),' of ',num2str(length(pending_h5_fn_list))])

            %Kill function
            if toc(kill_timer)>kill_wait
                hist_oldest_restart = date_list(d);
                save('temp_process_vars.mat','complete_h5_fn_list','complete_h5_dt','hist_oldest_restart','gfs_extract_list')
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
    
    %break loop if cts_loop=0
    if realtime_flag==0
        delete('tmp/kill_process')
        break
    end
    
    disp('pausing for 5s')
    pause(5)
    
end
catch err
    %save vars
    display(err)
    hist_oldest_restart = date_list(d);
    save('temp_process_vars.mat','complete_h5_fn_list','complete_h5_dt','hist_oldest_restart','gfs_extract_list')
    log_cmd_write('tmp/log.crash','',['crash error at ',datestr(now)],[err.identifier,' ',err.message]);
    save(['tmp/crash_',datestr(now,'yyyymmdd_HHMMSS'),'.mat'],'err')
    rethrow(err)
end

%soft exit display
disp([10,'@@@@@@@@@ Soft Exit at ',datestr(now),' runtime: ',num2str(toc(kill_timer)),' @@@@@@@@@'])
%profile off
%profile viewer

function update_archive(src_root,dest_root,vol_obj,storm_obj,odimh5_ddb_table,storm_ddb_table,realtime_flag,odimh5_ffn)
%WHAT: Updates the ident_db and intp_db database mat files fore
%that day with the additional entires from input

%INPUT:
%archive_dest: path to archive destination
%vol_obj: new entires for vol_obj from cart_interpol6
%storm_obj: new entires for storm_obj from ewt2ident

%% Update vol_db and vol_data

load('tmp/global.config.mat')
load('tmp/interp_cmaps.mat')

%setup paths and tags
date_vec     = datevec(vol_obj.start_timedate);
radar_id     = vol_obj.radar_id;
radar_id_str = num2str(radar_id,'%02.0f');
arch_path = [radar_id_str,...
    '/',num2str(date_vec(1)),'/',num2str(date_vec(2),'%02.0f'),...
    '/',num2str(date_vec(3),'%02.0f'),'/'];
dest_path = [dest_root,arch_path];
src_path  = [src_root,arch_path];
data_tag  = [num2str(radar_id,'%02.0f'),'_',datestr(vol_obj.start_timedate,r_tfmt)];
%create local data path
if ~strcmp(dest_root(1:2),'s3')
    mkdir(dest_path)
end

%% volume data
tar_fn      = [data_tag,'.wv.tar'];
tmp_tar_ffn = [tempdir,tar_fn];
h5_fn       = [data_tag,'.storm.h5'];
tmp_h5_ffn  = [tempdir,h5_fn];
stormh5_ffn = '';

%delete h5 if exists
if exist(tmp_h5_ffn,'file') == 2
    delete(tmp_h5_ffn)
end

%append to odimh5_ddb_table (replaces any previous entries)
%get-item
jstruct = ddb_get_item(odimh5_ddb_table,...
    'radar_id','N',radar_id_str,...
    'start_timestamp','S',datestr(vol_obj.start_timedate,ddb_tfmt),'');
%update init_sig_relf_flag
if ~isempty(jstruct)
    storm_flag    = jstruct.Item.storm_flag.N;
else
    storm_flag    = 0;
    jstruct       = struct;
end

%skip if storm_obj is empty
if isempty(storm_obj)
    storm_flag = 0;
else
    %delete storm ddb entries for this volume if they already exist
    if storm_flag == 1 %since indicates volumes was previous processed for storms
        storm_atts      = 'radar_id,subset_id';
        oldest_time_str = datestr(vol_obj.start_timedate,ddb_tfmt);
        newest_time_str = datestr(addtodate(vol_obj.start_timedate,1,'second'),ddb_tfmt); %duffer time for between function
        %query for storm_ddb entries
        delete_jstruct  = ddb_query('radar_id',num2str(radar_id,'%02.0f'),'subset_id',oldest_time_str,newest_time_str,storm_atts,storm_ddb_table);
        for i=1:length(delete_jstruct)
            %remove items
            ddb_rm_item(delete_jstruct(i),storm_ddb_table);
        end
    end
    %init vars
    stormh5_ffn     = [dest_path,tar_fn];
    storm_flag      = 1; %determine sig_refl from storm analysis, not vol_grid
    tar_ffn_list    = '';
    track_id        = 0; %default for no track
    %init struct
    ddb_put_struct  = struct;
    for i=1:length(storm_obj)
        subset_id  = i;
        storm_llb      = round(storm_obj(i).subset_latlonbox*geo_scale);
        storm_dcent    = round(storm_obj(i).dbz_latloncent*geo_scale);
        storm_edge_lat = round(storm_obj(i).subset_lat_edge*geo_scale);
        storm_edge_lon = round(storm_obj(i).subset_lon_edge*geo_scale);
        storm_stats    = round(storm_obj(i).stats*stats_scale);
        %append and write db
        tmp_jstruct                     = struct;
        tmp_jstruct.radar_id.N          = num2str(vol_obj.radar_id);
        tmp_jstruct.subset_id.S         = [datestr(vol_obj.start_timedate,ddb_tfmt),'_',num2str(i,'%03.0f')];
        tmp_jstruct.data_ffn.S          = stormh5_ffn;
        tmp_jstruct.start_timestamp.S   = datestr(vol_obj.start_timedate,ddb_tfmt);
        tmp_jstruct.track_id.N          = num2str(track_id);
        tmp_jstruct.storm_ijbox.S       = num2str(storm_obj(i).subset_ijbox);
        tmp_jstruct.storm_latlonbox.S   = num2str(storm_llb');
        tmp_jstruct.storm_edge_lat.S    = num2str(storm_edge_lat);
        tmp_jstruct.storm_edge_lon.S    = num2str(storm_edge_lon);
        tmp_jstruct.storm_dbz_centlat.N = num2str(storm_dcent(1));
        tmp_jstruct.storm_dbz_centlon.N = num2str(storm_dcent(2));
        tmp_jstruct.h_grid.N            = num2str(h_grid);
        tmp_jstruct.v_grid.N            = num2str(v_grid);
        %append stats
        for j=1:length(storm_stats)
            tmp_jstruct.(storm_obj(i).stats_labels{j}).N = num2str(storm_stats(j));
        end
        %append to put struct
        [ddb_put_struct,tmp_sz] = addtostruct(ddb_put_struct,tmp_jstruct,['item',num2str(i)]);
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
        if ~isempty(vol_obj.vol_vel_out)
            data_struct.vel_vol = storm_obj(i).subset_vel;
        end
        h5_data_write(h5_fn,tempdir,subset_id,data_struct,r_scale);
    end
    %%%TAR
    %append h5 files to tar list
    if exist(tmp_h5_ffn,'file') == 2
        tar_ffn_list = [tar_ffn_list;h5_fn];
    end
    %tar data and move to s3
    %parse file list
    tartxt_fid = fopen('etc/tar_ffn_list.txt','w');
    for i=1:length(tar_ffn_list)
        fprintf(tartxt_fid,'%s\n',tar_ffn_list{i});
    end
    fclose(tartxt_fid);
    %pass to tar cmd
    cmd         = ['tar -C ',tempdir,' -cvf ',tmp_tar_ffn,' -T etc/tar_ffn_list.txt'];
    [sout,eout] = unix(cmd);
    file_mv(tmp_tar_ffn,stormh5_ffn);
    %remove files
    for i=1:length(tar_ffn_list)
        delete([tempdir,tar_ffn_list{i}]);
    end  
end

%update dynamodb odimh5 table
ddb_update('radar_id','N',radar_id_str,'start_timestamp','S',datestr(vol_obj.start_timedate,ddb_tfmt),'storm_flag','N',num2str(storm_flag),odimh5_ddb_table)

%add new entry to staging ddb for realtime processing
if realtime_flag == 1
    data_id                          = [datestr(vol_obj.start_timedate,ddb_tfmt),'_',num2str(radar_id,'%02.0f')];
    %process odimh5
    ddb_staging                      = struct;
    ddb_staging.data_type.S          = 'process_odimh5';
    ddb_staging.data_id.S            = data_id;
    ddb_staging.data_ffn.S           = odimh5_ffn;
    ddb_put_item(ddb_staging,staging_ddb_table)
    %stormh5
    ddb_staging                      = struct;
    ddb_staging.data_type.S          = 'stormh5';
    ddb_staging.data_id.S            = data_id;
    ddb_staging.data_ffn.S           = stormh5_ffn;
    ddb_put_item(ddb_staging,staging_ddb_table)
end



function [ddb_struct,tmp_sz] = addtostruct(ddb_struct,data_struct,item_id)

%init
data_name_list  = fieldnames(data_struct);

for i = 1:length(data_name_list);
    %read from data_struct
    data_name  = data_name_list{i};
    data_type  = fieldnames(data_struct.(data_name)); data_type = data_type{1};
    data_value = data_struct.(data_name).(data_type);
    %add to ddb master struct
    ddb_struct.(item_id).(data_name).(data_type) = data_value;
end
%check size
tmp_sz =  length(fieldnames(ddb_struct));