year_list = 1997:2016;

header = [...
    '#!/usr/bin/env python',10,...
    'from api import ECMWFDataServer',10,...
    'server = ECMWFDataServer()',10,...
    'server.retrieve({',10,...
    '"class"   : "ei",',10,...
    '"dataset" : "interim",',10];
    
footer = [...
    '"expver"  : "1",',10,...
    '"grid"    : "0.75/0.75",',10,...
    '"levelist": "250/300/400/450/500/550/600/650/700/750/800/850/900/950/1000",',10,...
    '"levtype" : "pl",',10,...
    '"param"   : "130.128/129.128",',10,...
    '"step"    : "0",',10,...
    '"stream"  : "oper",',10,...
    '"time"    : "00/06/12/18",',10,...
	'"area"    : "-10/110/-45/155",',10,...
    '"type"    : "an",',10,...
	'"format"  : "netcdf",',10];
    

for i = 1:length(year_list)
    target_year    = year_list(i);
    py_fn          = ['scripts/era_fetch_',num2str(target_year),'.py'];
    nc_fn          = ['era_wv_',num2str(target_year),'.nc'];
    %create date strings
    start_date_str = [num2str(target_year),'-01-01'];
    if target_year == 2016
        stop_date_str = [num2str(target_year),'-06-30'];
    else
        stop_date_str = [num2str(target_year),'-12-31'];
    end
    date_line   = ['"date"    : "',start_date_str,'/to/',stop_date_str,'",',10];
    %create target
    target_line = ['"target"  : "',nc_fn,'",',10,'})'];
    %write to file
    era_str = [header,date_line,footer,target_line];
    fid = fopen(py_fn,'w');
    fprintf(fid,'%s',era_str);
    fclose(fid);
end