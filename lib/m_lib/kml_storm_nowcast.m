function [nowcast_kml,nowcast_stat_kml]=kml_storm_nowcast(nowcast_kml,nowcast_stat_kml,track_idx,storm_jstruct,track_id)
%WHAT
%for the inputted track 'cur_track', a forecast is produced from the end
%cells using the historical data. Forecast data is saved as forecast swaths
%and historical weighted timeseries graphs. nl links for these 

%INPUT
%cur_track: A single track from track_db
%ident2kml: contains cells from cur_track (and others)
%kml_dir: path to kml directory
%region: region for kml generation
%start_td: kml start time
%stop_td: kml stop time
%cur_vis: kml vis

%OUTPUT
%fcst_nl: network link to forecast swaths
%fcst_graph_nl: netowrklink to balloon graph

%% 
%load config file
load('tmp/global.config.mat');
load('tmp/kml.config.mat');

name        = ['track_id_',num2str(track_id)];

end_cell_idx     = track_idx(end);
timestamp        = datenum(storm_jstruct(end_cell_idx).start_timestamp.S,ddb_tfmt);
[fcst_lat_polys,fcst_lon_polys,fcst_dt,trck_vil,trck_top,trck_mesh,trck_dt,intensity] = storm_nowcast(track_idx,storm_jstruct,timestamp);

if isempty(fcst_dt)
    return
end

tmp_kml = '';
%% generate nowcast kml    
for i=1:length(fcst_lat_polys)
    %if track not at end of database, skip
    if isempty(fcst_lat_polys{i})
        continue
    end
    %generate forecast swath tag
    single_fcst_tag = ['nowcast_',num2str((i)*fcst_step),'min'];
    %generate poly placemark kml of swath
    tmp_kml    = ge_poly_placemark(tmp_kml,['../../track.kml#fcst_',intensity,'_step_',num2str(i),'_style'],single_fcst_tag,'relativeToGround',1,fcst_lon_polys{i},fcst_lat_polys{i},repmat(200,length(fcst_lon_polys{i}),1));
end
%append to kml
nowcast_kml = ge_folder(nowcast_kml,tmp_kml,name,'',1);
%% Forecast graph balloon tag

%calculate number of minutes between end timestep and all other
%timesteps
temp_end_dt = repmat(trck_dt(end),length(trck_dt),1);
hist_min    = etime(datevec(temp_end_dt),datevec(trck_dt))/60;

%preparing graph y data
hist_vild   = trck_vil./trck_top.*1000;
hist_mesh   = trck_mesh;
hist_top    = trck_top./1000;
hist_min    = -hist_min;

nowcast_stat_kml = ge_balloon_graph_placemark(nowcast_stat_kml,1,'../../track.kml#balloon_graph_style','',hist_min,hist_vild,'VILD (g/m^3)',hist_mesh,'MaxExpSizeHail (mm)',hist_top,'Echo-top Height (km)',mean(fcst_lat_polys{end}),mean(fcst_lon_polys{end}));