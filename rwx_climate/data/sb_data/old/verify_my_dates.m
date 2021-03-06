verify_date_list=...
    {'04-11-08';...
    '07-10-09';...
    '25-10-09';...
    '16-11-09';...
    '17-11-09';...
    '19-12-09';...
    '22-12-09';...
    '03-01-10';...
    '13-11-13';...
    '14-11-13';...
    '15-11-13';...
    '16-11-13';...
    '18-11-13';...
    '24-11-13';...
    '14-12-13';...
    '29-12-13';...
    '06-01-14'};

verify_datenum=datenum(verify_date_list,'dd-mm-yy');
ffn='ARCH_Days_C.mat';
load(ffn);

C = intersect(target_days,verify_datenum);

display([num2str(length(C)),' out of ',num2str(length(verify_datenum)),' sb days are captured by the ',ffn,' list'])

    