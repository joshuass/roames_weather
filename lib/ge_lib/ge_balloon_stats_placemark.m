function kml_str=ge_balloon_stats_placemark(kml_str,vis,Style_id,place_id,vild,mesh,tops,ident_id,lat,lon)
%WHAT: generates kml for the storm stats values (3) using extendeddata as inputs
%(template stored in style). anchored at lat lon at a height of 20km

out=['<Placemark>',10,...
            '<name>',place_id,'</name>',10,...
            '<styleUrl>',Style_id,'</styleUrl>',10,...
            '<visibility>',num2str(vis),'</visibility>',10,...  
            '<ExtendedData>',10,...
                '<Data name="vild">',10,...
                    '<value>',num2str(vild),'</value>',10,...
                '</Data>',10,...
                '<Data name="mesh">',10,...
                    '<value>',num2str(mesh),'</value>',10,...
                '</Data>',10,...
                '<Data name="tops">',10,...
                    '<value>',num2str(tops),'</value>',10,...
                '</Data>',10,...
                '<Data name="ident_id">',10,...
                    '<value>',num2str(ident_id),'</value>',10,...
                '</Data>',10,...
            '</ExtendedData>',10,...
            '<Point>',10,...
                '<extrude>1</extrude>',10,...
                '<altitudeMode>absolute</altitudeMode>',10,...
                '<coordinates>',num2str(lon),',',num2str(lat),',',num2str(20000),'</coordinates>',10,...
            '</Point>',10,...
    '</Placemark>',10];
    
kml_str=[kml_str,out];