const hb=await import('/tmp/heal-oracle-1/src/engine/compositing/healing-brush.js');
function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296;};}
// Standard separable 2D 8x8 FWHT, unnormalized, natural coefficient order.
function fwht2d8(buf){
  const t=new Float64Array(8);
  for(let r=0;r<8;r++){ const o=r*8;
    for(let i=0;i<8;i++) t[i]=buf[o+i];
    for(let len=1;len<8;len<<=1) for(let i=0;i<8;i+=len<<1) for(let k=0;k<len;k++){
      const a=t[i+k],b=t[i+k+len]; t[i+k]=a+b; t[i+k+len]=a-b; }
    for(let i=0;i<8;i++) buf[o+i]=t[i];
  }
  for(let c=0;c<8;c++){ for(let i=0;i<8;i++) t[i]=buf[i*8+c];
    for(let len=1;len<8;len<<=1) for(let i=0;i<8;i+=len<<1) for(let k=0;k<len;k++){
      const a=t[i+k],b=t[i+k+len]; t[i+k]=a+b; t[i+k+len]=a-b; }
    for(let i=0;i<8;i++) buf[i*8+c]=t[i];
  }
}
let bad=0, badInt=0;
for(let trial=0;trial<600;trial++){
  const rnd=mulberry32(trial*104729+7);
  const src=new Float64Array(64);
  for(let i=0;i<64;i++) src[i]=Math.floor((rnd()-0.5)*2000);
  const a=Float64Array.from(src); const b=Float64Array.from(src);
  fwht2d8(a);
  hb.fwht64InPlace(b,new Float64Array(64));
  for(let i=0;i<16;i++) if(a[i]!==b[i]){bad++;if(bad<4)console.log('float mismatch t',trial,'i',i,a[i],b[i]);break;}
  // Int16 path (what upstream actually uses): values wrap at 16 bits.
  const ia=Int16Array.from({length:64},(_,i)=>src[i]);
  const ref=Int16Array.from(ia); hb.fwht64InPlace(ref,new Int16Array(64));
  const m=Float64Array.from(ia); fwht2d8(m);
  for(let i=0;i<16;i++){ let v=Math.trunc(m[i])%65536; if(v<0)v+=65536; let s=v>32767?v-65536:v; if(s!==ref[i]){badInt++;if(badInt<4)console.log('int16 mismatch t',trial,'i',i,s,ref[i]);break;} }
}
console.log('first-16 float mismatches:',bad);
console.log('first-16 int16 mismatches:',badInt);
