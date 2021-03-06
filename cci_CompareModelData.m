function [model,data]=cci_CompareModelData(wb,yy,mm);
%example for January 2005:
%  listWaveBands=[412 443 490 510 555 670];
%  [model,data]=cci_CompareModelData(listWaveBands,2005,1);
%example of "satellite Chl" in model:
%  RRSB=max(model(:,:,2:3),[],3); RRSG=model(:,:,5);
%  X = log10(RRSB./RRSG); %ratio of blue to green
%  C=[0.2424    -2.7423 +1.8017 +0.0015 -1.2280]; %OC3M-547 (MODIS)
%  a0=C(1); a1=C(2); a2=C(3); a3=C(4); a4=C(5);
%  chld=10.^(a0+a1*X+a2*X.^2+a3*X.^3+a4*X.^4);


gcmfaces_global;

dirModel='daily_model/'; filModel='Rrs_';
dirData='occci-daily-llc90/'; filData='OC_CCI_L3S_Rrs_';
doPlot=0;
dirFig=[];
% dirFig='daily_plots/';

if isempty(whos('wb'))||isempty(wb);
    listWaveBands=[412 443 490 510 555 670];
else;
    listWaveBands=wb;
end;
nwb=length(listWaveBands);

if isempty(whos('yy')); listYears=[1998:2011]; else; listYears=yy; end;
if isempty(whos('mm')); listMonths=[1:12]; else; listMonths=mm; end;

%initialize output if needed:
if nargout>0; model=NaN*repmat(mygrid.XC,[1 1 nwb]); data=model; end;

for iwb=1:nwb;
    wb=listWaveBands(iwb);
    fldCount=0*mygrid.XC; fldModel=fldCount; fldData=fldCount;
    statsD=NaN*zeros(length(listYears)*366,9);%[year day count meanM meanD stdM stdD stdMminusD corrMvsD]
    if ~isempty(dirFig); nameFig=[dirFig filModel num2str(wb)]; end;
    nd=0;
    for yy=listYears;
        for mm=listMonths;
            listDays=[datenum(yy,mm,1):datenum(yy,mm+1,1)-1]-datenum(yy,1,0);
            %the following issue would not occur if unobserved days had been masked:
            test0=dir([dirData filData num2str(wb) '_' num2str(yy)]);
            listDays=listDays(listDays<=test0.bytes/90/1170/4);
            %
            disp([yy listDays(1)])
            for dd=listDays;
                tmpM=read_bin([dirModel filModel num2str(wb) '_' num2str(yy)],dd,0);
                tmpD=read_bin([dirData filData num2str(wb) '_' num2str(yy)],dd,0);
                msk=1+0*mygrid.mskC(:,:,1).*tmpM.*tmpD;
                %
                fldModel(~isnan(msk))=fldModel(~isnan(msk))+tmpM(~isnan(msk));
                fldData(~isnan(msk))=fldData(~isnan(msk))+tmpD(~isnan(msk));
                fldCount(~isnan(msk))=fldCount(~isnan(msk))+1;
                %
                nd=nd+1;
                tmp1=[yy dd sum(~isnan(msk)) nanmean(msk.*tmpM) nanmean(msk.*tmpD) ...
                    nanstd(msk.*tmpM) nanstd(msk.*tmpD) nanstd(msk.*tmpM-tmpD)];
                tmpM=convert2vector(tmpM.*msk); tmpM=tmpM(~isnan(tmpM));
                tmpD=convert2vector(tmpD.*msk); tmpD=tmpD(~isnan(tmpD));
                if length(tmpD)~=length(tmpM); keyboard; end;
                tmpC=corrcoef(tmpM,tmpD);
                stats(nd,:)=[tmp1  tmpC(2,1)];
                tmpC=corrcoef(tmpM,tmpD);
                stats(nd,:)=[tmp1 tmpC(2,1)];
            end;%for dd...
        end;%for mm...
    end;%for yy..
    fldData=fldData./fldCount;
    fldModel=fldModel./fldCount;
    if nargout>0;
        model(:,:,iwb)=fldModel;
        data(:,:,iwb)=fldData;
    end;
    %
    if doPlot;
        cc=max(prctile(fldModel,90),prctile(fldData,90));
        cc=round(cc*1e4)/1e4;
        figureL; m_map_gcmfaces(fldModel,1.2,{'myCaxis',[0:0.1:1.5]*cc},{'myTitle',['Model for ' num2str(wb) 'nm']});
        if ~isempty(dirFig); saveas(gcf,[nameFig 'mean_model'],'fig'); end;
        figureL; m_map_gcmfaces(fldData,1.2,{'myCaxis',[0:0.1:1.5]*cc},{'myTitle',['Data for ' num2str(wb) 'nm']});
        if ~isempty(dirFig); saveas(gcf,[nameFig 'mean_data'],'fig'); end;
        figureL; m_map_gcmfaces(fldModel-fldData,1.2,{'myCaxis',[-0.5:0.1:0.5]*cc},{'myTitle',['Model-Data for ' num2str(wb) 'nm']});
        if ~isempty(dirFig); saveas(gcf,[nameFig 'mean_diff'],'fig'); end;
        %
        figureL;
        dd0=datestr(datenum(listYears(1),listMonths(1),1));
        subplot(3,1,1); plot([1:nd],stats(1:nd,4:5)); legend('model','data'); title('sample mean');
        subplot(3,1,2); plot([1:nd],stats(1:nd,6:8)); legend('model','data','diff'); title('standard deviation');
        subplot(3,1,3); plot([1:nd],stats(1:nd,9)); title('correlation coeff.'); xlabel(['days (1 <-> ' dd0 ')']);
        if ~isempty(dirFig); saveas(gcf,[nameFig 'time_series'],'fig'); end;
        %
        drawnow; refresh; pause(1);
    end;
end;



