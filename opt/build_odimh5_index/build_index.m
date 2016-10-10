function build_index
%WHAT: Builds an index for the odimh5 s3 archive.
display('WARNING, CHECK WRITE CAPACITIY OF DDB')
pause
if ~isdeployed
    addpath('/home/meso/Dropbox/dev/wv/lib/m_lib');
    addpath('/home/meso/Dropbox/dev/shared_lib/jsonlab');
end
prefix_cmd     = 'export LD_LIBRARY_PATH=/usr/lib; ';
ddb_table      = 'wxradar-odimh5-index';
s3_odimh5_root = 's3://roames-wxradar-archive/odimh5_archive/';
s3_bucket      = 's3://roames-wxradar-archive/';
radar_id_list  = 50;

for i=1:length(radar_id_list)
    display(['s3 ls for radar_id: ',num2str(radar_id_list(i))])
    s3_odimh5_path = [s3_odimh5_root,num2str(radar_id_list(i)),'/'];
    %run an aws ls -r
    cmd         = [prefix_cmd,'aws s3 ls ',s3_odimh5_path,' --recursive'];
    [sout,eout] = unix(cmd);
    %read text
    C           = textscan(eout,'%*s %*s %u %s');
    h5_name     = C{2};
    h5_size     = C{1};
    %add to archive
    ddb_tmp_struct  = struct;
    for k=1:length(h5_name)
        %skip if not a h5 file
        if ~strcmp(h5_name{k}(end-1:end),'h5')
            continue
        end
        %add to ddb struct
        h5_ffn                  = [s3_bucket,h5_name{k}];
        [ddb_tmp_struct,tmp_sz] = addtostruct(ddb_tmp_struct,h5_ffn,h5_size(k));
        %write to ddb
        if tmp_sz==25 || k == length(h5_name)
            display(['write to ddb ',h5_name{k}]);
            ddb_batch_write(ddb_tmp_struct,ddb_table,0);
            %clear ddb_tmp_struct
            ddb_tmp_struct  = struct;
            %display('written_to ddb')
        end
    end
end
display('complete')
        
        
function [ddb_struct,tmp_sz] = addtostruct(ddb_struct,h5_ffn,h5_size)

%init
h5_fn              = h5_ffn(end-20:end);
radar_id           = h5_fn(1:2);
try
radar_timestamp    = datenum(h5_fn(4:end-3),'yyyymmdd_HHMMSS');
item_id            = ['item_',radar_id,'_',datestr(radar_timestamp,'yyyymmddHHMMSS')];

%build ddb struct
ddb_struct.(item_id).radar_id.N           = radar_id;
ddb_struct.(item_id).start_timestamp.S    = datestr(radar_timestamp,'yyyy-mm-ddTHH:MM:SS');
ddb_struct.(item_id).h5_size.N            = num2str(h5_size);
ddb_struct.(item_id).h5_ffn.S             = h5_ffn;
ddb_struct.(item_id).sig_refl_flag.N      = '0';

tmp_sz =  length(fieldnames(ddb_struct));