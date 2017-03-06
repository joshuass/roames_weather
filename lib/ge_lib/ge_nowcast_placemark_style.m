function kml_str=ge_nowcast_placemark_style(kml_str,Style_id,url_prefix,icons_path,icon_color)
%style for balloon storm history graph containing html template and icon link

out=['<Style id="',Style_id,'">',10,...
        '<BalloonStyle>',10,...
            '<text><![CDATA[',...
                '$[table_html]<br/>',...
                '<img src="http://chart.apis.google.com/chart?&chxt=x,y&chs=150x100&cht=lxy&chds=a&chd=t:$[x_data1]|$[y_data1]&chco=FF0000&chls=1,6,3&chtt=$[ctitle1]"/>',...
                '<img src="http://chart.apis.google.com/chart?&chxt=x,y&chs=150x100&cht=lxy&chds=a&chd=t:$[x_data2]|$[y_data2]&chco=0000FF&chls=1,6,3&chtt=$[ctitle2]"/>',...
                '<img src="http://chart.apis.google.com/chart?&chxt=x,y&chs=150x100&cht=lxy&chds=a&chd=t:$[x_data3]|$[y_data3]&chco=00FF00&chls=1,6,3&chtt=$[ctitle3]"/>',...
            ']]></text>',10,...
       '</BalloonStyle>',10,...
       '<LineStyle>',10,...
		    '<color>',icon_color,'</color>',10,...
	   '</LineStyle>',10,...
       '<IconStyle>',10,...
            '<color>',icon_color,'</color>',10,...
			'<Icon>',10,...
				'<href>',[url_prefix,icons_path,'graph_icon.png'],'</href>',10,...
			'</Icon>',10,...
		'</IconStyle>',10,...
        '<LabelStyle>',10,...
            '<scale>0</scale>',10,...
        '</LabelStyle>',10,...    
    '</Style>',10];

kml_str=[kml_str,out];