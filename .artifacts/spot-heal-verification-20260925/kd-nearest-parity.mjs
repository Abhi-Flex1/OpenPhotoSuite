const O='/tmp/heal-oracle-1/src/engine/compositing/healing-brush.js';
const hb=await import(O);
const R=24, C=4, INF=1e9;
function getError(co,qo,f,be){let e=0;for(let c=C;c<R;c+=4){const d0=f[qo+c]-f[co+c],d1=f[qo+c+1]-f[co+c+1],d2=f[qo+c+2]-f[co+c+2],d3=f[qo+c+3]-f[co+c+3];e+=d0*d0+d1*d1+d2*d2+d3*d3;if(e>=be)return e+1;}return e;}
// faithful: descend to the single leaf reached by the greedy walk, scan only that leaf
function nearestLeaf(i,f,kd,md){const q=i*R,qx=f[q],qy=f[q+1],cut=md*md;let n=0,be=INF;
  while(kd[n]!==99){ if(f[q+kd[n]]<kd[n+1]) n=kd[n+2]; else n=kd[n+3]; }
  const lo=kd[n+1],hi=kd[n+2];let bi=-1;
  for(let c=lo;c<=hi;c++){const co=c*R,dx=f[co]-qx,dy=f[co+1]-qy;
    if(dx*dx+dy*dy<cut)continue;const e=getError(co,q,f,be);if(e<be){be=e;bi=c;}}
  return bi;}
function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};}
let mism=0,tot=0;
for(let trial=0;trial<25;trial++){
  const rnd=mulberry32(trial*7919+3); const n=40+trial*12;
  const f=new Int16Array(n*R);
  for(let i=0;i<n;i++){const o=i*R;f[o]=Math.floor(rnd()*60);f[o+1]=Math.floor(rnd()*60);
    for(let k=2;k<R;k++)f[o+k]=Math.floor((rnd()-0.5)*400);}
  for(const md of [3,5,9]){
    const kd=[]; hb.buildKdTree(0,n-1,kd,f,new Int16Array(2*R));
    for(let i=0;i<n;i++){ tot++; if(nearestLeaf(i,f,kd,md)!==hb.findNearestFeatureInKdTree(i,f,kd,md)) mism++; }
  }
}
console.log(`queries=${tot} mismatches=${mism}`);
