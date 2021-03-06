function singledop_validate
%WHAT: ingests the output of singledop_validate_compute and aws data to
%compare obs

aws_path = '/run/media/meso/DATA/project_data/singledop_aws_obs_2006-2016/';
% build_bom_aws(aws_path,'040842')
% build_bom_aws(aws_path,'040211')
% build_bom_aws(aws_path,'040983')
% build_bom_aws(aws_path,'040764')
% build_bom_aws(aws_path,'040004')
% build_bom_aws(aws_path,'040913')


%load singledop data
singledop_fn = 'sdvalidate_66_20170608_123731.mat';
load(singledop_fn);

aws_wspd_mat = nan(size(sd_wspd_mat));
aws_wdir_mat = nan(size(sd_wspd_mat));

for m = 1:length(aws_id_list)
    aws_id   = aws_id_list(m);
    aws      = load([aws_path,'0',num2str(aws_id)]);
    aws_dt   = aws.dataset.dt;
    aws_dt   = aws_dt-(1/24*10); %convert to UTC to match radar
    aws_wspd = aws.dataset.wspd;
    aws_wdir = aws.dataset.wdir;
    for n = 1:length(fetch_date_list)
        [~,aws_idx] = min(abs(fetch_date_list(n)-aws_dt));
        if isempty(aws_idx)
            disp(['skipped ',num2str(aws_id),' ',datestr(fetch_date_list(n))]);
            continue
        end
        aws_wspd_mat(n,m)   = mean(aws_wspd(aws_idx));
        aws_wdir_mat(n,m)   = mean(aws_wdir(aws_idx));
    end
end
aws_alt_mat = repmat(ar_alt_list,1,length(fetch_date_list))+0.174;
keyboard

%histogram plot
figure
plot_aws_wspd           = aws_wspd_mat(:);
plot_aws_wdir           = aws_wdir_mat(:);
plot_aws_alt            = aws_alt_mat(:);
plot_sd_wspd            = sd_wspd_mat(:).*3.6;
plot_sd_wdir            = sd_wdir_mat(:);
high_mask               = plot_aws_wspd>=35;
high_mask               = true(length(plot_aws_wspd),1);
diff_wspd               = plot_aws_wspd-plot_sd_wspd;
histogram(diff_wspd(high_mask),[-55:10:55],'Normalization','probability')
xlabel('AWS-Doppler difference (km/h)')
ylabel('Probability (%)')
%stats
nanmean(diff_wspd(high_mask))
sum(high_mask)
%diff vs aws speed line plot
figure
plot(plot_aws_wspd(high_mask),diff_wspd(high_mask),'b.')
xlabel('AWS (km/h)')
ylabel('AWS-Doppler difference (km/h)')
grid on
%diff vs direction plot
figure
plot(plot_aws_wdir(high_mask),diff_wspd(high_mask),'b.')
xlabel('Direction (degTN)')
ylabel('AWS-Doppler difference (km/h)')
grid on
%diff vs elevation plot
figure
plot(plot_aws_alt(high_mask).*1000,diff_wspd(high_mask),'b.')
xlabel('Radar beam altitude above AWS (km/h)')
ylabel('AWS-Doppler difference (m)')
grid on

function build_bom_aws(aws_path,aws_id)
%merges two 5 year AWS datasets containing wind data into single struct and
%saves to file
%load two datasets
dataset_1    = read_bom([aws_path,'HD01D_',aws_id,'_1.txt']);
dataset_2    = read_bom([aws_path,'HD01D_',aws_id,'_2.txt']);
%merge
dataset      = struct;
dataset.id   = dataset_1.id;
dataset.dt   = [dataset_1.dt;dataset_2.dt];
dataset.wspd = [dataset_1.wspd;dataset_2.wspd];
dataset.wdir = [dataset_1.wdir;dataset_2.wdir];
dataset.gspd = [dataset_1.gspd;dataset_2.gspd];
%save
save([aws_path,aws_id,'.mat'],'dataset')
%update user
disp(['aws ',aws_id,' complete'])

function dataset = read_bom(path)
%Joshua Soderholm, Feb 2016
%Climate Research Group, University of Queensland

%% WHAT
%_Reads bom HD01D (1min) wind data

%_Using the following changes to the standard configuration (ex. time)
%-extra field: station name, station number, lat, lon, elev
%-time format: YYYMMDDHH24MI (UTC)
%-time interval: all
%-data: wspd (km/h), gspd (km/h), wdir (deg)

%%

%open file and read
fid = fopen(path);
%                   hd  id date wspd  qc wdir  qc  gspd  qc   #        
C   = textscan(fid,'%*s %f %s   %f   %*s  %f  %*s  %f   %*s  %*s','Delimiter',',','HeaderLines',1);    
%close file
fclose(fid);

%create struct
dataset = struct;

%fill in header
dataset.id   = C{1}(1);

%add time
dataset.dt   = datenum(C{2},'yyyymmddHHMM');

%add data
dataset.wspd = C{3};
dataset.wdir = C{4};
dataset.gspd = C{5};