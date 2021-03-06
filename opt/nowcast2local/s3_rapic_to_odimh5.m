function s3_rapic_to_odimh5

%WHAT: converts rapic files on s3 to odimh5 files on s3
%rapic files names are in the folder root/radar_id/paths/.../.rapic
%odimh5 filename radar_id and date are derived from the odimh5 file header
%(/what)
%odimh5 files are moved back into s3 with
%root/radarid/yyyy/mm/dd/id_yyyymmdd_HHMM00.h5

%paths
if ~isdeployed
    addpath('../../etc')
    addpath('../../lib/m_lib')
end
addpath('etc')

mkdir('tmp')

%init
s3_input_root = 's3://roames-weather-rapic/';
s3_input_path = 'rapic_archive/201606-09/';
s3_output     = 's3://roames-weather-odimh5/odimh5_archive/';
prefix_cmd    = 'export LD_LIBRARY_PATH=/usr/lib; ';
log_fn        = 'matlab.log';
config_fn     = 'rapic_to_odimh5_config';

%read config
read_config(config_fn);
load(['tmp/',config_fn,'.mat']);

for i = 1:length(radar_id_list)
    radar_id   = radar_id_list(i);
    radar_path = [s3_input_root,s3_input_path,num2str(radar_id,'%02.0f'),'/'];
    %run s3 ls cmd
    cmd        = [prefix_cmd,'aws s3 ls --recursive ',radar_path];
    [~,eout]   = unix(cmd);
    %no files
    if isempty(eout)
        disp(['no files for radar ',num2str(radar_id)]);
        write_log(log_fn,'s3 ls not files for radar id',num2str(radar_id))
        continue
    end
    C = textscan(eout,'%*s %*s %*f %s'); rapic_fn_list = C{1};
    for j = 1:length(rapic_fn_list)
        rapic_ffn = rapic_fn_list{j};
        %update user
        disp(['processing ',rapic_ffn])
        [~,rapic_fn,rapic_ext] = fileparts(rapic_ffn);
        %check if rapic file
        if ~strcmp(rapic_ext,'.rapic')
            disp([rapic_fn,' not a rapic'])
            write_log(log_fn,'filename not rapic',rapic_fn)
            continue
        end
        %copy locally
        local_rapic_ffn = [tempdir,rapic_fn,rapic_ext];
        cmd             = [prefix_cmd,'aws s3 cp ',s3_input_root,rapic_ffn,' ',local_rapic_ffn];
        [~,~]           = unix(cmd);
        if exist(local_rapic_ffn,'file') ~= 2
            disp([local_rapic_ffn,' failed to download'])
            write_log(log_fn,'s3 download rapic',local_rapic_ffn)
            continue
        end
        %convert to odimh5 and remove
        local_odimh5_ffn = [tempdir,rapic_fn,'.h5'];
        cmd              = [prefix_cmd,' rapic_to_odim ',local_rapic_ffn,' ',local_odimh5_ffn];
        [sout,eout]      = unix(cmd);
        if sout ~= 0
            disp([local_odimh5_ffn,' failed to convert with error ',eout])
            write_log(log_fn,'convert failed',eout)
            delete(local_rapic_ffn)
            continue
        end
        if exist(local_odimh5_ffn,'file') ~= 2
            disp([local_odimh5_ffn,' failed to convert'])
            write_log(log_fn,'convert missing',local_odimh5_ffn)
            delete(local_rapic_ffn)
            continue
        end
        delete(local_rapic_ffn)
        %read odimh5 vol time and radar id
        source_att   = h5readatt(local_odimh5_ffn,'/what','source');                                    
        h5_radar_id  = str2num(source_att(7:8));
        h5_vol_date  = deblank(h5readatt(local_odimh5_ffn,'/what/','date'));
        h5_vol_time  = deblank(h5readatt(local_odimh5_ffn,'/what/','time'));
        h5_datetime  = datenum([h5_vol_date,h5_vol_time],'yyyymmddHHMMSS');
        h5_datevec   = datevec(h5_datetime);
        %move to s3
        odimh5_fn     = [num2str(h5_radar_id,'%02.0f'),'_',datestr(h5_datetime,'yyyymmdd_HHMM'),'00.h5'];
        s3_odimh5_ffn = [s3_output,num2str(h5_radar_id,'%02.0f'),'/',num2str(h5_datevec(1)),'/',...
            num2str(h5_datevec(2),'%02.0f'),'/',num2str(h5_datevec(3),'%02.0f'),'/',odimh5_fn];
        cmd           = [prefix_cmd,'aws s3 mv ',local_odimh5_ffn,' ',s3_odimh5_ffn,' >> tmp/log.mv 2>&1 &'];
        [~,~]         = unix(cmd);
        disp('complete')
    end
    utility_pushover('s3_rapic_to_odimh5',['finished radar ',num2str(radar_id)]);
end
utility_pushover('s3_rapic_to_odimh5',['COMPLETE fire sites ',num2str(radar_id_list)]);

%log each error and pass file to brokenVOL archive
function write_log(log_fn,type,msg)
log_fid = fopen(log_fn,'a');
display(msg)
fprintf(log_fid,'%s %s %s\n',datestr(now),type,msg);
fclose(log_fid);


