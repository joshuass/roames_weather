function VOLtoLZ4_batch
%WHAT: converts all files in all folders which are .VOL into .VOL.lz4


source_folder='/media/meso/storage/marburg_radar_data/2015/'; %all in one folder
%list all files in source_folder
source_ffn = getAllFiles(source_folder);
log={};

for i=1:length(source_ffn)
    disp(['processing ',num2str(i),' of ',num2str(length(source_ffn))]);
    target_fn_path=source_ffn{i};
    
    if ~strcmp(target_fn_path(end-2:end),{'VOL'})
       disp(['NOT A VOL: ',source_ffn{i}])
       log=[log;{source_ffn{i},'NOT A VOL'}];
       continue
    end
    
    cmd_text=['lz4c -hc -y ',target_fn_path,' ',target_fn_path,'.lz4'];
    [status,cmdout]=system(cmd_text);
    if exist([target_fn_path,'.lz4'],'file')==2
        delete(target_fn_path)
        log=[log;{source_ffn{i},'Success'}];
        disp('Success')
    else
        disp(['LZ4 fail: ',source_ffn{i}])
        log=[log;{source_ffn{i},'LZ$ Failed'}];
    end
end

%date_str=datestr(now,'yymmdd_HHMM');
%save(['log_file_VOLtoLZ4_',date_str,'.mat'],'log')