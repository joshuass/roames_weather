function kml_out=ge_line_string(kml_in,vis,name,timeSpanStart,timeSpanStop,styleUrl,relative_altitude,altitudeMode,extrude,tessellate,start_lat_vec,start_lon_vec,end_lat_vec,end_lon_vec)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Joshua Soderholm, Fugro ROAMES, 2017
%
% WHAT: Creates a kml string in the line sereies format using a start and
%end point approach.
% INPUTS
% kml_str: string containing kml
% vis: flag for visbility (binary)
% name: name to assign xml object (string)
% timeSpanStart: starting time for kml time span (GE timestamp) (str)
% timeSpanStop: stoping time for kml time span (GE timestamp) (str)
% styleUrl: style name containing a # (string)
% relative_altitude: altitude vector containing heights of each point (matrix) (m)
% altitudemode: string containing an acceptable altitudemode clamped/absolute
% extrude: flag for extending nodes down to surface (binary
% tessellate: smooth line using tesselation (binary)
% start_lat_vec: lat vector for starting points of line segment pairs
% start_lon_vec: lon vector for starting points of line segment pairs
% end_lat_vec: lat vector for end points of line segment pairs
% end_lon_vec: lon vector for end points of line segment pairs
% RETURNS
% kml_str: string containing kml
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


kml_out=[''];

%build timekml if values inputted, otherwise blank
if isempty(timeSpanStart)
    timekml='';
else
    timekml=['<TimeSpan><begin>' timeSpanStart '</begin><end>' timeSpanStop '</end></TimeSpan>',10];
end

%build headers and footers
header=['<Placemark>',10,...
            '<name>',name,'</name>',10,...
            '<visibility>',num2str(vis),'</visibility>',10,...
            timekml,...
            '<styleUrl>',styleUrl,'</styleUrl>',10,...
            '<LineString>',10,...
                '<tessellate>',num2str(tessellate),'</tessellate>',10,...
                '<extrude>',num2str(extrude),'</extrude>',10,...
                '<altitudeMode>',altitudeMode,'</altitudeMode>',10,...
                '<coordinates>',10];
            
footer=        ['</coordinates>',10,...
            '</LineString>',10,...
        '</Placemark>',10];

%convert vector locations into a kml string
line_str = '';
for i=1:length(start_lat_vec)
     line_str=[line_str,...
         sprintf('%.6f,%.6f,%.6f', start_lon_vec(i), start_lat_vec(i), relative_altitude),10];
end

%collate and append to header and footer
line_str=[line_str,sprintf('%.6f,%.6f,%.6f', end_lon_vec(i), end_lat_vec(i), relative_altitude),10]; 
kml_out=[kml_out,header,line_str,footer];
 
%append to master
kml_out=[kml_in,kml_out];
