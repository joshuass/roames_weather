function dataset_struct = read_odimh5_ppi_data(h5_ffn,dataset_no)

%WHAT: reads ppi from odimh5 volumes into a struct included the required
%variables

%init
dataset_struct = [];
try
    %set dataset name
    dataset_name = ['dataset',num2str(dataset_no)];
    %index data groups
    data_info = h5info(h5_ffn,['/',dataset_name,'/']);
    num_data = length(data_info.Groups)-3; %remove index for what/where/how groups
    %loop through all data sets
    for i=1:num_data
        %read data
        data_name = ['data',num2str(i)];
        data      = double(h5read(h5_ffn,['/',dataset_name,'/',data_name,'/data']));
        quantity  = deblank(h5readatt(h5_ffn,['/',dataset_name,'/',data_name,'/what'],'quantity'));
        offset    = h5readatt(h5_ffn,['/',dataset_name,'/',data_name,'/what'],'offset');
        gain      = h5readatt(h5_ffn,['/',dataset_name,'/',data_name,'/what'],'gain');
        nodata    = h5readatt(h5_ffn,['/',dataset_name,'/',data_name,'/what'],'nodata');
        undetect  = h5readatt(h5_ffn,['/',dataset_name,'/',data_name,'/what'],'undetect');
        %unpack data
        data(data == nodata | data == undetect) = nan;
        data = (data.*gain) + offset;
        %wrap data (first azimuth = last azimuth)
        data = [data,data(:,1)];
        %add to struct
        dataset_struct.(data_name) = struct('data',data,'quantity',quantity);
    end
    %save nquist data
    if i>=2
		try
        	NI     = h5readatt(h5_ffn,['/',dataset_name,'/how'],'NI');
		catch
			NI     = max(abs(dataset_struct.data2.data(:))); %dummy fill using max of abs
		end
    else
        %dummy nyquist data
        NI     = '';
        dataset_struct.data2.data = nan(size(data));
    end
    %read dimensions
    [azi_vec,rng_vec] = read_odimh5_ppi_dims(h5_ffn,dataset_no,true);
    %check dims match image size
    [img_i,img_j] = size(data);
    %abort if size of image does not match h5 dims
    if length(rng_vec) ~= img_i || length(azi_vec) ~= img_j
        utility_log_write('tmp/log.ppi_data_read','',['/dataset',num2str(dataset_no),' img dim not matching h5 dim ',datestr(now)],[err.identifier,' ',err.message]);
        dataset_struct = [];
        return
    end
    dataset_struct.atts = struct('NI',NI,'azi_vec',azi_vec,'rng_vec',rng_vec);
catch err
    dataset_struct = [];
    disp(['/dataset',num2str(dataset_no),' is broken']);
    utility_log_write('tmp/log.ppi_data_read','',[h5_ffn,' for ','/dataset',num2str(dataset_no),' is broken ',datestr(now)],[err.identifier,' ',err.message]);
end  
