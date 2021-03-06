function asset_data(out_ffn)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Joshua Soderholm, Fugro ROAMES, 2017
%
% WHAT: customisable script to read asset data files and saves them into an
% output file for filtering later. Filtered by asset_filter.m
% INPUTS
% out_ffn: output full filename (str)
% RETURNS: saves asset information to mat file
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%substation csv
sub_struct  = [];
sub_fn      = 'NationalElectricityTransmissionSubstations.csv';
fileID      = fopen(sub_fn);
raw_headers = textscan(fileID,'%s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s',1,'Delimiter',',');
raw_data    = textscan(fileID,'%f %s %s %f %s %s %s %s %f %s %f %s %f %f %f %f','Delimiter',',','HeaderLines',1);
for i=1:length(raw_headers)
    sub_struct.(raw_headers{i}{1}) = raw_data{i};
end

%powerlines shapefile
power_fn     = 'national_transmission_201702.shp';
power_struct = shaperead(power_fn);

%population geotif
pop_fn        = 'Australian_Population_Grid_2011.tif';
pop_grid      = geotiffread(pop_fn);
pop_info      = geotiffinfo(pop_fn);

%export data to files
if exist(out_ffn,'file') == 2
    delete(out_ffn)
end
save(out_ffn,'sub_struct','power_struct','pop_grid','pop_info')