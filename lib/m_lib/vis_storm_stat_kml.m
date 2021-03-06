function kml_str = vis_storm_stat_kml(kml_str,storm_jstruct,track_id)

load('tmp/global.config.mat')

timestamps  = datenum(utility_jstruct_to_mat([storm_jstruct.start_timestamp],'S'),ddb_tfmt);
timestep_mm = mode(minute(timestamps(2:end)-timestamps(1:end-1)));
%init string
%loop through cells
tmp_kml = '';
for i=1:length(storm_jstruct)
    %extract stats
    storm_max_tops    = str2num(storm_jstruct(i).max_tops.N);
    storm_max_mesh    = str2num(storm_jstruct(i).max_mesh.N);
    storm_cell_vil    = str2num(storm_jstruct(i).cell_vil.N);
    storm_max_tops    = roundn(storm_max_tops,-1);
    storm_cell_vild   = roundn(storm_cell_vil/storm_max_tops,-2);
    storm_z_centlat   = str2num(storm_jstruct(i).storm_z_centlat.N);
    storm_z_centlon   = str2num(storm_jstruct(i).storm_z_centlon.N);
    cell_id           = storm_jstruct(i).subset_id.N;
    start_timestr     = datestr(timestamps(i),ge_tfmt);
    stop_timestr      = datestr(addtodate(timestamps(i),timestep_mm,'minute'),ge_tfmt);
    %generate kml
    name    = [datestr(timestamps(i),r_tfmt),'_',cell_id];
    tmp_kml = ge_balloon_stats_placemark(tmp_kml,1,...
        '../cell.kml#balloon_stats_style',name,storm_cell_vild,storm_max_mesh...
        ,storm_max_tops,cell_id,storm_z_centlat,storm_z_centlon,...
        start_timestr,stop_timestr);
end
%group into folder
name    = ['track_id_',num2str(track_id)];
kml_str = ge_folder(kml_str,tmp_kml,name,'',1);

