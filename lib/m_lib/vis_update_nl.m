function vis_update_nl(kmlobj_struct,storm_jstruct,track_id_list,dest_root,r_id_list,options)

%init
load('tmp/global.config.mat')
load('tmp/vis.config.mat')

%remove kmlobj which don't have a matching entry in storm_jstruct (BUG)
if ~isempty(storm_jstruct) && ~isempty(kmlobj_struct)
    kml_sort_list       = {kmlobj_struct.sort_id};
    kml_type            = {kmlobj_struct.type};
    jstruct_sort_list   = utility_jstruct_to_mat([storm_jstruct.sort_id],'S');
    filter_mask         = ismember(kml_sort_list,jstruct_sort_list) | strncmp('ppi',kml_type,3);
    %check for entries to remove
    if any(~filter_mask)
        kmlobj_struct = kmlobj_struct(filter_mask);
        utility_log_write('tmp/log.update_kml',strjoin(kml_sort_list(~filter_mask)),'','');
    end
end
%% generate new nl kml for cell and scan objects
%load radar colormap and gobal config
for i=1:length(r_id_list)
    %set radar_id
    radar_id  = r_id_list(i);
    ppi_path  = [dest_root,ppi_obj_path,num2str(radar_id,'%02.0f'),'/'];
    cell_path = [dest_root,cell_obj_path,num2str(radar_id,'%02.0f'),'/'];
     
    %PPI Reflectivity
    if options(1)==1
        generate_nl_ppi(radar_id,kmlobj_struct,'ppi_dbzh',ppi_path,max_ge_alt,ppi_minLodPixels,ppi_maxLodPixels);
        offline_type = 'ppi_dbzh';
    end
    %PPI Velcoity
    if options(2)==1
        generate_nl_ppi(radar_id,kmlobj_struct,'ppi_vradh',ppi_path,max_ge_alt,ppi_minLodPixels,ppi_maxLodPixels);
        offline_type = 'ppi_vradh';
    end
    %SingleDoppler
    if options(9)==1
        generate_nl_ppi(radar_id,kmlobj_struct,'ppi_singledop',ppi_path,max_ge_alt,ppi_minLodPixels,ppi_maxLodPixels);
        offline_type = 'ppi_singledop';
    end
    
    %offline ppi data
    if any(options([1,2,9]))
        disp('building offline images')
        generate_offline_nl(radar_id,kmlobj_struct,offline_type,ppi_path);
    end
    
    %iso
    if options(3)==1 || options(4)==1
         generate_nl_cell(radar_id,storm_jstruct,track_id_list,kmlobj_struct,'iso',cell_path,max_ge_alt,iso_minLodPixels,iso_maxLodPixels);
    end
end

function generate_nl_ppi(radar_id,kmlobj_struct,type,nl_path,altLod,minlod,maxlod)

%WHAT: generates kml for ppi objects listed in object_Struct using
%a radar_id and type filter
load('tmp/global.config.mat')

%init radar_id and type list
type_list = {kmlobj_struct.type};
r_id_list = [kmlobj_struct.radar_id];
time_list = [kmlobj_struct.start_timestamp];
%init nl
nl_kml       = '';
name         = [type,'_',num2str(radar_id,'%02.0f')];
%find entries from correct radar_id and type
target_idx   = find(ismember(type_list,type) & r_id_list==radar_id);
%write out offline radar image if no data is present
if isempty(target_idx)
    ge_kml_out([nl_path,name,'.kml'],'','');
    return
end

%sort by time
[~,sort_idx]  = sort(time_list(target_idx));
target_idx    = target_idx(sort_idx);

%loop through entries, appending kml
for j=1:length(target_idx)
    %target data
    target_start     = kmlobj_struct(target_idx(j)).start_timestamp;
    target_stop      = kmlobj_struct(target_idx(j)).stop_timestamp;
    target_link      = kmlobj_struct(target_idx(j)).nl;
    target_latlonbox = kmlobj_struct(target_idx(j)).latlonbox;
	%extend stop time for last item
	if j == length(target_idx)
		target_stop = addtodate(target_stop,10,'minute');
	end
    %nl
    region_kml    = ge_region(target_latlonbox,0,altLod,minlod,maxlod);
    timeSpanStart = datestr(target_start,ge_tfmt);
    timeSpanStop  = datestr(target_stop,ge_tfmt);
    kml_name      = datestr(target_start,r_tfmt);
    nl_kml        = ge_networklink(nl_kml,kml_name,target_link,0,'','',region_kml,timeSpanStart,timeSpanStop,1);
end
%write out
ge_kml_out([nl_path,name,'.kml'],name,nl_kml);

function generate_nl_cell(radar_id,storm_jstruct,track_id_list,kmlobj_struct,type,nl_path,altLod,minlod,maxlod)

%WHAT: generates kml for cell objects listed in object_Struct using
%a radar_id and type filter
load('tmp/global.config.mat')

%init nl
nl_kml       = '';
nl_name      = [type,'_',num2str(radar_id,'%02.0f')];
%exist if no storm struct data
if isempty(storm_jstruct)
    ge_kml_out([nl_path,nl_name,'.kml'],'','');
    return
end

%keep kmlobj_struct entries from radar_id and type 
filt_idx            = find(ismember({kmlobj_struct.type},type) & [kmlobj_struct.radar_id]==radar_id);
kmlobj_struct       = kmlobj_struct(filt_idx);

%init lists
kml_sort_list       = {kmlobj_struct.sort_id};
time_list           = [kmlobj_struct.start_timestamp];

%build jstruct cell list and storm_id list
jstruct_sort_list = utility_jstruct_to_mat([storm_jstruct.sort_id],'S');

%build track_list
[~,Lib]    = ismember(kml_sort_list,jstruct_sort_list);
%exist if no tracks
if isempty(Lib)
    ge_kml_out([nl_path,nl_name,'.kml'],'','');
    return
end
track_list = track_id_list(Lib);

%loop through unique tracks
uniq_track_list = unique(track_list);
for i=1:length(uniq_track_list)
    track_id = uniq_track_list(i);
    %find entries track
    target_idx   = find(track_list==track_id);

    %sort by time
    [~,sort_idx]  = sort(time_list(target_idx));
    target_idx    = target_idx(sort_idx);

    %loop through entries, appending kml
    tmp_kml = '';
    for j=1:length(target_idx)
        %target data
        target_start     = kmlobj_struct(target_idx(j)).start_timestamp;
        target_stop      = kmlobj_struct(target_idx(j)).stop_timestamp;
        target_latlonbox = kmlobj_struct(target_idx(j)).latlonbox;
        target_link      = kmlobj_struct(target_idx(j)).nl;
        target_subset_id = kmlobj_struct(target_idx(j)).sort_id(end-2:end);
		%extend stop time for last item
		if j == length(target_idx)
			target_stop = addtodate(target_stop,10,'minute');
		end
        %nl
        timeSpanStart = datestr(target_start,ge_tfmt);
        timeSpanStop  = datestr(target_stop,ge_tfmt);
        region_kml    = ge_region(target_latlonbox,0,altLod,minlod,maxlod);
        kml_name      = [datestr(target_start,r_tfmt),'_',target_subset_id];
        tmp_kml       = ge_networklink(tmp_kml,kml_name,target_link,0,'','',region_kml,timeSpanStart,timeSpanStop,1);
    end
    
    %group into folder
    track_name = ['track_id_',num2str(track_id)];
    nl_kml     = ge_folder(nl_kml,tmp_kml,track_name,'',1);
end
%write out
ge_kml_out([nl_path,nl_name,'.kml'],nl_name,nl_kml);


function generate_offline_nl(radar_id,kmlobj_struct,type,nl_path)
%find entries from correct radar_id
r_id_list  = [kmlobj_struct.radar_id];
%write out offline radar image if no data is present
if ~any(r_id_list==radar_id)
    radar_id_str = num2str(radar_id,'%02.0f');
    nl_kml       = ge_networklink('','Radar Offline',['radar_offline_',radar_id_str,'.kmz'],0,0,60,'','','',1);
    name         = [type,'_',num2str(radar_id,'%02.0f')];
    ge_kml_out([nl_path,name,'.kml'],radar_id_str,nl_kml);
    return
end
