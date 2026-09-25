# Spot Healing port verification (2026-09-25)

The healing core in `entry/src/main/ets/model/EditorMath.ets` is a port of upstream's
`src/engine/compositing/healing-brush.js` in the PhotoSuite reference tree.

## How this was verified

Upstream ships as plain ESM without `"type": "module"`, so it cannot be imported
directly. `/tmp/heal-oracle-1` is a copy of upstream's `src/` with an added
`package.json` marker that makes the real upstream module loadable in Node. Every
number below comes from running that real module, not from a hand transcription.

    node --input-type=module -e "import('/tmp/heal-oracle-1/src/engine/compositing/healing-brush.js')"

## Results

| Check | Result |
| --- | --- |
| FWHT first 16 coefficients vs upstream, 600 fuzz trials (float + Int16 wraparound) | 0 mismatches |
| Feature extraction vs upstream over 5 image sizes (up to 3,025 patches) | bit-identical |
| KD nearest-neighbour query vs upstream, 13,800 queries | 0 mismatches |
| Voted offset vs upstream, 12 scenes | 12/12 exact, including vote counts |
| Randomised sweep, 60 scenes, healed pixels vs `runHealingBrushFill` | 0 worse, 59/60 identical outcome |
| ArkTS production build | BUILD SUCCESSFUL |
| ArkTS ohosTest build | BUILD SUCCESSFUL |
| Device suite on PC emulator (127.0.0.1:5555) | 55/55 pass, 0 failures |

## Two findings worth keeping

**The transform is only half a standard 8x8 FWHT.** Upstream's hand-unrolled
`fwht64InPlace` reorders coefficients 16 and above. The healing descriptor only
reads the first 16 (12 luma + 4 Cb + 4 Cr), which are bit-identical to the plain
separable 8x8 transform. `fwht64` therefore uses the readable form.

**Upstream's KD search is approximate on purpose.** `findNearestFeatureInKdTree`
descends greedily to one leaf and never backtracks, so it is not a true nearest
neighbour. A flat exact scan disagrees with upstream on 10,081 of 13,800 queries
and is always the "better" match. Reproducing the tree keeps the port
behaviourally identical instead of quietly solving a different problem.

## What is deliberately not ported

Upstream finishes the fill with a graph-cut label optimisation and a Poisson
blend. Those are separate stages that refine the vote; the vote is their seed.
`healPatchPlan` therefore returns the diverse patch set and per-pixel labels, and
`applyHealPlan` performs upstream's `pasteLabeledPatches`. Healed pixels are not
byte-identical to upstream (2/49 on the reference scene) because upstream smooths
after pasting, but the blemish is fully removed in both.

## Re-running

    python3 transpile-heal-to-js.py            # strips ArkTS types into a JS mirror
    node fwht-coefficient-parity.mjs
    node kd-nearest-parity.mjs
    node parity-voted-offset.mjs
    node parity-randomised-sweep.mjs

The device suite:

    hvigorw --mode module -p product=test -p module=entry@ohosTest \
      -p buildMode=debug onDeviceTest

Note: `GenerateDeviceCoverage` fails to parse its own coverage JSON
(`ErrorCode 00507008`) but this does not affect the run. To read results
directly:

    hdc -t 127.0.0.1:5555 shell aa test -b com.openphotosuite.editor \
      -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 120000

## UI wiring (2026-09-25, second slice)

The verified algorithm was unreachable: `EditorTool.SPOT_HEAL` had an icon and an
enum but no rail button, no `PaintMode`, and no layer path. It is now wired end to end.

| File | Change |
| --- | --- |
| `EditorTypes.ets` | `PaintMode.SPOT_HEAL` |
| `EditorStore.ets` | `addSpotHealLayer`, strength editing, 'Heal flow' label |
| `ImageFileService.ets` | `createSpotHealSurface` + both compositor dispatch sites |
| `Index.ets` | rail button (J), tool/paint-mode predicates, touch gate, properties panel |

### Channel order

`createSpotHealSurface` initially swizzled the reference buffer as if it were
BGRA. That is wrong: the PixelMaps are `RGBA_8888`, and `createCloneSurface`
copies channels straight through. Healing now does the same, so the planner's
RGB working space matches the source directly. The regression test
`heals without swapping colour channels` locks this in.

### Runtime evidence

- Rail: `tool-j` present in `runtime-editor-layout.json` (25 tools, was 24).
- Panel: `spot-heal-size-slider`, `spot-heal-flow-slider`, `spot-heal-opacity-slider`
  and the `SPOT HEALING` / `Content aware` labels in `runtime-spot-heal-panel.json`.
- Device suite: 58/58 pass on 127.0.0.1:5555.

### Not verified on device

A real stroke over a real photo. The emulated storage exposes no image files and
HDC cannot write to the user-visible picker directories, so the image could not be
opened through the picker. The heal surface's pixel logic is covered by the
algorithm parity sweep and the unit tests, but the interactive stroke path
remains unexercised end to end.

## A shared filter bug found by the compositor test (2026-09-25)

Adding a device test that drives the real `renderPreviewPixelMap` exposed a
defect that had nothing to do with healing and affected **every** paint mode.

`getFilterPresetMatrix` blended each preset toward the wrong identity matrix:

    // before
    const identity = index === 4 || index === 9 || index === 14 ? 0
      : index === 19 ? 1 : index % 5 === 4 ? 0 : 1;
    // => [1,1,1,1,0, 1,1,1,1,0, 1,1,1,1,0, 1,1,1,1,1]   (wrong)

    // after
    const identity = index % 5 === 4 ? 0
      : (index === 0 || index === 6 || index === 12 || index === 18) ? 1 : 0;
    // => [1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0]   (true identity)

The old version set every off-diagonal weight to 1, so the kernel summed all
three channels. Any pixel that was not pure grey saturated to white *before any
paint layer ran* — a neutral document rendered as a white image. Measured on
device: a source pixel of `25,25,215` came out of `applyRgbaFilter` as
`255,255,255`.

Locked in by `blends filter presets from a true identity matrix`, and by the
compositor test's pass-through assertion that neutral adjustments leave pixels
untouched.

## PixelMap channel order, measured not assumed

`createPixelMap(buffer)` and `readPixelsToBuffer(buffer)` do **not** share a
channel order. Measured on device with a known asymmetric colour:

- wrote `215,25,25` into `createPixelMap`, read back `25,25,215`
  → `readPixelsToBuffer` returns **BGRA**
- a surface buffer written RGB and composited through `Canvas` reads back **BGRA**

`createSpotHealSurface` therefore swaps the outer channels when reading the
reference (BGRA → RGB for the patch match) and writes them straight back. Getting
this wrong is invisible in unit tests and only shows up against a real PixelMap.

## Retouch family compositor coverage, and a correction (2026-09-25)

`composites every retouch mode through the real preview pipeline` now drives
blur, sharpen, smudge, sponge, dodge, burn, red eye, clone, fill and brush
through `renderPreviewPixelMap` on a real PixelMap, asserting each one paints and
that pixels far from the stroke survive unchanged. Device suite: 61/61.

### Correction to the note above

This test first reported a red/blue swap in blur and I "fixed" the read order in
six surfaces and three helpers. **That fix was wrong.** The suite passed both
before and after the change, which means the test never actually distinguished
the two: the failing assertion compared a BGRA read-back against an RGB-ordered
input.

All eight edits were reverted and the suite re-run green, confirming the
original code was correct. The lesson is the one that matters for the rest of
this port: a change that does not make a failing test pass was not a fix. I
should have run that experiment before editing rather than after.

What the test does establish, on device and against real PixelMaps:

- every retouch mode composites without error
- every retouch mode visibly paints inside the stroke
- pixels outside the stroke bounds are byte-identical to the source
- the healed pixel keeps the background's channel ordering

Two modes legitimately leave the centre red and are excluded from the colour
check, because they resample neighbours that are themselves inside the red block:
smudge (single-point strokes sample +x) and sponge (saturation of an already-saturated
red stays red).

## Interactive stroke verified on device (2026-09-25)

The app bundles `sample_beach.jpg`, which loads on start. That makes a real
interactive stroke possible without the picker, closing the gap flagged earlier.

- Selected Spot Healing (J) from the rail; the properties panel appeared with
  Size / Flow / Opacity sliders.
- Dragged across the canvas; a **Spot Healing** paint layer was created in the
  Layers panel, and undo removed it and redo restored it.
- Compared screenshots before/after: **64,735 pixels changed inside the
  artboard**, 1,076 inside the stroke region with a max channel delta of 106 —
  real texture replacement, not a no-op. On a smooth beach photo with no actual
  blemish the visual change is subtle by design.

Screenshots: `interactive-stroke-with-heal.png`, `interactive-stroke-undone.png`,
`interactive-stroke-crop.png`.

## Poisson blend ported (2026-09-25)

Upstream finishes a heal with a graph-cut label optimisation followed by a
Poisson solve that removes the pasted edge. The graph cut is ~500 lines; the
Poisson half is self-contained and is ported here.

`healPoissonBlend` follows upstream's `solvePoissonFill`: the fill region is
solved for, surrounding opaque pixels form the Dirichlet boundary, interior
neighbours contribute the gradient term, and the system is relaxed with SOR over
three interleaved channels (`HealSparseMatrix` holds the CSR layout with the
diagonal split out, as upstream's solver expects).

Verified against the real upstream module:

| Check | Result |
| --- | --- |
| Step-edge fixture, row y=16 | exact match with upstream's output |
| Byte parity on that fixture | 9 of 4096 bytes differ by 1 (SOR rounding) |
| Randomised fuzz, 25 scenes incl. transparent pixels | 20 bit-identical, worst delta 1 |

Wired into `createSpotHealSurface` between the paste and the composite, matching
upstream's ordering. Device suite: 62/62.

The graph-cut label optimisation is still not ported: the per-pixel labels come
from the patch plan alone rather than being refined by a min-cut.
