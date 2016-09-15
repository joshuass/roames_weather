function kml_str=ge_groundoverlay(kml_str,name,image_path,LatLonBox,timeSpanStart,timeSpanStop,altitudemode,altitude,visible)
%WHAT: generates a ground overlay kml object for an image using its latlonbox,
%start/stop ts

%build altitudemode kml string
if strcmp(altitudemode,'clamped')
    altkml=['<altitudeMode>clampToGround</altitudeMode>',10];
elseif strcmp(altitudemode,'absolute')
    altkml=['<altitudeMode>absolute</altitudeMode>',10,...
        '<altitude>',num2str(altitude),'</altitude>',10];
end

%build timekml if values inputted, otherwise blank
if isempty(timeSpanStart)
    timekml='';
else
    timekml=['<TimeSpan><begin>' timeSpanStart '</begin><end>' timeSpanStop '</end></TimeSpan>',10];
end

out=['<GroundOverlay>',10,...
        '<name>',name,'</name>',10,...
        '<visibility>',num2str(visible),'</visibility>',10,...   
        timekml,...
        '<color>C0ffffff</color>',10,...
        '<Icon>',...
             '<href>',image_path,'</href>',10,...
        '</Icon>',10,...
        altkml,...
        '<LatLonBox>',10,...
                 '<north>',num2str(LatLonBox(1)),'</north>',10,...
                 '<south>',num2str(LatLonBox(2)),'</south>',10,...
                 '<east>',num2str(LatLonBox(3)),'</east>',10,...
                 '<west>',num2str(LatLonBox(4)),'</west>',10,...
                 '<rotation>0</rotation>',10,...
             '</LatLonBox>',10,...
      '</GroundOverlay>',10];
  
kml_str=[kml_str,out]; 
             
