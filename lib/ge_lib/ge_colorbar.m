function ge_colorbar
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Joshua Soderholm, Fugro ROAMES, 2017
%
% WHAT: generates colorbar images for reflectivity and Doppler velocity layers. Only needs to be run once
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

load('colormaps.mat')

%Reflectivity colourmap
figure
colormap(interp_refl_cmap);
%custom labels
colorbar('YTickLabel',...
    {'-30','-20','-10','0','10','20','30','40',...
     '50','60','70'},'YTick',[2,12,22,32,42,52,62,72,82,92,102].*2,'FontWeight','bold','FontSize',14);
axis off
%save to file, load, crop resave
saveas(gca,'refl_colorbar.png')
refl_colorbar = imread('refl_colorbar.png', 'png');
refl_colorbar=refl_colorbar(60:820,1000:1100,:);
imwrite(refl_colorbar,'refl_colorbar.png','png')
close gcf

%Velocity colourmap
figure
colormap(interp_vel_cmap);
%custom labels
colorbar('YTickLabel',...
    {'-70','-60','-50','-40','-30','-20','-10','0','10',...
     '20','30','40','50','60','70'},'YTick',[1,6,11,16,21,26,31,36,41,46,51,56,61,66,71].*2,'FontWeight','bold');
axis off
%save to file, load, crop resave
saveas(gca,'vel_colorbar.png')
vel_colorbar = imread('vel_colorbar.png', 'png');
vel_colorbar=vel_colorbar(60:820,1000:1100,:);
imwrite(vel_colorbar,'vel_colorbar.png','png')
close gcf


