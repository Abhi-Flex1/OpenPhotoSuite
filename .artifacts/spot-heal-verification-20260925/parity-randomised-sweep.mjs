const mirror = await import('/tmp/heal-ets-mirror.mjs');
const hb = await import('/tmp/heal-oracle-1/src/engine/compositing/healing-brush.js');
const Rect = (await import('/tmp/heal-oracle-1/src/core/math/rect.js')).Rect;
function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};}
function scene(W,H,seed,kind,blemishR){
  const rnd=mulberry32(seed); const rgba=new Uint8Array(W*H*4);
  for(let y=0;y<H;y++)for(let x=0;x<W;x++){const o=(y*W+x)<<2;
    let base,noise;
    if(kind==='flat'){base=120;noise=(rnd()-0.5)*3;}
    else if(kind==='grad'){base=40+180*(x+y)/(W+H);noise=(rnd()-0.5)*6;}
    else {base=100+40*Math.sin(x*0.31)+30*Math.cos(y*0.27)+20*Math.sin((x+y)*0.13);noise=(rnd()-0.5)*12;}
    rgba[o]=Math.max(0,Math.min(255,base+noise));
    rgba[o+1]=Math.max(0,Math.min(255,base*0.9+noise));
    rgba[o+2]=Math.max(0,Math.min(255,base*0.8+noise));
    rgba[o+3]=255;}
  const mask=new Uint8Array(W*H);
  const cx=3+Math.floor(rnd()*(W-6)), cy=3+Math.floor(rnd()*(H-6)), r=blemishR;
  for(let y=cy-r;y<=cy+r;y++)for(let x=cx-r;x<=cx+r;x++){
    if(x<0||y<0||x>=W||y>=H)continue; if(Math.hypot(x-cx,y-cy)>r)continue;
    mask[y*W+x]=255; const o=(y*W+x)<<2; rgba[o]=200;rgba[o+1]=40;rgba[o+2]=40;rgba[o+3]=255;}
  return {rgba,mask,cx,cy};
}
function red(buf,mask,W,H){let n=0,t=0;for(let y=0;y<H;y++)for(let x=0;x<W;x++){if(!mask[y*W+x])continue;t++;const o=(y*W+x)<<2;if(buf[o]>150&&buf[o+1]<95)n++;}return {red:n,tot:t};}
let agree=0,better=0,worse=0,both0=0,total=0;
const kinds=['tex','flat','grad'];
for(let i=0;i<60;i++){
  const W=20+ (i*7)%70, H=20+(i*11)%60;
  const kind=kinds[i%3], r=[2,3,4,5][i%4];
  const {rgba,mask}=scene(W,H,i*13+1,kind,r);
  if(!mask.some(v=>v>0)) continue;
  const dst=new Uint8Array(rgba.length); dst.set(rgba);
  let rc; try{ rc=hb.runHealingBrushFill(rgba,new Rect(0,0,W,H),mask,dst,new Rect(0,0,W,H)); }catch(e){ continue; }
  const rRes=red(dst,mask,W,H);
  const plan=mirror.healPatchPlan(rgba,mask,W,H);
  let mRes=red(rgba,mask,W,H);
  if(plan&&plan.patches.length>0){ mRes=red(mirror.applyHealPlan(plan,rgba,mask,W,H),mask,W,H); }
  total++;
  if(mRes.red<rRes.red) better++;
  else if(mRes.red>rRes.red) worse++;
  else agree++;
  if(rRes.red===0&&mRes.red===0) both0++;
  if(worse>0) console.log(`WORSE case ${i} ${W}x${H} ${kind} r=${r}: upstream=${rRes.red} mine=${mRes.red} rc=${rc}`);
}
console.log(`\ntotal=${total} better=${better} equal=${agree} worse=${worse} bothPerfect=${both0}`);
