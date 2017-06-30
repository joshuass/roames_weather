function kml_str=ge_balloon_stats_style(kml_str,Style_id,url_prefix,icons_path)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Joshua Soderholm, Fugro ROAMES, 2017
%
% WHAT: generates kml for the storm stats values (3) using extendeddata as inputs
%(template stored in style). anchored at lat lon at a height of 20km
% INPUTS
% kml_str: string containing kml
% Style_id: style name containing a # (string)
% place_id: name for kml object (String)
% url_prefix: url prefix for location of icon path (String)
% icons_path: path to location of icon for balloon (String)
% RETURNS
% kml_str: string containing kml
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%generate xml
out=['<Style id="',Style_id,'">',10,...
        '<BalloonStyle>',10,...
            '<text>',10,...
                 '<![CDATA[',10,...
                     '<b><font face="Courier">VILD: $[VILD] g/m^3</font></b><br/>',10,...
                     '<br/>',10,...
                     '<b><font face="Courier">MESH: $[MESH] mm</font></b><br/>',10,...
                     '<br/>',10,...
                     '<b><font face="Courier">Tops: $[EchoTopH] km</font></b><br/>',10,...
                     '<br/>',10,...
                     '<b><font face="Courier">Ctag: $[storm_id]</font></b><br/>',10,...
                     '<br/>',10,...
                 ']]>',10,...
                 '$[geDirections]',10,...
            '</text>',10,...
       '</BalloonStyle>',10,...
       '<IconStyle>',10,...
			'<Icon>',10,...
				'<href>',[url_prefix,icons_path,'lightning_icon.png'],'</href>',10,...
			'</Icon>',10,...
		'</IconStyle>',10,...
        '<LabelStyle>',10,...
            '<scale>0</scale>',10,...
        '</LabelStyle>',10,...    
    '</Style>',10];

%collate
kml_str=[kml_str,out];
