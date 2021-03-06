function asset_table = asset_filter(data_ffn,poly_lat,poly_lon)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Joshua Soderholm, Fugro ROAMES, 2017
%
% WHAT: using the poly lat/lon filter to filter asset information to build
%impact stats table (in html format)
% INPUTS
% data_ffn: input data full filename from asset_data.m (str)
% poly_lat: vector of polygon lats (double)
% poly_lon: vector of polygon lons (double)
% RETURNS
% asset_table: html string containing table structure (str)
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% load data_ffn
load(data_ffn)

%use polygon to filter substations, extract name and capacity
sub_mask     = inpolygon(sub_struct.LONGITUDE,sub_struct.LATITUDE,poly_lon,poly_lat);
sub_names    = [sub_struct.NAME(sub_mask)];
sub_capacity = [sub_struct.CAPACITY_kV(sub_mask)];

%powerlines
%shapefile stores individual powerline segments
power_kv  = [];
power_len = [];
%for each powerline segment, extract lat lon
for i=1:length(power_struct)
    power_lat  = power_struct(i).Y;
    power_lon  = power_struct(i).X;
    %use polygon to mask lat lon
    power_mask = inpolygon(power_lon,power_lat,poly_lon,poly_lat);
    if sum(power_mask)>1 %need more than one pole
        %calculate ditance of lat lon segments in polygon
        power_lat     = power_lat(power_mask);
        power_lon     = power_lon(power_mask);
        [len_pairs,~] = distance(power_lat(1:end-1),power_lon(1:end-1),power_lat(2:end),power_lon(2:end));
        seg_len       = deg2km(sum(len_pairs));
        power_kv      = [power_kv;str2double(power_struct(i).CAPACITY_k)];
        power_len     = [power_len;seg_len];
    end
end
%sum powerline segments for unique kv
[sum_power_kv,~,ic]  = unique(power_kv);
sum_power_len        = zeros(length(sum_power_kv),1);
for i=1:length(sum_power_len)
    sum_mask         = ic==i;
    sum_power_len(i) = round(sum(power_len(sum_mask)));
end

%mask population raster using poly2mask and sum
[poly_map_x,poly_map_y] = projfwd(pop_info,poly_lat,poly_lon);
[poly_y,poly_x]         = map2pix(pop_info.RefMatrix,poly_map_x,poly_map_y);
pop_mask                = poly2mask(poly_x, poly_y, pop_info.Height, pop_info.Width);
total_pop               = round(sum(pop_grid(pop_mask)));
nf                      = java.text.DecimalFormat;
total_pop_str           = char(nf.format(total_pop));

%generate variable html rows for substation
sub_html = '';
if ~isempty(sub_names)
    for i=1:length(sub_names)
        sub_html = [sub_html,...
                      '<tr>',10,...
                      '<td>',sub_names{i},'</td>',10,...
                      '<td>',num2str(sub_capacity(i)),'</td>',10,...
                      '</tr>',10];
    end
else
    sub_html    = ['<tr>',10,...
                      '<td>None</td>',10,...
                      '<td>N/A</td>',10,...
                      '</tr>',10];
end
%generate variable html rows for powerlines
power_html = '';
if ~isempty(sum_power_kv)
    for i=1:length(sum_power_kv)
        power_html = [power_html,...
                      '<tr>',10,...
                      '<td>',num2str(sum_power_kv(i)),'</td>',10,...
                      '<td>',num2str(sum_power_len(i)),'</td>',10,...
                      '</tr>',10];
    end
else %blank
    power_html    = ['<tr>',10,...
                      '<td>None</td>',10,...
                      '<td>N/A</td>',10,...
                      '</tr>',10];
end

%collate html table + add population field
asset_table = ['<table style="width:100%">',10,...
  '<tr>',10,...
    '<td><b>Substation</b></td>',10,...
    '<td><b>Substation kV</b></td>',10,...
  '</tr>',10,...
  '<tr>',10,...
    sub_html,...
  '</tr>',10,...
  '<tr>',10,...
    '<td><b>Lines kV</b></td>',10,...
    '<td><b>Lines km</b></td>',10,...
  '</tr>',10,...
  '<tr>',10,...
    power_html,...
  '</tr>',10,...
  '<tr>',10,...
    '<td><b>Population:</b></td>',10,...
    '<td>',total_pop_str,'</td>',10,...
  '</tr>',10,...
'</table>',10];