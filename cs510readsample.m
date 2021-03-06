
gcmfaces_global;%this code uses the gcmfaces toolbox (https://github.com/gaelforget/gcmfaces/)

if isempty(mygrid)||~strcmp(mygrid.dirGrid,'GRID_CS510/');
  dirGrid='GRID_CS510/'; nFaces=6; fileFormat='cube';
  grid_load(dirGrid,nFaces,fileFormat); clear dirGrid nFaces fileFormat;
end;

dirPtr='sample_cs510/';
iStep=72; iPtr=1;

[dims,prec,tiles]=cs510readmeta(dirPtr);
n1=tiles(1,2);
n2=tiles(1,4);
n3=dims(3);
recl3D=n1*n2*n3*4;
if strcmp(prec,'float64'); recl3D=2*recl3D; end;

fld=zeros(dims);
for iTile=1:size(tiles,1);
  filPtr=sprintf('res_%04d/_.%010d',iTile-1,iStep);
  filPtr=dir([dirPtr filesep filPtr '*']);
  %
  fid=fopen([filPtr.folder filesep filPtr.name],'r','b');
  status=fseek(fid,(iPtr-1)*recl3D,'bof');
  tmp=reshape(fread(fid,n1*n2*n3,prec),[n1 n2 n3]);
  tmp(tmp==0)=NaN;
  fclose(fid);
  %
  ii=[tiles(iTile,1):tiles(iTile,2)]; 
  jj=[tiles(iTile,3):tiles(iTile,4)];
  fld(ii,jj,:)=tmp;
end;
fld=convert2gcmfaces(fld);

figure; qwckplot(fld(:,:,1)); drawnow;

