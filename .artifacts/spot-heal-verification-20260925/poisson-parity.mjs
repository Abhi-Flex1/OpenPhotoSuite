const mirror = await import('/tmp/poisson-mirror.mjs');
const expected = JSON.parse((await import('node:fs')).readFileSync('/tmp/poisson-vectors.json','utf8'));
const W=32,H=32;
const px=new Uint8Array(W*H*4);
for(let y=0;y<H;y++)for(let x=0;x<W;x++){const o=(y*W+x)<<2;const v=x<16?60:200;px[o]=v;px[o+1]=v;px[o+2]=v;px[o+3]=255;}
const region=new Uint8Array(W*H);
for(let y=8;y<24;y++)for(let x=8;x<24;x++) region[y*W+x]=1;
for(let y=8;y<24;y++)for(let x=8;x<24;x++){const o=(y*W+x)<<2;px[o]=130;px[o+1]=130;px[o+2]=130;}
mirror.healPoissonBlend(px, region, W, H, 1000);
const row=[]; for(let x=6;x<26;x++) row.push(px[((16*W+x)<<2)]);
console.log('upstream:', expected.row.join(','));
console.log('mine    :', row.join(','));
let maxDiff=0, diffs=0;
for(let i=0;i<expected.full.length;i++){ const d=Math.abs(expected.full[i]-px[i]); if(d>0){diffs++; maxDiff=Math.max(maxDiff,d);} }
console.log('byte diffs:',diffs,'max delta:',maxDiff);
