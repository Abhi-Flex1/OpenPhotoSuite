const mirror = await import('/tmp/heal-ets-mirror.mjs');
const hb = await import('/tmp/heal-oracle-1/src/engine/compositing/healing-brush.js');
const cm = await import('/tmp/heal-oracle-1/src/engine/compositing/color-math.js');
const po = await import('/tmp/heal-oracle-1/src/engine/compositing/pixel-ops.js');
const Rect = (await import('/tmp/heal-oracle-1/src/core/math/rect.js')).Rect;

function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};}
function makeImage(W,H,seed,kind){
  const rnd=mulberry32(seed); const rgba=new Uint8Array(W*H*4);
  for(let y=0;y<H;y++)for(let x=0;x<W;x++){const o=(y*W+x)<<2;
    let base,noise;
    if(kind==='flat'){base=120;noise=(rnd()-0.5)*3;}
    else {base=100+40*Math.sin(x*0.31)+30*Math.cos(y*0.27)+20*Math.sin((x+y)*0.13);noise=(rnd()-0.5)*12;}
    rgba[o]=Math.max(0,Math.min(255,base+noise));
    rgba[o+1]=Math.max(0,Math.min(255,base*0.9+noise));
    rgba[o+2]=Math.max(0,Math.min(255,base*0.8+noise));
    rgba[o+3]=255;}
  const cx=W>>1,cy=H>>1,r=4;
  for(let y=cy-r;y<=cy+r;y++)for(let x=cx-r;x<=cx+r;x++){
    if(x<0||y<0||x>=W||y>=H)continue; if(Math.hypot(x-cx,y-cy)>r)continue;
    const o=(y*W+x)<<2; rgba[o]=200;rgba[o+1]=40;rgba[o+2]=40;rgba[o+3]=255;}
  return rgba;
}
function makeMask(W,H){const m=new Uint8Array(W*H);const cx=W>>1,cy=H>>1,r=4;
  for(let y=cy-r;y<=cy+r;y++)for(let x=cx-r;x<=cx+r;x++){
    if(x<0||y<0||x>=W||y>=H)continue; if(Math.hypot(x-cx,y-cy)>r)continue; m[y*W+x]=255;}
  return m;}

// Faithful transcription of upstream's stage, using upstream's own helpers,
// to produce the reference voted offset.
function upstreamVotedOffset(srcRgba, srcRect, maskChannel){
  const fillRect=new Rect(0,0,srcRect.width,srcRect.height);
  let maskBuffer=new Uint8Array(srcRect.area());
  po.copyChannel(maskChannel, fillRect, maskBuffer, srcRect);
  po.round(maskBuffer);
  const downsampleFactor = (()=>{let f=1;while((srcRect.width+srcRect.height)/2/f>400)f++;return f;})();
  const fullResMask=maskBuffer;
  const dsW=Math.floor(srcRect.width/downsampleFactor), dsH=Math.floor(srcRect.height/downsampleFactor);
  let dsRgba=new Uint8Array(dsW*dsH*4);
  po.resampleUint32UniformScale(srcRgba,srcRect.width,srcRect.height,dsRgba,dsW,dsH,1/downsampleFactor);
  let dsMask=new Uint8Array(dsW*dsH);
  po.resampleUint8UniformScale(maskBuffer,srcRect.width,srcRect.height,dsMask,dsW,dsH,1/downsampleFactor);
  po.round(dsMask,1);
  const cb=po.contentBoundsChannel(dsMask,new Rect(0,0,dsW,dsH));
  if(cb.isEmpty()) return null;
  const minDistSq=Math.round((cb.width+cb.height)/2/15);
  const ycbcr=new Int16Array(dsW*dsH*4);
  cm.rgbaToYcbcr(dsRgba,ycbcr);
  // extract features via upstream exported pieces
  const FB=24,FC=4,PH=3,AM=200;
  const recs=[];
  for(let row=PH;row<dsH-4;row++)for(let col=PH;col<dsW-4;col++){
    const px=row*dsW+col; if(dsMask[px]==255) continue;
    const y=new Int16Array(64),cbk=new Int16Array(64),crk=new Int16Array(64);
    if(hb.samplePatchFwhtBlock(ycbcr,dsMask,col,row,dsW,dsH,y,cbk,crk)!==0) continue;
    const s=new Int16Array(64);
    const rec=new Int16Array(FB); rec[0]=col; rec[1]=row;
    hb.fwht64InPlace(y,s); for(let i=0;i<12;i++) rec[4+i]=y[i];
    hb.fwht64InPlace(cbk,s); for(let i=0;i<4;i++) rec[16+i]=cbk[i];
    hb.fwht64InPlace(crk,s); for(let i=0;i<4;i++) rec[20+i]=crk[i];
    const a5=rec[5],a6=rec[6]; rec[5]=rec[20]; rec[6]=rec[16]; rec[16]=a6; rec[20]=a5;
    recs.push(rec);
  }
  if(!recs.length) return null;
  const fb=new Int16Array(recs.length*FB);
  for(let i=0;i<recs.length;i++) fb.set(recs[i],i*FB);
  const kd=[]; hb.buildKdTree(0,recs.length-1,kd,fb,new Int16Array(2*FB));
  const hist=new Float32Array(dsW*dsH*4);
  for(let i=0;i<recs.length;i++){
    const ni=hb.findNearestFeatureInKdTree(i,fb,kd,minDistSq);
    if(ni===-1) continue;
    hist[(dsH+(fb[ni*FB+1]-fb[i*FB+1]))*2*dsW+(dsW+(fb[ni*FB]-fb[i*FB]))]+=1;
  }
  const votes=[];
  for(let vi=0;vi<hist.length;vi++) if(hist[vi]>0){
    const row=Math.floor(vi/(2*dsW)); const col=vi-row*2*dsW;
    votes.push({x:col-dsW,y:row-dsH,c:hist[vi]});
  }
  votes.sort((a,b)=>b.c-a.c);
  if(!votes.length) return null;
  return votes[0];
}

let ok=0, bad=0;
for(const [W,H,seed,kind] of [
  [24,24,1,'tex'],[32,28,7,'tex'],[40,40,13,'tex'],[48,36,29,'tex'],
  [64,64,5,'tex'],[30,30,3,'flat'],[80,60,11,'tex'],[24,24,2,'flat'],
  [120,90,17,'tex'],[36,36,9,'tex'],[28,32,4,'tex'],[50,50,21,'tex']]) {
  const rgba=makeImage(W,H,seed,kind), mask=makeMask(W,H);
  const ref=upstreamVotedOffset(rgba,new Rect(0,0,W,H),mask);
  const mine=mirror.healVotedOffset(rgba,mask,W,H);
  const refStr=ref?`${ref.x},${ref.y},${ref.c}`:'none';
  const mineStr=`${mine.x},${mine.y},${mine.votes}`;
  const same = (ref? ref.x===mine.x && ref.y===mine.y && ref.c===mine.votes : mine.votes===0);
  console.log(`${W}x${H} ${kind}: ref=${refStr} mine=${mineStr} ${same?'OK':'MISMATCH'}`);
  same?ok++:bad++;
}
console.log(`\nE2E parity: ${ok} ok, ${bad} mismatched`);
