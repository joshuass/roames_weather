function climate_generate_kml(data_grid,site_name,site_lat,site_lon,geo_coords,map_config_fn)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Joshua Soderholm, Fugro ROAMES, 2017
%
% WHAT:    generates image kml for the provided data grid and config settings
% INPUTS:  
% RETURNS: 
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%read climate config
load('tmp/climate.config.mat')
%read mapping config
read_config(map_config_fn);
load(['tmp/',map_config_fn,'.mat'])

%colorbar_ffn=generate_colorbar(opt_struct.proc_opt(4),'Density');

%init colourmap
%calc colormap steps
colormap_steps = length(unique(data_grid(:)));
if colormap_steps > 128
    colormap_steps = 128;
end
img_cmap    = flipud(hot(colormap_steps));
%init kml
kml_str     = '';
kml_str     = ge_swath_poly_style(kml_str,'poly_style',html_color(1,silence_edge_color),silence_line_width,html_color(1,silence_face_color),false);
kml_str     = ge_swath_poly_style(kml_str,'trans_poly',html_color(1/255,silence_edge_color),silence_line_width,html_color(1/255,silence_face_color),true);

%resize image
[img_grid,img_cmap] = imresize(data_grid,img_cmap,img_rescale,'nearest','Colormap','original');
img_grid            = double(img_grid);

%create image grids
img_grid    = img_grid./max(img_grid(:)).*colormap_steps;

%create transparency grid
if kml_transparent_flag == 1
    alpha_grid = img_grid./max(img_grid(:));
    %shift transparency
    alpha_grid(alpha_grid>0) = alpha_grid(alpha_grid>0)+0.6;
    alpha_grid(alpha_grid>1) = 1;
else
    alpha_grid = ones(size(img_grid));
end

%convert to rgb
img_grid   = ind2rgb(uint8(img_grid),img_cmap);

%write image to file
image_ffn = [tempdir,'rwx_climate.png'];
imwrite(img_grid,image_ffn,'Alpha',alpha_grid);

%building latlonbox
kml_N_lat = max(geo_coords.radar_lat_vec);
kml_S_lat = min(geo_coords.radar_lat_vec);
kml_E_lon = max(geo_coords.radar_lon_vec);
kml_W_lon = min(geo_coords.radar_lon_vec);
latlonbox = [kml_N_lat,kml_S_lat,kml_E_lon,kml_W_lon];

%create ground overlay kml
kml_tag   = ['IDR',num2str(radar_id,'%02.0f')];
kml_str = ge_groundoverlay(kml_str,['Radar Climatology for ',site_name,' ',kml_tag],'rwx_climate.png',latlonbox,'','','clamped','',1);

%create silence mask
if draw_silence == 1
    [tmp_lat,tmp_lon] = scircle1(site_lat,site_lon,km2deg(silence_radius));
    kml_str = ge_swath_poly(kml_str,'poly_style','radar_blind_spot','','','clampToGround',1,tmp_lon,tmp_lat,zeros(length(tmp_lat),1),'');
end

%create transparent polygon containing stats
tmp_lat = [kml_N_lat,kml_N_lat,kml_S_lat,kml_S_lat,kml_N_lat];
tmp_lon = [kml_W_lon,kml_E_lon,kml_E_lon,kml_W_lon,kml_W_lon];
html_str = ['<p>',kml_tag,' - ',site_name,'</p>',10,...
            '<p>Period: ',date_start,' to ',date_stop,'</p>',10,...
            '<img src="colorbar.png" />'];
            
%generate colorbar image
colorbar_ffn = colorbar_img(img_cmap,data_grid,colorbar_label);
%generate swath poly
kml_str = ge_swath_poly(kml_str,'trans_poly','balloon_popup_poly','','','clampToGround',1,tmp_lon,tmp_lat,zeros(length(tmp_lat),1),html_str);

%size kmlstr and png into a kmz
kmz_fn    = [kml_tag,'_',site_name,'.kmz'];
ge_kmz_out(kmz_fn,kml_str,out_root,{image_ffn,colorbar_ffn});

%remove files
delete(image_ffn)
delete(colorbar_ffn)

function colorbar_ffn = colorbar_img(cmap,data_grid,title)
%generates kmz colorbar image
colorbar_ffn = [tempdir,'colorbar.png'];
%create figure and turn off axis
figure('position',[1 1 60 200]);
set(findall(gca),'visible','off','Fontsize',6);
%assign colormap
colormap(cmap);
%create colorbar
ch = colorbar('Location','manual','Position',[0.1 0.05 .3 .9],'YAxisLocation','right');
%set y label
ylabel(ch,title,'FontSize',8);
%set color axis limits
caxis([min(data_grid(:)) max(data_grid(:))])
%save figure to image and close
saveas(gca,colorbar_ffn,'png');
close(gcf)