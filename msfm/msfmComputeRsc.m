function [ anim SBasis clusInd ] = msfmComputeRsc( W, Sim2, Sim3 )
% Computes the rigid shape chain
%
% USAGE
%  [ anim SBasis clusInd ] = msfmComputeRsc( anim, Sim2, Sim3 )
%
% INPUTS
%  W            - [ 2 x nFrame ] measurements
%  Sim2         - [ nFrame x nFrame ] similarity matrix
%  Sim3         - {nFrame}[ nFrame x nFrame ] similarity tensor
%
% OUTPUTS
%  anim         - output animation
%  SBasis       - [ 3 x nPoint x nClus ] rigid shape basis
%  clusInd      - [ nFrame ] cluster a frame belongs to
%
% EXAMPLE
%
% See also

% Vincent's Structure From Motion Toolbox      Version NEW
% Copyright (C) 2008 Vincent Rabaud.  [vrabaud-at-cs.ucsd.edu]
% Please email me if you find bugs, or have suggestions or questions!
% Licensed under the GPL [see external/gpl.txt]

anim=Animation(); anim.W=W;
nFrame=anim.nFrame; nPoint=anim.nPoint;
anim.S = zeros(3,nPoint,nFrame); anim.R = zeros(3,3,nFrame);
anim.t = zeros(3,nFrame);

% create an approximated graph
if nargin>=3 && ~isempty(Sim3)
  SimTot=approxGraph(Sim2,Sim3);
else
  SimTot=Sim2;
end

% remove the close temporal neighbors
SimTot(spdiags(logical(ones(nFrame,2*5+1)),[-5:5],nFrame,nFrame)) = Inf;

% create a similarity matrix and cluster it
sig=2;
W=real(exp(-SimTot.^2/2/sig^2));

test = true;

nClus = size(Sim2,1)/3;
while test
  clusInd=nCut(SimTot,sig,nClus); test = false;
  for n=1:nClus
    if nnz(clusInd==n)<4; nClus = nClus - 1; test=true; break; end
  end
end

%%% 3D recovery (RSC)
SBasis=zeros(3,nPoint,nClus);
clus = cell(1,nClus);
anim.t = mean(anim.W,2); W = bsxfun(@minus,anim.W,anim.t);
anim.t = squeeze(anim.t); anim.t(3,:)=1;
for n=1:nClus
  % recover the 3D shape for each cluster
  clus{n} = find(clusInd==n)';
  animPair=computeSMFromW(anim.isProj, 'W',W(:,:,clus{n}), ...
    'method',Inf,'isCalibrated',true);
  SBasis(:,:,n)=animPair.S;
  P=animPair.P;

  % recover the rotation matrices
  anim.R(:,:,clus{n}) = animPair.R;
end

% center the basis
SBasis=bsxfun(@minus,SBasis,mean(SBasis,2));

% recover the best rotations to align all the shapes
% first recover matrices to align the clusters ...

% we will compute R to minimze RA, R is [ 3 x 3*nCluster ] 
% and the set of cluster global rotation
A = zeros(3*nClus, 3*nClus);

for n=1:nClus
  for f=clus{n}
	if f>1 && clusInd(f-1)~=n
      A(3*n+(-2:0),3*n+(-2:0)) = A(3*n+(-2:0),3*n+(-2:0)) + SBasis(:,:,n)*SBasis(:,:,n)';
	  i = clusInd(f-1);
	  A(3*i+(-2:0),3*n+(-2:0)) = A(3*i+(-2:0),3*n+(-2:0)) - SBasis(:,:,i)*SBasis(:,:,n)';
	end
	if f<nFrame && clusInd(f+1)~=n
      A(3*n+(-2:0),3*n+(-2:0)) = A(3*n+(-2:0),3*n+(-2:0)) + SBasis(:,:,n)*SBasis(:,:,n)';
	  i = clusInd(f+1);
	  A(3*i+(-2:0),3*n+(-2:0)) = A(3*i+(-2:0),3*n+(-2:0)) - SBasis(:,:,i)*SBasis(:,:,n)';
	end
  end
end

[ disc disc V ] = svd(A');
R = V(:,end-2:end)';

% each row has a norm of 1 but it should be nClus
% so that each rotation has a row with norm 1
R = R*nClus;
R = reshape(R,3,3,nClus);

% then convert those matrices to rotation matrices
for i=1:nClus
  RTmp = rotationMatrix(R(:,:,i));
  % make sure it is a rotation matrix
  if det(RTmp)<0
    if anim.isProj==true
      warning('Problem in finding a rotation matrix');
    else
      RTmp(:,3) = -RTmp(:,3); SBasis(3,:,i) = -SBasis(3,:,i);
	  anim.R(:,3,clus{i}) = -anim.R(:,3,clus{i});
	  anim.R(3,:,clus{i}) = -anim.R(3,:,clus{i});
    end
  end

  % rectify the rotations/translations in anim
  anim.S(:,:,clus{i}) = repmat(RTmp*SBasis(:,:,i), [ 1, 1, length(clus{i})]);
  anim.R(:,:,clus{i}) = multiTimes(anim.R(:,:,clus{i}), RTmp', 1);
end

% Set the first rotation to Id
anim = anim.setFirstRToId();
