// Min-cut parity against the real upstream computeMinCut.
// The generator mirrors upstream's own caller: a source/sink pair, one aux node
// per hole pixel, and symmetric paired capacities. Degenerate graphs (where
// upstream itself fails to terminate) are excluded and reported.
const mirror = await import('/tmp/mc-mirror.mjs');
const pz = await import('/tmp/heal-oracle-1/src/engine/compositing/posterize.js');

function mulberry32(a) {
  return function () {
    a |= 0; a = a + 0x6D2B79F5 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

const LIMIT = 5000;
let exact = 0, total = 0, skipped = 0;

for (let trial = 0; trial < 30; trial++) {
  const rnd = mulberry32(trial * 2654435761 + 17);
  const holes = 2 + Math.floor(rnd() * 6);
  const labels = 1 + Math.floor(rnd() * 3);
  const source = holes;
  const sink = holes + 1;
  const nodeCount = holes + 2;
  const E = [], C = [];
  // Each hole connects to the source and sink, and to its right/below neighbour.
  for (let h = 0; h < holes; h++) {
    const a = 1 + Math.floor(rnd() * 50), b = 1 + Math.floor(rnd() * 50);
    E.push(h, source, a, a); C.push(a, a);
    E.push(source, h, b, b); C.push(b, b);
    E.push(h, sink, a, a); C.push(a, a);
    E.push(sink, h, b, b); C.push(b, b);
    if (h + 1 < holes) {
      const p = 1 + Math.floor(rnd() * 20);
      E.push(h, h + 1, p, p); C.push(p, p);
    }
  }
  const Ei = Int32Array.from(E), Ci = Float64Array.from(C);
  const ref = pz.computeMinCut(nodeCount, Ei.length, source, sink, Ei, Ci, LIMIT);
  if (ref.flow === undefined || !Number.isFinite(ref.flow)) { skipped++; continue; }
  const mine = mirror.healMinCut(nodeCount, Ei.length, source, sink, Ei, Ci, LIMIT);
  total++;
  const rc = ref.cut ? Array.from(ref.cut).join(',') : 'null';
  const mc = mine.cut ? Array.from(mine.cut).join(',') : 'null';
  if (ref.flow === mine.flow && rc === mc) exact++;
  else if (total <= 5) {
    console.log('DIFF trial', trial, 'holes', holes, '| ref', ref.flow, rc, '| mine', mine.flow, mc);
  }
}
console.log(`mincut parity: ${exact}/${total} exact (${skipped} skipped)`);
