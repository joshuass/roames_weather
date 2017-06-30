function kml_str = ge_balloon_stats_placemark(kml_str,vis,Style_id,place_id,vild,mesh,tops,storm_id,lat,lon,timeSpanStart,timeSpanStop)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Joshua Soderholm, Fugro ROAMES, 2017
%
% WHAT: generates kml for the storm stats values (3) using extendeddata as inputs
%(template stored in style). anchored at lat lon at a height of 20km
% INPUTS
% kml_str: string containing kml
% vis: flag for visbility (binary)
% Style_id: style name containing a # (string)
% place_id: name for kml object (String)
% vild: vil density value for table (number) (kg/m2)
% mesh: mesh value for table (number) (mm)
% tops: storm tops value for table (number) (km)
% storm_id: storm id string for reference from storm ddb (string)
% lat: lat value for balloon placement (number) (deg)
% lon: lon value for balloon placement (number) (deg)
% timeSpanStart: starting time for kml time span (GE timestamp) (str)
% timeSpanStop: stoping time for kml time span (GE timestamp) (str)
% RETURNS
% kml_str: string containing kml
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%build timekml if values inputted, otherwise blank
if isempty(timeSpanStart)
    timekml='';
else
    timekml=['<TimeSpan><begin>' timeSpanStart '</begin><end>' timeSpanStop '</end></TimeSpan>',10];
end

%generate string
out=['<Placemark>',10,...
            '<name>',place_id,'</name>',10,...
            '<styleUrl>',Style_id,'</styleUrl>',10,...
            '<visibility>',num2str(vis),'</visibility>',10,...
            timekml,...
            '<ExtendedData>',10,...
                '<Data name="VILD">',10,...
                    '<value>',num2str(vild),'</value>',10,...
                '</Data>',10,...
                '<Data name="MESH">',10,...
                    '<value>',num2str(mesh),'</value>',10,...
                '</Data>',10,...
                '<Data name="EchoTopH">',10,...
                    '<value>',num2str(tops),'</value>',10,...
                '</Data>',10,...
                '<Data name="storm_id">',10,...
                    '<value>',storm_id,'</value>',10,...
                '</Data>',10,...
            '</ExtendedData>',10,...
            '<Point>',10,...
                '<extrude>1</extrude>',10,...
                '<altitudeMode>absolute</altitudeMode>',10,...
                '<coordinates>',num2str(lon),',',num2str(lat),',',num2str(20000),'</coordinates>',10,...
            '</Point>',10,...
    '</Placemark>',10];
    
%append to output
kml_str=[kml_str,out];
