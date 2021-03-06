function kml_str=ge_poly_style(kml_str,Style_id,LineColor,LineWidth,PolyColor)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Joshua Soderholm, Fugro ROAMES, 2017
%
% WHAT: Create a polygon style kml file using line colour, poly colour and
%line width
% INPUTS
% kml_str: string containing kml
% Style_id: style name containing a # (string)
% LineColor: line colour as a html hex string
% LineWidth: line width as a number (number)
% PolyColor: polygon colour as a html hex string
% RETURNS
% kml_str: string containing kml
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


if isempty(LineColor)
    LineColor=PolyColor;
end
    
out=['<Style id="',Style_id,'">',10,...
        '<LineStyle>',10,...
            '<width>',num2str(LineWidth),'</width>',10,...
            '<color>',LineColor,'</color>',10,...
        '</LineStyle>',10,...
        '<PolyStyle>',10,...
            '<color>',PolyColor,'</color>',10,...
        '</PolyStyle>',10,...
    '</Style>',10];

kml_str=[kml_str,out];
