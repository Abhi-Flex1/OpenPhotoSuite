const mirror = await import('/tmp/poisson-mirror.mjs');
const caf = await import('/tmp/heal-oracle-1/src/engine/compositing/content-aware-fill.js');
function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};}
let worst=0, trials=0, exact=0;
for(let trial=0;trial<25;trial++){
  const rnd=mulberry32(trial*7919+5);
  const W=16+ (trial%4)*8, H=16+ (trial%3)*8;
  const px=new Uint8Array(W*H*4), region=new Uint8Array(W*H);
  for(let y=0;y<H;y++)for(let x=0;x<W;x++){
    const o=(y*W+x)<<2;
    px[o]=Math.floor(rnd()*256); px[o+1]=Math.floor(rnd()*256);
    px[o+2]=Math.floor(rnd()*256); px[o+3]=(trial%7===0 && rnd()<0.1)?0:255;
  }
  // random blob region
  const cx=Math.floor(rnd()*W), cy=Math.floor(rnd()*H), r=1+Math.floor(rnd()*4);
  for(let y=cy-r;y<=cy+r;y++)for(let x=cx-r;x<=cx+r;x++){
    if(x<0||y<0||x>=W||y>=H)continue;
    if(Math.hypot(x-cx,y-cy)<=r) region[y*W+x]=1;
  }
  let holes=0; for(const v of region) if(v) holes++;
  if(holes===0) continue;
  const a=new Uint8Array(px), b=new Uint8Array(px);
  caf.solvePoissonFill(a, region, {width:W,height:H}, null, 1000);
  mirror.healPoissonBlend(b, region, W, H, 1000);
  let diffs=0, maxd=0;
  for(let i=0;i<b.length;i++){const d=Math.abs(a[i]-b[i]); if(d>0){diffs++; maxd=Math.max(maxd,d);}}
  trials++;
  if(diffs===0) exact++;
  worst=Math.max(worst,maxd);
  if(maxd>3) console.log('trial',trial,W+'x'+H,'maxd',maxd,'diffs',diffs);
}
console.log(`poisson fuzz: ${trials} trials, ${exact} bit-identical, worst delta ${worst}`);
