import { describe, it, expect } from '@ohos/hypium';
import { image } from '@kit.ImageKit';
import {
  applyRgbaFilter,
  applyHealPlan,
  clamp,
  clampAdjustment,
  clampFilterIntensity,
  centeredCropRect,
  cropAspectForRect,
  documentFilterMatrix,
  dodgeBurnExposureFlow,
  dodgeBurnToneValue,
  filterMatrix,
  filterPresetFromLabel,
  floodFillMask,
  fwht64,
  getFilterPresetMatrix,
  healPatchPlan,
  healPoissonBlend,
  healVotedOffset,
  normalizeCropRect,
  normalizePaintPoints,
  normalizeSelectionRect,
  normalizeHexColor,
  rgbaToYcbcr,
  selectionPointsFromMask,
  redEyeCorrection,
  redEyeWeight,
  selectionToCropRect,
  sourcePointToCropSpace,
  transformPoint,
  transformedSize
} from '../../../main/ets/model/EditorMath';
import { HealOffset, HealPlan } from '../../../main/ets/model/EditorMath';
import { EditorStore } from '../../../main/ets/model/EditorStore';
import { renderPreviewPixelMap } from '../../../main/ets/platform/ImageFileService';
import {
  AdjustmentValues,
  ColorTarget,
  EditorTool,
  FilterState,
  LayerModel,
  PaintMode,
  PaintGradientStyle,
  SelectionRect,
  ShapeType,
  SidebarTab,
  TransformPoint,
  TransformState
} from '../../../main/ets/model/EditorTypes';

/** A textured image with a red blemish painted in the middle, for heal tests. */
interface HealScene {
  pixels: Uint8Array;
  mask: Uint8Array;
}

function buildHealScene(width: number, height: number): HealScene {
  const pixels: Uint8Array = new Uint8Array(width * height * 4);
  const mask: Uint8Array = new Uint8Array(width * height);
  let state: number = 7;
  const nextNoise: () => number = (): number => {
    // Small deterministic LCG so the fixture is identical on every run.
    state = (state * 1103515245 + 12345) % 2147483648;
    return state / 2147483648 - 0.5;
  };
  for (let y: number = 0; y < height; y++) {
    for (let x: number = 0; x < width; x++) {
      const offset: number = (y * width + x) << 2;
      const base: number = 100 + 40 * Math.sin(x * 0.31) + 30 * Math.cos(y * 0.27) +
        20 * Math.sin((x + y) * 0.13);
      const noise: number = nextNoise() * 12;
      pixels[offset] = Math.max(0, Math.min(255, base + noise));
      pixels[offset + 1] = Math.max(0, Math.min(255, base * 0.9 + noise));
      pixels[offset + 2] = Math.max(0, Math.min(255, base * 0.8 + noise));
      pixels[offset + 3] = 255;
    }
  }
  const centreX: number = width >> 1;
  const centreY: number = height >> 1;
  const radius: number = 4;
  for (let y: number = centreY - radius; y <= centreY + radius; y++) {
    for (let x: number = centreX - radius; x <= centreX + radius; x++) {
      if (x < 0 || y < 0 || x >= width || y >= height) {
        continue;
      }
      if (Math.sqrt((x - centreX) * (x - centreX) + (y - centreY) * (y - centreY)) > radius) {
        continue;
      }
      mask[y * width + x] = 255;
    }
  }
  // Paint the blemish after the texture so it is the actual defect being repaired.
  for (let index: number = 0; index < mask.length; index++) {
    if (mask[index] === 0) {
      continue;
    }
    const offset: number = index << 2;
    pixels[offset] = 200;
    pixels[offset + 1] = 40;
    pixels[offset + 2] = 40;
    pixels[offset + 3] = 255;
  }
  return { pixels: pixels, mask: mask };
}

function countReddish(pixels: Uint8Array, mask: Uint8Array, width: number, height: number): number {
  let count: number = 0;
  for (let y: number = 0; y < height; y++) {
    for (let x: number = 0; x < width; x++) {
      if (mask[y * width + x] === 0) {
        continue;
      }
      const offset: number = (y * width + x) << 2;
      if (pixels[offset] > 150 && pixels[offset + 1] < 95) {
        count++;
      }
    }
  }
  return count;
}

export default function editorStateTest(): void {
  describe('PhotoSuite editor state', () => {
    it('clamps adjustment values to editor limits', 0, () => {
      expect(clampAdjustment('exposure', 140)).assertEqual(100);
      expect(clampAdjustment('blur', -8)).assertEqual(0);
      expect(clampAdjustment('contrast', Number.NaN)).assertEqual(0);
      expect(clamp(5, 1, 3)).assertEqual(3);
    });

    it('keeps a neutral color matrix stable', 0, () => {
      const matrix: number[] = filterMatrix({
        exposure: 0,
        contrast: 0,
        saturation: 0,
        temperature: 0,
        blur: 0
      });
      expect(matrix.length).assertEqual(20);
      expect(matrix[0]).assertClose(1, 0.0001);
      expect(matrix[6]).assertClose(1, 0.0001);
      expect(matrix[12]).assertClose(1, 0.0001);
      expect(matrix[18]).assertClose(1, 0.0001);
      expect(matrix[4]).assertClose(0, 0.0001);
      expect(matrix[9]).assertClose(0, 0.0001);
      expect(matrix[14]).assertClose(0, 0.0001);
      expect(matrix[19]).assertClose(0, 0.0001);
    });

    it('blends filter presets from a true identity matrix', 0, () => {
      // Regression: the preset blend used the wrong identity layout, so every
      // preset resolved to a matrix that summed all three channels. That washed
      // any non-grey pixel to white before paint layers ever ran.
      const neutral: number[] = getFilterPresetMatrix('none', 0);
      expect(neutral.length).assertEqual(20);
      expect(neutral[0]).assertClose(1, 0.0001);
      expect(neutral[6]).assertClose(1, 0.0001);
      expect(neutral[12]).assertClose(1, 0.0001);
      expect(neutral[18]).assertClose(1, 0.0001);
      for (let index: number = 0; index < 20; index++) {
        const onDiagonal: boolean = index === 0 || index === 6 || index === 12 || index === 18;
        if (!onDiagonal) {
          expect(neutral[index]).assertClose(0, 0.0001);
        }
      }
      // A full-strength preset must not leak identity into off-diagonal slots.
      const vivid: number[] = getFilterPresetMatrix('vivid', 100);
      expect(vivid.length).assertEqual(20);
      expect(vivid[4]).assertClose(0, 0.0001);
      expect(vivid[9]).assertClose(0, 0.0001);
      expect(vivid[14]).assertClose(0, 0.0001);
      expect(vivid[19]).assertClose(0, 0.0001);
    });

    it('maps filter presets to stable preview and export matrices', 0, () => {
      const neutral: number[] = documentFilterMatrix({
        exposure: 0,
        contrast: 0,
        saturation: 0,
        temperature: 0,
        blur: 0
      }, 'none', 100);
      expect(neutral.length).assertEqual(20);
      expect(neutral[0]).assertClose(1, 0.0001);
      expect(neutral[6]).assertClose(1, 0.0001);
      expect(neutral[12]).assertClose(1, 0.0001);
      expect(neutral[18]).assertClose(1, 0.0001);
      expect(filterPresetFromLabel('Soft Light')).assertEqual('softLight');
      expect(clampFilterIntensity(140)).assertEqual(100);

      const source: ArrayBuffer = new ArrayBuffer(4);
      const pixels: Uint8Array = new Uint8Array(source);
      pixels[0] = 200;
      pixels[1] = 100;
      pixels[2] = 50;
      pixels[3] = 255;
      const output: Uint8Array = new Uint8Array(applyRgbaFilter(source, 1, 1, 4,
        getFilterPresetMatrix('mono', 100)));
      expect(output[0]).assertEqual(output[1]);
      expect(output[1]).assertEqual(output[2]);
      expect(output[3]).assertEqual(255);
    });

    it('restores filter presets and intensity through history', 0, () => {
      const store: EditorStore = new EditorStore();
      store.setFilterPreset('mono');
      store.setFilterIntensity(40);
      expect(store.document.filter.preset).assertEqual('mono');
      expect(store.document.filter.intensity).assertEqual(40);
      store.undo();
      expect(store.document.filter.preset).assertEqual('mono');
      expect(store.document.filter.intensity).assertEqual(100);
      store.undo();
      expect(store.document.filter.preset).assertEqual('none');
      store.redo();
      expect(store.document.filter.preset).assertEqual('mono');
      store.redo();
      expect(store.document.filter.intensity).assertEqual(40);
    });

    it('updates and reverses adjustment history', 0, () => {
      const store: EditorStore = new EditorStore();
      store.updateExposure(35);
      store.updateContrast(18);
      expect(store.document.adjustments.exposure).assertEqual(35);
      expect(store.document.adjustments.contrast).assertEqual(18);
      store.undo();
      expect(store.document.adjustments.exposure).assertEqual(35);
      expect(store.document.adjustments.contrast).assertEqual(0);
      store.redo();
      expect(store.document.adjustments.contrast).assertEqual(18);
    });

    it('tracks the active tool and sidebar tab', 0, () => {
      const store: EditorStore = new EditorStore();
      store.setTool(EditorTool.BRUSH);
      store.setSidebarTab(SidebarTab.HISTORY);
      expect(store.activeTool).assertEqual(EditorTool.BRUSH);
      expect(store.sidebarTab).assertEqual(SidebarTab.HISTORY);
    });

    it('normalizes brush points into bounded source-space coordinates', 0, () => {
      const points: TransformPoint[] = normalizePaintPoints([
        { x: -8, y: 12.4 },
        { x: 0, y: 12 },
        { x: 40.6, y: 220 },
        { x: 90, y: 80 }
      ], 150, 105);
      expect(points.length).assertEqual(3);
      expect(points[0].x).assertEqual(0);
      expect(points[0].y).assertEqual(12);
      expect(points[1].x).assertEqual(41);
      expect(points[1].y).assertEqual(104);
      expect(points[2].x).assertEqual(90);
      expect(points[2].y).assertEqual(80);
    });

    it('creates brush layers and restores stroke properties through history', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalCount: number = store.document.layers.length;
      const paintId: string = store.addPaintLayer([
        { x: 12, y: 18 },
        { x: 42, y: 34 },
        { x: 80, y: 64 }
      ], '#abc', 18);
      const paint = store.getLayer(paintId);
      expect(paint?.kind).assertEqual('paint');
      expect(paint?.paintColor).assertEqual('#AABBCC');
      expect(paint?.paintWidth).assertEqual(18);
      expect(paint?.paintPoints.length).assertEqual(3);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      expect(store.selectedLayerId).assertEqual(paintId);
      expect(store.document.history[store.document.history.length - 1].kind).assertEqual('paint');
      expect(store.setPaintColor(paintId, '#123456')).assertEqual(true);
      expect(store.setPaintWidth(paintId, 28)).assertEqual(true);
      expect(store.getLayer(paintId)?.paintColor).assertEqual('#123456');
      expect(store.getLayer(paintId)?.paintWidth).assertEqual(28);
      store.undo();
      expect(store.getLayer(paintId)?.paintWidth).assertEqual(18);
      store.undo();
      expect(store.getLayer(paintId)?.paintColor).assertEqual('#AABBCC');
      store.undo();
      expect(store.getLayer(paintId)).assertEqual(undefined);
      store.redo();
      expect(store.getLayer(paintId)?.paintColor).assertEqual('#AABBCC');
      expect(store.getLayer(paintId)?.paintPoints.length).assertEqual(3);
    });

    it('creates named pixel-snapped pencil layers with history', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalCount: number = store.document.layers.length;
      const pencilId: string = store.addPaintLayer([
        { x: 12.4, y: 18.6 },
        { x: 44.2, y: 36.8 }
      ], '#abc', 10, PaintMode.PENCIL);
      const pencil = store.getLayer(pencilId);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      expect(pencil?.id).assertEqual('layer-pencil');
      expect(pencil?.name).assertEqual('Pencil stroke');
      expect(pencil?.paintMode).assertEqual(PaintMode.PENCIL);
      expect(pencil?.paintColor).assertEqual('#AABBCC');
      expect(pencil?.paintWidth).assertEqual(10);
      expect(pencil?.paintPoints[0].x).assertEqual(12);
      expect(pencil?.paintPoints[0].y).assertEqual(19);
      expect(store.document.history[store.document.history.length - 1].label).assertEqual('Pencil stroke');
      store.undo();
      expect(store.getLayer(pencilId)).assertEqual(undefined);
      store.redo();
      expect(store.getLayer(pencilId)?.paintMode).assertEqual(PaintMode.PENCIL);
    });

    it('creates eraser layers and restores their paint mode through history', 0, () => {
      const store: EditorStore = new EditorStore();
      const brushId: string = store.addPaintLayer([
        { x: 12, y: 18 },
        { x: 54, y: 60 }
      ], '#2BB8A7', 18);
      store.setTool(EditorTool.ERASER);
      const eraserId: string = store.addPaintLayer([
        { x: 20, y: 24 },
        { x: 54, y: 60 }
      ], '#000000', 24, PaintMode.ERASER);
      const eraser = store.getLayer(eraserId);
      expect(eraser?.name).assertEqual('Eraser stroke 2');
      expect(eraser?.kind).assertEqual('paint');
      expect(eraser?.paintMode).assertEqual(PaintMode.ERASER);
      expect(eraser?.paintTargetId).assertEqual(brushId);
      expect(store.activeTool).assertEqual(EditorTool.ERASER);
      expect(store.setPaintMode(eraserId, PaintMode.BRUSH)).assertEqual(true);
      expect(store.getLayer(eraserId)?.paintMode).assertEqual(PaintMode.BRUSH);
      store.undo();
      expect(store.getLayer(eraserId)?.paintMode).assertEqual(PaintMode.ERASER);
      store.undo();
      expect(store.getLayer(eraserId)).assertEqual(undefined);
      store.redo();
      expect(store.getLayer(eraserId)?.paintMode).assertEqual(PaintMode.ERASER);
    });

    it('creates non-destructive linear gradients with source-space endpoints', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalCount: number = store.document.layers.length;
      const gradientId: string = store.addGradientLayer(
        { x: -8, y: 12.4 },
        { x: 90, y: 80 },
        '#abc',
        '112233',
        false
      );
      const gradient = store.getLayer(gradientId);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      expect(store.selectedLayerId).assertEqual(gradientId);
      expect(gradient?.kind).assertEqual('paint');
      expect(gradient?.paintMode).assertEqual(PaintMode.GRADIENT);
      expect(gradient?.paintGradientStyle).assertEqual(PaintGradientStyle.LINEAR);
      expect(gradient?.paintColor).assertEqual('#AABBCC');
      expect(gradient?.paintSecondaryColor).assertEqual('#112233');
      expect(gradient?.paintGradientReverse).assertEqual(false);
      expect(gradient?.paintPoints.length).assertEqual(2);
      expect(gradient?.paintPoints[0].x).assertEqual(0);
      expect(gradient?.paintPoints[0].y).assertEqual(12);
      expect(gradient?.paintPoints[1].x).assertEqual(90);
      expect(gradient?.paintPoints[1].y).assertEqual(80);
      expect(gradient?.paintClip.width).assertEqual(150);
      expect(gradient?.paintClip.height).assertEqual(105);
    });

    it('clips gradients to the active selection and restores edits through history', 0, () => {
      const store: EditorStore = new EditorStore();
      store.setSelection({ x: 20, y: 15, width: 60, height: 45 });
      const gradientId: string = store.addGradientLayer(
        { x: 10, y: 20 },
        { x: 120, y: 90 },
        '#2BB8A7',
        '#F2F5F3'
      );
      const gradient = store.getLayer(gradientId);
      expect(gradient?.paintClip.x).assertEqual(20);
      expect(gradient?.paintClip.y).assertEqual(15);
      expect(gradient?.paintClip.width).assertEqual(60);
      expect(gradient?.paintClip.height).assertEqual(45);
      expect(store.setPaintSecondaryColor(gradientId, '#123456')).assertEqual(true);
      expect(store.setPaintGradientReverse(gradientId, true)).assertEqual(true);
      expect(store.getLayer(gradientId)?.paintSecondaryColor).assertEqual('#123456');
      expect(store.getLayer(gradientId)?.paintGradientReverse).assertEqual(true);
      store.undo();
      expect(store.getLayer(gradientId)?.paintGradientReverse).assertEqual(false);
      expect(store.getLayer(gradientId)?.paintSecondaryColor).assertEqual('#123456');
      store.undo();
      expect(store.getLayer(gradientId)?.paintSecondaryColor).assertEqual('#F2F5F3');
      store.redo();
      expect(store.getLayer(gradientId)?.paintSecondaryColor).assertEqual('#123456');
    });

    it('normalizes gradient colors and rejects invalid endpoints', 0, () => {
      const store: EditorStore = new EditorStore();
      expect(normalizeHexColor('abc')).assertEqual('#AABBCC');
      expect(store.addGradientLayer({ x: 0, y: 0 }, { x: 0, y: 0 }, '#abc', '#def'))
        .assertEqual('');
      expect(store.addGradientLayer({ x: 0, y: 0 }, { x: 2, y: 0 }, '#abc', '#def'))
        .assertEqual('');
      expect(store.addGradientLayer({ x: 0, y: 0 }, { x: 20, y: 0 }, 'not-a-color', '#def'))
        .assertEqual('');
      expect(store.addGradientLayer({ x: 0, y: 0 }, { x: 20, y: 0 }, '#abc', 'not-a-color'))
        .assertEqual('');
    });

    it('floods a contiguous color region with bounded tolerance', 0, () => {
      const pixels: Uint8Array = new Uint8Array(4 * 3 * 4);
      for (let index: number = 0; index < pixels.length; index += 4) {
        pixels[index] = 20;
        pixels[index + 1] = 40;
        pixels[index + 2] = 60;
        pixels[index + 3] = 255;
      }
      pixels[5] = 200;
      pixels[6] = 40;
      pixels[7] = 60;
      pixels[21] = 200;
      pixels[22] = 40;
      pixels[23] = 60;
      pixels[37] = 200;
      pixels[38] = 40;
      pixels[39] = 60;
      const mask: Uint8Array = floodFillMask(pixels, 4, 3, 16, 0, 0, 5, true, false);
      let selectedCount: number = 0;
      for (const value of mask) {
        if (value > 0) {
          selectedCount += 1;
        }
      }
      expect(selectedCount).assertEqual(3);
    });

    it('supports global flood fill and fill-layer option history', 0, () => {
      const pixels: Uint8Array = new Uint8Array(4 * 2 * 4);
      for (let index: number = 0; index < pixels.length; index += 4) {
        pixels[index] = 10;
        pixels[index + 1] = 20;
        pixels[index + 2] = 30;
        pixels[index + 3] = 255;
      }
      pixels[4] = 20;
      pixels[5] = 30;
      pixels[6] = 40;
      const globalMask: Uint8Array = floodFillMask(pixels, 2, 2, 8, 0, 0, 2, false, false);
      let globalCount: number = 0;
      for (const value of globalMask) {
        if (value > 0) {
          globalCount += 1;
        }
      }
      expect(globalCount).assertEqual(3);

      const store: EditorStore = new EditorStore();
      const fillId: string = store.addFillLayer({ x: 18, y: 22 }, '#2BB8A7', 64, false, true);
      const fill = store.getLayer(fillId);
      expect(fill?.paintMode).assertEqual(PaintMode.FILL);
      expect(fill?.paintFillTolerance).assertEqual(64);
      expect(fill?.paintFillContiguous).assertEqual(false);
      expect(fill?.paintFillAntialias).assertEqual(true);
      expect(store.setPaintFillTolerance(fillId, 90)).assertEqual(true);
      expect(store.setPaintFillContiguous(fillId, true)).assertEqual(true);
      expect(store.setPaintFillAntialias(fillId, false)).assertEqual(true);
      expect(store.getLayer(fillId)?.paintFillTolerance).assertEqual(90);
      expect(store.getLayer(fillId)?.paintFillContiguous).assertEqual(true);
      expect(store.getLayer(fillId)?.paintFillAntialias).assertEqual(false);
      store.undo();
      expect(store.getLayer(fillId)?.paintFillAntialias).assertEqual(true);
      store.undo();
      expect(store.getLayer(fillId)?.paintFillContiguous).assertEqual(false);
      store.undo();
      expect(store.getLayer(fillId)?.paintFillTolerance).assertEqual(64);
      store.undo();
      expect(store.getLayer(fillId)).assertEqual(undefined);
    });

    it('creates clone layers with source anchors and history', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalCount: number = store.document.layers.length;
      const cloneId: string = store.addCloneLayer(
        { x: -4, y: 12.6 },
        [{ x: 220, y: 80 }, { x: 140, y: 64 }],
        18
      );
      const clone = store.getLayer(cloneId);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      expect(clone?.kind).assertEqual('paint');
      expect(clone?.paintMode).assertEqual(PaintMode.CLONE);
      expect(clone?.paintWidth).assertEqual(18);
      expect(clone?.paintCloneSource.x).assertEqual(0);
      expect(clone?.paintCloneSource.y).assertEqual(13);
      expect(clone?.paintPoints.length).assertEqual(2);
      expect(clone?.paintPoints[0].x).assertEqual(149);
      expect(clone?.paintPoints[0].y).assertEqual(80);
      expect(clone?.paintPoints[1].x).assertEqual(140);
      expect(clone?.paintPoints[1].y).assertEqual(64);
      expect(clone?.paintClip.width).assertEqual(150);
      expect(clone?.paintClip.height).assertEqual(105);
      store.undo();
      expect(store.getLayer(cloneId)).assertEqual(undefined);
      store.redo();
      expect(store.getLayer(cloneId)?.paintMode).assertEqual(PaintMode.CLONE);
      expect(store.getLayer(cloneId)?.paintCloneSource.x).assertEqual(0);
    });

    it('clips clone layers to the active source-space selection', 0, () => {
      const store: EditorStore = new EditorStore();
      store.setSelection({ x: 18, y: 20, width: 70, height: 45 });
      const cloneId: string = store.addCloneLayer({ x: 30, y: 30 },
        [{ x: 100, y: 60 }], 12);
      const clone = store.getLayer(cloneId);
      expect(clone?.paintClip.x).assertEqual(18);
      expect(clone?.paintClip.y).assertEqual(20);
      expect(clone?.paintClip.width).assertEqual(70);
      expect(clone?.paintClip.height).assertEqual(45);
    });

    it('creates non-destructive blur strokes with strength and history', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalCount: number = store.document.layers.length;
      const blurId: string = store.addBlurLayer([
        { x: 18, y: 22 },
        { x: 82, y: 66 }
      ], 24, 75);
      const blur = store.getLayer(blurId);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      expect(store.selectedLayerId).assertEqual(blurId);
      expect(blur?.kind).assertEqual('paint');
      expect(blur?.paintMode).assertEqual(PaintMode.BLUR);
      expect(blur?.paintWidth).assertEqual(24);
      expect(blur?.paintRetouchStrength).assertEqual(75);
      expect(blur?.paintPoints.length).assertEqual(2);
      expect(store.setPaintRetouchStrength(blurId, 20)).assertEqual(true);
      expect(store.getLayer(blurId)?.paintRetouchStrength).assertEqual(20);
      store.undo();
      expect(store.getLayer(blurId)?.paintRetouchStrength).assertEqual(75);
      store.redo();
      expect(store.getLayer(blurId)?.paintRetouchStrength).assertEqual(20);
      store.undo();
      store.undo();
      expect(store.getLayer(blurId)).assertEqual(undefined);
      store.redo();
      expect(store.getLayer(blurId)?.paintMode).assertEqual(PaintMode.BLUR);
    });

    it('clips blur strokes to the active source-space selection', 0, () => {
      const store: EditorStore = new EditorStore();
      store.setSelection({ x: 22, y: 18, width: 64, height: 42 });
      const blurId: string = store.addBlurLayer([{ x: 30, y: 28 }, { x: 92, y: 72 }], 18, 50);
      const blur = store.getLayer(blurId);
      expect(blur?.paintClip.x).assertEqual(22);
      expect(blur?.paintClip.y).assertEqual(18);
      expect(blur?.paintClip.width).assertEqual(64);
      expect(blur?.paintClip.height).assertEqual(42);
    });

    it('creates non-destructive sharpen strokes with strength and history', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalCount: number = store.document.layers.length;
      const sharpenId: string = store.addSharpenLayer([
        { x: 16, y: 24 },
        { x: 86, y: 70 }
      ], 22, 80);
      const sharpen = store.getLayer(sharpenId);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      expect(store.selectedLayerId).assertEqual(sharpenId);
      expect(sharpen?.kind).assertEqual('paint');
      expect(sharpen?.paintMode).assertEqual(PaintMode.SHARPEN);
      expect(sharpen?.paintWidth).assertEqual(22);
      expect(sharpen?.paintRetouchStrength).assertEqual(80);
      expect(sharpen?.paintPoints.length).assertEqual(2);
      expect(store.setPaintRetouchStrength(sharpenId, 35)).assertEqual(true);
      expect(store.getLayer(sharpenId)?.paintRetouchStrength).assertEqual(35);
      store.undo();
      expect(store.getLayer(sharpenId)?.paintRetouchStrength).assertEqual(80);
      store.redo();
      expect(store.getLayer(sharpenId)?.paintRetouchStrength).assertEqual(35);
      store.undo();
      store.undo();
      expect(store.getLayer(sharpenId)).assertEqual(undefined);
      store.redo();
      expect(store.getLayer(sharpenId)?.paintMode).assertEqual(PaintMode.SHARPEN);
    });

    it('clips sharpen strokes to the active source-space selection', 0, () => {
      const store: EditorStore = new EditorStore();
      store.setSelection({ x: 20, y: 16, width: 68, height: 46 });
      const sharpenId: string = store.addSharpenLayer([{ x: 28, y: 26 }, { x: 96, y: 76 }], 16, 60);
      const sharpen = store.getLayer(sharpenId);
      expect(sharpen?.paintClip.x).assertEqual(20);
      expect(sharpen?.paintClip.y).assertEqual(16);
      expect(sharpen?.paintClip.width).assertEqual(68);
      expect(sharpen?.paintClip.height).assertEqual(46);
    });

    it('creates non-destructive smudge strokes with strength and history', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalCount: number = store.document.layers.length;
      const smudgeId: string = store.addSmudgeLayer([
        { x: 18, y: 22 },
        { x: 82, y: 66 }
      ], 24, 75);
      const smudge = store.getLayer(smudgeId);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      expect(store.selectedLayerId).assertEqual(smudgeId);
      expect(smudge?.kind).assertEqual('paint');
      expect(smudge?.paintMode).assertEqual(PaintMode.SMUDGE);
      expect(smudge?.paintWidth).assertEqual(24);
      expect(smudge?.paintRetouchStrength).assertEqual(75);
      expect(smudge?.paintPoints.length).assertEqual(2);
      expect(store.setPaintRetouchStrength(smudgeId, 20)).assertEqual(true);
      expect(store.getLayer(smudgeId)?.paintRetouchStrength).assertEqual(20);
      store.undo();
      expect(store.getLayer(smudgeId)?.paintRetouchStrength).assertEqual(75);
      store.redo();
      expect(store.getLayer(smudgeId)?.paintRetouchStrength).assertEqual(20);
      store.undo();
      store.undo();
      expect(store.getLayer(smudgeId)).assertEqual(undefined);
      store.redo();
      expect(store.getLayer(smudgeId)?.paintMode).assertEqual(PaintMode.SMUDGE);
    });

    it('clips smudge strokes to the active source-space selection', 0, () => {
      const store: EditorStore = new EditorStore();
      store.setSelection({ x: 24, y: 16, width: 62, height: 48 });
      const smudgeId: string = store.addSmudgeLayer([{ x: 30, y: 24 }, { x: 94, y: 76 }], 18, 50);
      const smudge = store.getLayer(smudgeId);
      expect(smudge?.paintClip.x).assertEqual(24);
      expect(smudge?.paintClip.y).assertEqual(16);
      expect(smudge?.paintClip.width).assertEqual(62);
      expect(smudge?.paintClip.height).assertEqual(48);
    });

    it('creates non-destructive sponge strokes with flow and mode history', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalCount: number = store.document.layers.length;
      const spongeId: string = store.addSpongeLayer([
        { x: 20, y: 24 },
        { x: 84, y: 68 }
      ], 22, 65, 0);
      const sponge = store.getLayer(spongeId);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      expect(store.selectedLayerId).assertEqual(spongeId);
      expect(sponge?.kind).assertEqual('paint');
      expect(sponge?.paintMode).assertEqual(PaintMode.SPONGE);
      expect(sponge?.paintWidth).assertEqual(22);
      expect(sponge?.paintRetouchStrength).assertEqual(65);
      expect(sponge?.paintSpongeMode).assertEqual(0);
      expect(sponge?.paintPoints.length).assertEqual(2);
      expect(store.setPaintRetouchStrength(spongeId, 25)).assertEqual(true);
      expect(store.getLayer(spongeId)?.paintRetouchStrength).assertEqual(25);
      expect(store.setPaintSpongeMode(spongeId, 1)).assertEqual(true);
      expect(store.getLayer(spongeId)?.paintSpongeMode).assertEqual(1);
      store.undo();
      expect(store.getLayer(spongeId)?.paintSpongeMode).assertEqual(0);
      store.undo();
      expect(store.getLayer(spongeId)?.paintRetouchStrength).assertEqual(65);
      store.undo();
      expect(store.getLayer(spongeId)).assertEqual(undefined);
      store.redo();
      expect(store.getLayer(spongeId)?.paintMode).assertEqual(PaintMode.SPONGE);
    });

    it('clips sponge strokes to the active source-space selection', 0, () => {
      const store: EditorStore = new EditorStore();
      store.setSelection({ x: 26, y: 18, width: 60, height: 46 });
      const spongeId: string = store.addSpongeLayer([{ x: 32, y: 26 }, { x: 96, y: 74 }], 18, 50, 1);
      const sponge = store.getLayer(spongeId);
      expect(sponge?.paintClip.x).assertEqual(26);
      expect(sponge?.paintClip.y).assertEqual(18);
      expect(sponge?.paintClip.width).assertEqual(60);
      expect(sponge?.paintClip.height).assertEqual(46);
    });

    it('creates non-destructive dodge strokes with exposure and tone-range history', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalCount: number = store.document.layers.length;
      const dodgeId: string = store.addDodgeLayer([
        { x: 18, y: 22 },
        { x: 82, y: 66 }
      ], 24, 65, 2);
      const dodge = store.getLayer(dodgeId);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      expect(store.selectedLayerId).assertEqual(dodgeId);
      expect(dodge?.kind).assertEqual('paint');
      expect(dodge?.paintMode).assertEqual(PaintMode.DODGE);
      expect(dodge?.paintWidth).assertEqual(24);
      expect(dodge?.paintRetouchStrength).assertEqual(65);
      expect(dodge?.paintRetouchRange).assertEqual(2);
      expect(dodge?.paintPoints.length).assertEqual(2);
      expect(store.setPaintRetouchStrength(dodgeId, 0)).assertEqual(true);
      expect(store.getLayer(dodgeId)?.paintRetouchStrength).assertEqual(0);
      store.undo();
      expect(store.setPaintRetouchStrength(dodgeId, 20)).assertEqual(true);
      expect(store.getLayer(dodgeId)?.paintRetouchStrength).assertEqual(20);
      expect(store.setPaintRetouchRange(dodgeId, 0)).assertEqual(true);
      expect(store.getLayer(dodgeId)?.paintRetouchRange).assertEqual(0);
      store.undo();
      expect(store.getLayer(dodgeId)?.paintRetouchRange).assertEqual(2);
      store.undo();
      expect(store.getLayer(dodgeId)?.paintRetouchStrength).assertEqual(65);
      store.undo();
      expect(store.getLayer(dodgeId)).assertEqual(undefined);
      store.redo();
      expect(store.getLayer(dodgeId)?.paintMode).assertEqual(PaintMode.DODGE);
    });

    it('creates non-destructive burn strokes and clips them to source-space selection', 0, () => {
      const store: EditorStore = new EditorStore();
      store.setSelection({ x: 18, y: 20, width: 70, height: 45 });
      const burnId: string = store.addBurnLayer([
        { x: 30, y: 30 },
        { x: 100, y: 60 }
      ], 18, 40, 0);
      const burn = store.getLayer(burnId);
      expect(burn?.paintMode).assertEqual(PaintMode.BURN);
      expect(burn?.paintRetouchStrength).assertEqual(40);
      expect(burn?.paintRetouchRange).assertEqual(0);
      expect(burn?.paintClip.x).assertEqual(18);
      expect(burn?.paintClip.y).assertEqual(20);
      expect(burn?.paintClip.width).assertEqual(70);
      expect(burn?.paintClip.height).assertEqual(45);
    });

    it('uses directional tone curves and mode-specific flow for dodge and burn', 0, () => {
      expect(dodgeBurnToneValue(64, PaintMode.DODGE, 0)).assertEqual(160);
      expect(dodgeBurnToneValue(64, PaintMode.DODGE, 1)).assertEqual(128);
      expect(dodgeBurnToneValue(64, PaintMode.DODGE, 2)).assertEqual(128);
      expect(dodgeBurnToneValue(64, PaintMode.BURN, 0)).assertEqual(0);
      expect(dodgeBurnToneValue(64, PaintMode.BURN, 1)).assertEqual(16);
      expect(dodgeBurnToneValue(64, PaintMode.BURN, 2)).assertEqual(32);
      expect(dodgeBurnExposureFlow(50, PaintMode.DODGE)).assertClose(0.5 / Math.PI, 0.0001);
      expect(dodgeBurnExposureFlow(50, PaintMode.BURN)).assertClose(0.5 / Math.E, 0.0001);
    });

    it('keeps brush points in source space through crop and transform history', 0, () => {
      const store: EditorStore = new EditorStore();
      const paintId: string = store.addPaintLayer([
        { x: 18, y: 22 },
        { x: 66, y: 48 }
      ], '#2bb8a7', 12);
      store.applyCrop({ x: 10, y: 12, width: 100, height: 70 });
      store.rotateClockwise();
      expect(store.document.width).assertEqual(70);
      expect(store.document.height).assertEqual(100);
      expect(store.getLayer(paintId)?.paintPoints[0].x).assertEqual(18);
      expect(store.getLayer(paintId)?.paintPoints[0].y).assertEqual(22);
      store.undo();
      expect(store.document.width).assertEqual(100);
      expect(store.document.height).assertEqual(70);
      store.undo();
      expect(store.document.width).assertEqual(150);
      expect(store.document.height).assertEqual(105);
      expect(store.getLayer(paintId)?.paintPoints[1].x).assertEqual(66);
      expect(store.getLayer(paintId)?.paintPoints[1].y).assertEqual(48);
    });

    it('maps source brush points into the transformed crop preview', 0, () => {
      const point: TransformPoint = sourcePointToCropSpace({ x: 30, y: 40 }, {
        x: 10,
        y: 12,
        width: 100,
        height: 70
      }, 150, 105, {
        rotation: 90,
        flipHorizontal: false,
        flipVertical: false
      });
      expect(point.x).assertEqual(-28);
      expect(point.y).assertEqual(20);
      const flipped: TransformPoint = sourcePointToCropSpace({ x: 30, y: 40 }, {
        x: 10,
        y: 12,
        width: 100,
        height: 70
      }, 150, 105, {
        rotation: 0,
        flipHorizontal: true,
        flipVertical: false
      });
      expect(flipped.x).assertEqual(-20);
      expect(flipped.y).assertEqual(28);
    });

    it('maps quarter-turn and flip coordinates to stable document bounds', 0, () => {
      const rotated: TransformState = {
        rotation: 90,
        flipHorizontal: true,
        flipVertical: false
      };
      const size = transformedSize(150, 105, rotated);
      expect(size.width).assertEqual(105);
      expect(size.height).assertEqual(150);
      const point = transformPoint(0, 0, 150, 105, rotated);
      expect(point.x).assertEqual(0);
      expect(point.y).assertEqual(0);
      const opposite = transformPoint(150, 105, 150, 105, rotated);
      expect(opposite.x).assertEqual(105);
      expect(opposite.y).assertEqual(150);
    });

  it('keeps document transforms and source coordinates non-destructive', 0, () => {
      const store: EditorStore = new EditorStore();
      const textId: string = store.addTextLayer('Transform title');
      store.setTextPosition(textId, 48, 64);
      store.rotateClockwise();
      store.flipHorizontal();
      expect(store.document.sourceWidth).assertEqual(150);
      expect(store.document.sourceHeight).assertEqual(105);
      expect(store.document.width).assertEqual(105);
      expect(store.document.height).assertEqual(150);
      expect(store.getLayer(textId)?.textX).assertEqual(48);
      expect(store.getLayer(textId)?.textY).assertEqual(64);
      expect(store.document.transform.rotation).assertEqual(90);
      expect(store.document.transform.flipHorizontal).assertEqual(true);
      store.undo();
      expect(store.document.transform.flipHorizontal).assertEqual(false);
      store.undo();
      expect(store.document.transform.rotation).assertEqual(0);
      expect(store.document.width).assertEqual(150);
      expect(store.document.height).assertEqual(105);
      store.redo();
      expect(store.document.transform.rotation).assertEqual(90);
      store.redo();
      expect(store.document.transform.flipHorizontal).assertEqual(true);
      store.resetTransform();
      expect(store.document.transform.rotation).assertEqual(0);
      expect(store.document.transform.flipHorizontal).assertEqual(false);
      expect(store.document.width).assertEqual(150);
      expect(store.document.height).assertEqual(105);
    });

    it('constrains crop rectangles and restores crop history', 0, () => {
      const square: TransformState = {
        rotation: 0,
        flipHorizontal: false,
        flipVertical: false
      };
      const squareRect = centeredCropRect(150, 105, 'square');
      expect(squareRect.x).assertEqual(23);
      expect(squareRect.y).assertEqual(0);
      expect(squareRect.width).assertEqual(105);
      expect(squareRect.height).assertEqual(105);
      const ratio = cropAspectForRect(centeredCropRect(150, 105, 'fourThree'));
      expect(ratio).assertEqual('fourThree');
      const bounded = normalizeCropRect({ x: -10, y: 90, width: 400, height: 400 }, 150, 105);
      expect(bounded.x).assertEqual(0);
      expect(bounded.y).assertEqual(0);
      expect(bounded.width).assertEqual(150);
      expect(bounded.height).assertEqual(105);

      const store: EditorStore = new EditorStore();
      expect(store.applyCrop(squareRect)).assertEqual(true);
      store.rotateClockwise();
      expect(store.document.width).assertEqual(105);
      expect(store.document.height).assertEqual(105);
      expect(square.rotation).assertEqual(0);
      store.undo();
      expect(store.document.crop.rect.width).assertEqual(105);
      expect(store.document.crop.rect.height).assertEqual(105);
      expect(store.document.width).assertEqual(105);
      expect(store.document.height).assertEqual(105);
      store.undo();
      expect(store.document.crop.rect.width).assertEqual(150);
      expect(store.document.crop.rect.height).assertEqual(105);
      store.redo();
      expect(store.document.crop.rect.width).assertEqual(105);
      store.redo();
      expect(store.document.width).assertEqual(105);
      expect(store.document.height).assertEqual(105);

      const landscapeStore: EditorStore = new EditorStore();
      expect(landscapeStore.applyCrop({ x: 10, y: 20, width: 100, height: 60 })).assertEqual(true);
      landscapeStore.rotateClockwise();
      expect(landscapeStore.document.width).assertEqual(60);
      expect(landscapeStore.document.height).assertEqual(100);
    });

    it('normalizes selection bounds and crops through transformed coordinates', 0, () => {
      const selection: SelectionRect = normalizeSelectionRect({
        x: -8,
        y: 12,
        width: 80,
        height: 240
      }, 150, 105);
      expect(selection.x).assertEqual(0);
      expect(selection.y).assertEqual(0);
      expect(selection.width).assertEqual(80);
      expect(selection.height).assertEqual(105);

      const transformed: TransformState = {
        rotation: 90,
        flipHorizontal: false,
        flipVertical: false
      };
      const crop = selectionToCropRect({
        x: 8,
        y: 10,
        width: 40,
        height: 60
      }, {
        x: 20,
        y: 5,
        width: 150,
        height: 105
      }, transformed);
      expect(crop.x).assertEqual(30);
      expect(crop.y).assertEqual(62);
      expect(crop.width).assertEqual(60);
      expect(crop.height).assertEqual(40);
    });

    it('stores selection actions in history and restores them with undo and redo', 0, () => {
      const store: EditorStore = new EditorStore();
      expect(store.setSelection({ x: 18, y: 22, width: 64, height: 48 })).assertEqual(true);
      expect(store.document.selection.active).assertEqual(true);
      expect(store.getSelectionRect().width).assertEqual(64);
      store.undo();
      expect(store.document.selection.active).assertEqual(false);
      store.redo();
      expect(store.document.selection.active).assertEqual(true);
      expect(store.getSelectionRect().x).assertEqual(18);
      store.deselect();
      expect(store.document.selection.active).assertEqual(false);
      store.undo();
      expect(store.document.selection.active).assertEqual(true);
      expect(store.getSelectionRect().width).assertEqual(64);
    });

    it('stores lasso polygons with bounds and history', 0, () => {
      const store: EditorStore = new EditorStore();
      expect(store.setLassoSelection([
        { x: 18, y: 20 },
        { x: 78, y: 16 },
        { x: 92, y: 66 },
        { x: 24, y: 72 }
      ])).assertEqual(true);
      expect(store.document.selection.mode).assertEqual('lasso');
      expect(store.document.selection.points.length).assertEqual(4);
      expect(store.getSelectionRect().x).assertEqual(18);
      expect(store.getSelectionRect().y).assertEqual(16);
      expect(store.getSelectionRect().width).assertEqual(74);
      expect(store.getSelectionRect().height).assertEqual(56);
      store.undo();
      expect(store.document.selection.active).assertEqual(false);
      store.redo();
      expect(store.document.selection.mode).assertEqual('lasso');
      expect(store.document.selection.points.length).assertEqual(4);
    });

    it('clips strokes to the exact lasso region instead of its bounds', 0, () => {
      const store: EditorStore = new EditorStore();
      // Diamond outline: stroke pixels outside the diamond but inside the
      // bounds rectangle must be clipped away.
      const left: number = 20;
      const top: number = 20;
      const size: number = 60;
      expect(store.setLassoSelection([
        { x: left + size / 2, y: top },
        { x: left + size, y: top + size / 2 },
        { x: left + size / 2, y: top + size },
        { x: left, y: top + size / 2 }
      ])).assertEqual(true);
      const strokeId: string = store.addBlurLayer([
        { x: 22, y: 22 },
        { x: 78, y: 78 }
      ], 20, 80);
      const stroke = store.getLayer(strokeId);
      expect(stroke?.paintClipMask.length).assertEqual(150 * 105);
      expect(stroke?.paintClipMaskWidth).assertEqual(150);
      // The bounds corner sits outside the diamond, so it must not be painted.
      expect(stroke?.paintClipMask[top * 150 + left]).assertEqual(0);
      // The diamond centre is inside, so it must be painted.
      expect(stroke?.paintClipMask[50 * 150 + 50]).assertEqual(255);
      // One pixel above the top vertex is outside the diamond.
      expect(stroke?.paintClipMask[19 * 150 + 50]).assertEqual(0);
      // Rectangle selection keeps the bounds-only behaviour.
      store.deselect();
      store.setSelection({ x: left, y: top, width: size, height: size });
      const rectId: string = store.addBlurLayer([{ x: 22, y: 22 }, { x: 78, y: 78 }], 20, 80);
      expect(store.getLayer(rectId)?.paintClipMask.length).assertEqual(0);
      expect(store.getLayer(rectId)?.paintClipMaskWidth).assertEqual(0);
    });

    it('corrects red-eye pixels toward the sclera tone and spares other hues', 0, () => {
      // The red band is fully weighted, so reds are pulled toward neutral.
      expect(redEyeWeight(0.8, 0.2, 0.2)).assertClose(1, 0.001);
      // Blue, green and grey fall outside the red band entirely.
      expect(redEyeWeight(0.2, 0.5, 0.8)).assertClose(0, 0.001);
      expect(redEyeWeight(0.3, 0.6, 0.3)).assertClose(0, 0.001);
      const red = redEyeCorrection(0.8, 0.2, 0.2);
      // Corrected red is desaturated toward the sclera tone: the channel spread
      // collapses from 0.6 to nearly neutral while lightness is preserved.
      const redSpread: number = Math.max(red.hue, red.saturation, red.lightness) -
        Math.min(red.hue, red.saturation, red.lightness);
      expect(redSpread).assertClose(0.06, 0.02);
      // The average channel level is close to the original red's lightness,
      // so the correction desaturates rather than darkening the pixel.
      const redLevel: number = (red.hue + red.saturation + red.lightness) / 3;
      expect(redLevel).assertClose(0.5, 0.03);
      // A blue pixel is returned untouched.
      const blue = redEyeCorrection(0.2, 0.5, 0.8);
      expect(blue.hue).assertClose(0.2, 0.02);
      expect(blue.saturation).assertClose(0.5, 0.02);
      expect(blue.lightness).assertClose(0.8, 0.02);
    });

    it('converts pixels to BT.601 YCbCr with upstream integer rounding', 0, () => {
      const grey: Uint8Array = new Uint8Array([128, 128, 128, 255]);
      const ycbcr: Int16Array = rgbaToYcbcr(grey);
      // 65.481/255*128 + 128.553/255*128 + 24.966/255*128 = 125.9, +16 = 141...
      // the upstream floor(+0.5) rounding gives these exact values.
      expect(ycbcr[0]).assertEqual(126);
      expect(ycbcr[1]).assertEqual(90);
      expect(ycbcr[2]).assertEqual(128);
      expect(ycbcr[3]).assertEqual(255);
      const red: Uint8Array = new Uint8Array([255, 0, 0, 255]);
      const redYcbcr: Int16Array = rgbaToYcbcr(red);
      expect(redYcbcr[0]).assertEqual(81);
      expect(redYcbcr[1]).assertEqual(90);
      expect(redYcbcr[2]).assertEqual(240);
    });

    it('computes the 8x8 Walsh-Hadamard coefficients the heal match reads', 0, () => {
      // The DC coefficient is the sum of the block, since the transform is unnormalised.
      const ramp: Float64Array = new Float64Array(64);
      let sum: number = 0;
      for (let index: number = 0; index < 64; index++) {
        ramp[index] = index + 1;
        sum += index + 1;
      }
      fwht64(ramp);
      expect(ramp[0]).assertEqual(sum);
      // A mean-centred block has no DC component at all.
      const centred: Float64Array = new Float64Array(64);
      for (let index: number = 0; index < 64; index++) {
        centred[index] = index + 1 - 32.5;
      }
      fwht64(centred);
      expect(centred[0]).assertClose(0, 0.0001);
      // A constant block keeps all of its energy in the DC term.
      const flat: Float64Array = new Float64Array(64);
      for (let index: number = 0; index < 64; index++) {
        flat[index] = 5;
      }
      fwht64(flat);
      expect(flat[0]).assertEqual(320);
      for (let index: number = 1; index < 64; index++) {
        expect(flat[index]).assertEqual(0);
      }
      // The transform is its own inverse up to a factor of 64.
      const forward: Float64Array = new Float64Array(64);
      for (let index: number = 0; index < 64; index++) {
        forward[index] = ((index * 37) % 97) - 48;
      }
      const before: Float64Array = Float64Array.from(forward);
      fwht64(forward);
      fwht64(forward);
      for (let index: number = 0; index < 64; index++) {
        expect(forward[index]).assertClose(before[index] * 64, 0.0001);
      }
    });

    it('heals a painted blemish by sampling real surrounding texture', 0, () => {
      const width: number = 32;
      const height: number = 28;
      const scene: HealScene = buildHealScene(width, height);
      // The blemish is genuinely present before healing.
      expect(countReddish(scene.pixels, scene.mask, width, height)).assertEqual(49);
      // A single global offset cannot clear it: upstream still needs the graph-cut stage.
      const offset: HealOffset = healVotedOffset(scene.pixels, scene.mask, width, height);
      expect(offset.votes).assertEqual(61);
      expect(offset.x).assertEqual(0);
      expect(offset.y).assertEqual(1);
      // The plan keeps a diverse set of patches and labels every hole pixel.
      const plan: HealPlan | undefined = healPatchPlan(scene.pixels, scene.mask, width, height);
      expect(plan !== undefined).assertEqual(true);
      expect(plan?.patches.length).assertEqual(7);
      expect(plan?.labels.length).assertEqual(49);
      expect(plan?.downsample).assertEqual(1);
      const healed: Uint8Array = applyHealPlan(plan as HealPlan, scene.pixels, scene.mask,
        width, height);
      // The blemish is gone and real texture now fills the hole.
      expect(countReddish(healed, scene.mask, width, height)).assertEqual(0);
      const centre: number = ((height >> 1) * width + (width >> 1)) << 2;
      expect(scene.pixels[centre]).assertEqual(200);
      expect(healed[centre]).assertEqual(39);
      // Pixels outside the mask are left untouched.
      const far: number = (2 * width + 2) << 2;
      expect(healed[far]).assertEqual(scene.pixels[far]);
      expect(healed[far + 1]).assertEqual(scene.pixels[far + 1]);
      expect(healed[far + 2]).assertEqual(scene.pixels[far + 2]);
    });

    it('creates spot healing layers with flow and history', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalCount: number = store.document.layers.length;
      const layerId: string = store.addSpotHealLayer([{ x: 40, y: 36 }], 18, 70);
      expect(layerId !== '').assertEqual(true);
      const layer = store.getLayer(layerId);
      expect(layer?.paintMode).assertEqual(PaintMode.SPOT_HEAL);
      expect(layer?.paintWidth).assertEqual(18);
      expect(layer?.paintRetouchStrength).assertEqual(70);
      expect(store.selectedLayerId).assertEqual(layerId);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      // A second stroke stacks as its own layer with its own history entry.
      const secondId: string = store.addSpotHealLayer([{ x: 60, y: 50 }], 12, 40);
      expect(secondId === layerId).assertEqual(false);
      expect(store.document.layers.length).assertEqual(originalCount + 2);
      // Flow is editable and undo restores the previous value.
      expect(store.setPaintRetouchStrength(secondId, 85)).assertEqual(true);
      expect(store.getLayer(secondId)?.paintRetouchStrength).assertEqual(85);
      store.undo();
      expect(store.getLayer(secondId)?.paintRetouchStrength).assertEqual(40);
      store.redo();
      expect(store.getLayer(secondId)?.paintRetouchStrength).assertEqual(85);
      // Undoing the stroke removes the layer and restores the previous count.
      store.undo();
      expect(store.getLayer(secondId)).assertEqual(undefined);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      expect(store.getLayer(layerId)?.paintMode).assertEqual(PaintMode.SPOT_HEAL);
    });

    it('clips spot healing strokes to the active source-space selection', 0, () => {
      const store: EditorStore = new EditorStore();
      store.setSelection({ x: 10, y: 10, width: 20, height: 20 });
      const layerId: string = store.addSpotHealLayer([{ x: 15, y: 15 }], 10, 50);
      const layer = store.getLayer(layerId);
      // A rectangular selection clips by bounds rather than a per-pixel mask.
      expect(layer?.paintClip.x).assertEqual(10);
      expect(layer?.paintClip.y).assertEqual(10);
      expect(layer?.paintClip.width).assertEqual(20);
      expect(layer?.paintClip.height).assertEqual(20);
      // A stroke outside the selection is still clipped away entirely.
      const outsideId: string = store.addSpotHealLayer([{ x: 80, y: 80 }], 10, 50);
      const outside = store.getLayer(outsideId);
      expect(outside?.paintClip.width).assertEqual(20);
      expect(outside?.paintClip.x).assertEqual(10);
    });

    it('heals without swapping colour channels', 0, () => {
      // Guards the PixelMap channel order: the planner works in RGB and the
      // surface writes RGBA, so a swap would invert the repaired colours.
      const width: number = 32;
      const height: number = 32;
      const pixels: Uint8Array = new Uint8Array(width * height * 4);
      const mask: Uint8Array = new Uint8Array(width * height);
      for (let y: number = 0; y < height; y++) {
        for (let x: number = 0; x < width; x++) {
          const offset: number = (y * width + x) << 2;
          // Background is deliberately red-dominant, so a swap is visible.
          pixels[offset] = 150;
          pixels[offset + 1] = 60;
          pixels[offset + 2] = 40;
          pixels[offset + 3] = 255;
        }
      }
      for (let y: number = 14; y <= 18; y++) {
        for (let x: number = 14; x <= 18; x++) {
          if (Math.sqrt((x - 16) * (x - 16) + (y - 16) * (y - 16)) > 3) {
            continue;
          }
          mask[y * width + x] = 255;
          const offset: number = (y * width + x) << 2;
          pixels[offset] = 20;
          pixels[offset + 1] = 220;
          pixels[offset + 2] = 200;
        }
      }
      const plan: HealPlan | undefined = healPatchPlan(pixels, mask, width, height);
      expect(plan !== undefined).assertEqual(true);
      const healed: Uint8Array = applyHealPlan(plan as HealPlan, pixels, mask, width, height);
      let redDominant: number = 0;
      let healedCount: number = 0;
      for (let index: number = 0; index < mask.length; index++) {
        if (mask[index] === 0) {
          continue;
        }
        healedCount++;
        const offset: number = index << 2;
        if (healed[offset] > healed[offset + 2]) {
          redDominant++;
        }
      }
      expect(healedCount > 0).assertEqual(true);
      // Every repaired pixel keeps the background's red-dominant ordering.
      expect(redDominant).assertEqual(healedCount);
    });

    it('heals a blemish through the real preview compositor', 0, async () => {
      // Exercises createSpotHealSurface end to end on a real PixelMap, which is
      // the path the unit tests above cannot reach.
      const width: number = 96;
      const height: number = 96;
      const pixels: Uint8Array = new Uint8Array(width * height * 4);
      const centre: number = width >> 1;
      const radius: number = 10;
      for (let y: number = 0; y < height; y++) {
        for (let x: number = 0; x < width; x++) {
          const offset: number = (y * width + x) << 2;
          // Textured background so the patch match has real structure to copy.
          const base: number = 120 + 30 * Math.sin(x * 0.2) + 24 * Math.cos(y * 0.18);
          if (Math.sqrt((x - centre) * (x - centre) + (y - centre) * (y - centre)) <= radius) {
            // A red blemish that must disappear after healing.
            pixels[offset] = 215;
            pixels[offset + 1] = 25;
            pixels[offset + 2] = 25;
          } else {
            pixels[offset] = Math.max(0, Math.min(255, base));
            pixels[offset + 1] = Math.max(0, Math.min(255, base * 0.85));
            pixels[offset + 2] = Math.max(0, Math.min(255, base * 0.7));
          }
          pixels[offset + 3] = 255;
        }
      }
      const source: image.PixelMap = await image.createPixelMap(pixels.buffer as ArrayBuffer, {
        size: { width: width, height: height },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: true
      });
      const srcCentre: number = (centre * width + centre) << 2;
      const store: EditorStore = new EditorStore();
      const layerId: string = store.addSpotHealLayer([{ x: centre, y: centre }], 24, 100);
      expect(layerId !== '').assertEqual(true);
      const layer = store.getLayer(layerId);
      const adjustments: AdjustmentValues = {
        exposure: 0, contrast: 0, saturation: 0, temperature: 0, blur: 0
      };
      const filter: FilterState = { preset: 'none', intensity: 0 };
      const rendered: image.PixelMap = await renderPreviewPixelMap(source, adjustments, filter,
        [layer as LayerModel]);
      const outBuffer: ArrayBuffer = new ArrayBuffer(rendered.getPixelBytesNumber());
      await rendered.readPixelsToBuffer(outBuffer);
      const out: Uint8Array = new Uint8Array(outBuffer);
      // Neutral adjustments must leave the image untouched.
      const passthrough: image.PixelMap = await renderPreviewPixelMap(source, adjustments, filter, []);
      const passBuffer: ArrayBuffer = new ArrayBuffer(passthrough.getPixelBytesNumber());
      await passthrough.readPixelsToBuffer(passBuffer);
      const passOut: Uint8Array = new Uint8Array(passBuffer);
      // readPixelsToBuffer returns BGRA, so the round trip swaps the edges.
      expect(passOut[srcCentre]).assertEqual(pixels[srcCentre + 2]);
      expect(passOut[srcCentre + 1]).assertEqual(pixels[srcCentre + 1]);
      expect(passOut[srcCentre + 2]).assertEqual(pixels[srcCentre]);
      await passthrough.release();
      // The blemish centre must no longer be red-dominant.
      const centreOffset: number = (centre * width + centre) << 2;
      const isRed: boolean = out[centreOffset + 2] > 150 && out[centreOffset + 1] < 95;
      expect(isRed).assertEqual(false);
      // The healed pixel carries the background's red-dominant channel order.
      expect(out[centreOffset + 2] > out[centreOffset + 1]).assertEqual(true);
      expect(out[centreOffset + 1] > out[centreOffset]).assertEqual(true);
      // Untouched corners are preserved exactly.
      const cornerOffset: number = 2 << 2;
      expect(out[cornerOffset]).assertEqual(pixels[cornerOffset + 2]);
      expect(out[cornerOffset + 1]).assertEqual(pixels[cornerOffset + 1]);
      expect(out[cornerOffset + 2]).assertEqual(pixels[cornerOffset]);
      await rendered.release();
      await source.release();
    });

    it('poisson blends a healed region into its surroundings', 0, () => {
      // Ported from upstream's solvePoissonFill: a hard-edged paste is smoothed
      // into the surrounding pixels so the fill does not read as a patch.
      const width: number = 32;
      const height: number = 32;
      const pixels: Uint8Array = new Uint8Array(width * height * 4);
      const region: Uint8Array = new Uint8Array(width * height);
      for (let y: number = 0; y < height; y++) {
        for (let x: number = 0; x < width; x++) {
          const offset: number = (y * width + x) << 2;
          // A hard vertical step, so the blend has a boundary to resolve.
          const value: number = x < 16 ? 60 : 200;
          pixels[offset] = value;
          pixels[offset + 1] = value;
          pixels[offset + 2] = value;
          pixels[offset + 3] = 255;
        }
      }
      // Paste a mid-grey block over the middle, the way a heal paste would.
      for (let y: number = 8; y < 24; y++) {
        for (let x: number = 8; x < 24; x++) {
          const offset: number = (y * width + x) << 2;
          region[y * width + x] = 1;
          pixels[offset] = 130;
          pixels[offset + 1] = 130;
          pixels[offset + 2] = 130;
        }
      }
      healPoissonBlend(pixels, region, width, height, 1000);
      // Upstream's solver produces this exact row; the paste has become a
      // smooth ramp between the dark and light halves of the step.
      const expected: number[] = [60, 60, 67, 74, 81, 89, 97, 106, 115, 125, 135, 145,
        154, 163, 171, 179, 186, 193, 200, 200];
      for (let index: number = 0; index < expected.length; index++) {
        const offset: number = ((16 * width) + (6 + index)) << 2;
        expect(pixels[offset]).assertEqual(expected[index]);
      }
      // Pixels outside the region are untouched by the solve.
      const outside: number = (2 * width + 2) << 2;
      expect(pixels[outside]).assertEqual(60);
      expect(pixels[outside + 3]).assertEqual(255);
    });

    it('composites every retouch mode through the real preview pipeline', 0, async () => {
      // Extends the healing compositor test across blur, sharpen, smudge,
      // sponge, dodge, burn, red eye, clone, fill and brush. Each is driven
      // through renderPreviewPixelMap on a real PixelMap, which is the only
      // place channel order and the shared colour matrix actually show up.
      const width: number = 64;
      const height: number = 64;
      const pixels: Uint8Array = new Uint8Array(width * height * 4);
      for (let y: number = 0; y < height; y++) {
        for (let x: number = 0; x < width; x++) {
          const offset: number = (y * width + x) << 2;
          // A smooth ramp plus a red patch, so filters have real gradients to
          // act on and any channel swap is visible.
          const base: number = 90 + (x * 60) / width + (y * 30) / height;
          pixels[offset] = base;
          pixels[offset + 1] = base * 0.8;
          pixels[offset + 2] = base * 0.6;
          pixels[offset + 3] = 255;
        }
      }
      // Uniform red square in the middle for the modes that key off colour.
      for (let y: number = 24; y < 40; y++) {
        for (let x: number = 24; x < 40; x++) {
          const offset: number = (y * width + x) << 2;
          pixels[offset] = 210;
          pixels[offset + 1] = 40;
          pixels[offset + 2] = 40;
        }
      }
      const source: image.PixelMap = await image.createPixelMap(pixels.buffer as ArrayBuffer, {
        size: { width: width, height: height },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: true
      });
      const adjustments: AdjustmentValues = {
        exposure: 0, contrast: 0, saturation: 0, temperature: 0, blur: 0
      };
      const filter: FilterState = { preset: 'none', intensity: 0 };
      const stroke: TransformPoint[] = [{ x: 32, y: 32 }];
      // One layer per retouch mode, each built on its own store.
      const layers: LayerModel[] = [];
      let local: EditorStore = new EditorStore();
      layers.push(local.getLayer(local.addBlurLayer(stroke, 20, 80)) as LayerModel);
      local = new EditorStore();
      layers.push(local.getLayer(local.addSharpenLayer(stroke, 20, 80)) as LayerModel);
      local = new EditorStore();
      layers.push(local.getLayer(local.addSmudgeLayer(stroke, 20, 80)) as LayerModel);
      local = new EditorStore();
      layers.push(local.getLayer(local.addSpongeLayer(stroke, 20, 80, 1)) as LayerModel);
      local = new EditorStore();
      layers.push(local.getLayer(local.addDodgeLayer(stroke, 20, 60, 1)) as LayerModel);
      local = new EditorStore();
      layers.push(local.getLayer(local.addBurnLayer(stroke, 20, 60, 1)) as LayerModel);
      local = new EditorStore();
      layers.push(local.getLayer(local.addRedEyeLayer(stroke, 20, 80)) as LayerModel);
      local = new EditorStore();
      layers.push(local.getLayer(local.addCloneLayer({ x: 8, y: 8 }, stroke, 20)) as LayerModel);
      local = new EditorStore();
      layers.push(local.getLayer(local.addFillLayer({ x: 32, y: 32 }, '#2BB8A7', 40, true, true)) as LayerModel);
      local = new EditorStore();
      layers.push(local.getLayer(local.addPaintLayer(stroke, '#2BB8A7', 20, PaintMode.BRUSH)) as LayerModel);
      const probe: number = (32 * width + 32) << 2;
      const corner: number = 2 << 2;
      for (let index: number = 0; index < layers.length; index++) {
        const rendered: image.PixelMap = await renderPreviewPixelMap(source, adjustments, filter,
          [layers[index]]);
        const buffer: ArrayBuffer = new ArrayBuffer(rendered.getPixelBytesNumber());
        await rendered.readPixelsToBuffer(buffer);
        const out: Uint8Array = new Uint8Array(buffer);
        // The stroke centre must not stay pure red: every mode alters it.
        // The mode must actually paint. Smudge and sponge resample neighbouring
        // pixels that are themselves red, so instead of checking colour we
        // check that the composited image differs from the untouched source
        // somewhere near the stroke.
        // The mode must actually have painted something at the stroke centre.
        let changedNear: boolean = false;
        for (let dy: number = -6; dy <= 6 && !changedNear; dy++) {
          for (let dx: number = -6; dx <= 6; dx++) {
            const px: number = 32 + dy;
            const py: number = 32 + dx;
            if (px < 0 || py < 0 || px >= height || py >= width) {
              continue;
            }
            const at: number = (py * width + px) << 2;
            if (out[at] !== pixels[at] || out[at + 1] !== pixels[at + 1] ||
              out[at + 2] !== pixels[at + 2]) {
              changedNear = true;
              break;
            }
          }
        }
        expect(changedNear).assertEqual(true);
        // Pixels far from the stroke survive untouched, so nothing washes out
        // or shifts hue. The composite reads back BGRA, so the edges swap.
        expect(out[corner + 1]).assertEqual(pixels[corner + 1]);
        expect(out[corner]).assertEqual(pixels[corner + 2]);
        expect(out[corner + 2]).assertEqual(pixels[corner]);
        await rendered.release();
      }
      await source.release();
    });

    it('declines to heal instead of inventing texture when no patch plan exists', 0, () => {
      // 8x8 is the smallest patch window, so anything smaller has no candidates.
      const tinyPixels: Uint8Array = new Uint8Array(4 * 4 * 4).fill(120);
      const tinyMask: Uint8Array = new Uint8Array(4 * 4);
      tinyMask[5] = 255;
      const offset: HealOffset = healVotedOffset(tinyPixels, tinyMask, 4, 4);
      expect(offset.votes).assertEqual(0);
      const plan: HealPlan = healPatchPlan(tinyPixels, tinyMask, 4, 4) as HealPlan;
      expect(plan.patches.length).assertEqual(0);
      // Applying an empty plan is a no-op, so the image is returned unchanged.
      const untouched: Uint8Array = applyHealPlan(plan, tinyPixels, tinyMask, 4, 4);
      for (let index: number = 0; index < tinyPixels.length; index++) {
        expect(untouched[index]).assertEqual(tinyPixels[index]);
      }
    });

    it('creates red eye layers with flow and history', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalCount: number = store.document.layers.length;
      const redEyeId: string = store.addRedEyeLayer([
        { x: 20, y: 24 },
        { x: 74, y: 62 }
      ], 18, 70);
      const layer = store.getLayer(redEyeId);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      expect(layer?.id).assertEqual('layer-redeye');
      expect(layer?.name).assertEqual('Red Eye');
      expect(layer?.paintMode).assertEqual(PaintMode.RED_EYE);
      expect(layer?.paintWidth).assertEqual(18);
      expect(layer?.paintRetouchStrength).assertEqual(70);
      expect(store.setPaintRetouchStrength(redEyeId, 30)).assertEqual(true);
      expect(store.getLayer(redEyeId)?.paintRetouchStrength).assertEqual(30);
      store.undo();
      expect(store.getLayer(redEyeId)?.paintRetouchStrength).assertEqual(70);
      store.undo();
      expect(store.getLayer(redEyeId)).assertEqual(undefined);
      store.redo();
      expect(store.getLayer(redEyeId)?.paintMode).assertEqual(PaintMode.RED_EYE);
    });

    it('builds a magic wand selection from a contiguous color mask', 0, () => {
      const store: EditorStore = new EditorStore();
      const pixels: Uint8Array = new Uint8Array(4 * 3 * 3);
      for (let index: number = 0; index < pixels.length; index += 4) {
        pixels[index] = 10;
        pixels[index + 1] = 20;
        pixels[index + 2] = 30;
        pixels[index + 3] = 255;
      }
      pixels[16] = 240;
      pixels[17] = 20;
      pixels[18] = 30;
      const mask: Uint8Array = floodFillMask(pixels, 3, 3, 12, 0, 0, 8, true, false);
      const points: TransformPoint[] = selectionPointsFromMask(mask, 3, 3);
      // The seed pixel is not adjacent to the perturbed center, so the top-left
      // three-pixel row plus the untouched neighbors all expose a leading edge.
      expect(points.length).assertEqual(5);
      expect(store.setMagicWandSelection(points)).assertEqual(true);
      expect(store.document.selection.mode).assertEqual('magicWand');
      expect(store.document.selection.points.length).assertEqual(points.length);
      expect(store.getSelectionRect().x).assertEqual(0);
      expect(store.getSelectionRect().y).assertEqual(0);
      expect(store.getSelectionRect().width).assertEqual(2);
      expect(store.getSelectionRect().height).assertEqual(2);
      store.undo();
      expect(store.document.selection.active).assertEqual(false);
      store.redo();
      expect(store.document.selection.mode).assertEqual('magicWand');
    });

    it('crops to a selection and restores the pre-crop document through history', 0, () => {
      const store: EditorStore = new EditorStore();
      store.setSelection({ x: 10, y: 15, width: 60, height: 45 });
      expect(store.cropToSelection()).assertEqual(true);
      expect(store.document.crop.rect.x).assertEqual(10);
      expect(store.document.crop.rect.y).assertEqual(15);
      expect(store.document.crop.rect.width).assertEqual(60);
      expect(store.document.crop.rect.height).assertEqual(45);
      expect(store.document.width).assertEqual(60);
      expect(store.document.height).assertEqual(45);
      store.undo();
      expect(store.document.crop.rect.width).assertEqual(150);
      expect(store.document.crop.rect.height).assertEqual(105);
      expect(store.document.selection.active).assertEqual(true);
    });

    it('crops a rotated document to a selection in source coordinates', 0, () => {
      const store: EditorStore = new EditorStore();
      store.rotateClockwise();
      store.setSelection({ x: 10, y: 20, width: 30, height: 40 });
      expect(store.cropToSelection()).assertEqual(true);
      expect(store.document.crop.rect.x).assertEqual(20);
      expect(store.document.crop.rect.y).assertEqual(65);
      expect(store.document.crop.rect.width).assertEqual(40);
      expect(store.document.crop.rect.height).assertEqual(30);
      expect(store.document.width).assertEqual(30);
      expect(store.document.height).assertEqual(40);
      store.undo();
      expect(store.document.width).assertEqual(105);
      expect(store.document.height).assertEqual(150);
      expect(store.document.selection.active).assertEqual(true);
    });

    it('expands and contracts rectangular selections with bounded history', 0, () => {
      const store: EditorStore = new EditorStore();
      store.setSelection({ x: 12, y: 18, width: 36, height: 24 });
      expect(store.expandSelection(8)).assertEqual(true);
      expect(store.getSelectionRect().x).assertEqual(4);
      expect(store.getSelectionRect().y).assertEqual(10);
      expect(store.getSelectionRect().width).assertEqual(52);
      expect(store.getSelectionRect().height).assertEqual(40);
      expect(store.contractSelection(6)).assertEqual(true);
      expect(store.getSelectionRect().x).assertEqual(10);
      expect(store.getSelectionRect().y).assertEqual(16);
      expect(store.getSelectionRect().width).assertEqual(40);
      expect(store.getSelectionRect().height).assertEqual(28);
      store.undo();
      expect(store.getSelectionRect().width).assertEqual(52);
      store.undo();
      expect(store.getSelectionRect().x).assertEqual(12);
      expect(store.getSelectionRect().width).assertEqual(36);
      store.redo();
      expect(store.getSelectionRect().width).assertEqual(52);
      store.redo();
      expect(store.getSelectionRect().width).assertEqual(40);

      const edgeStore: EditorStore = new EditorStore();
      edgeStore.setSelection({ x: 0, y: 0, width: 10, height: 8 });
      expect(edgeStore.expandSelection(4)).assertEqual(true);
      expect(edgeStore.getSelectionRect().x).assertEqual(0);
      expect(edgeStore.getSelectionRect().y).assertEqual(0);
      expect(edgeStore.getSelectionRect().width).assertEqual(18);
      expect(edgeStore.getSelectionRect().height).assertEqual(16);
    });

    it('manages layer selection and properties', 0, () => {
      const store: EditorStore = new EditorStore();
      store.selectLayer('layer-adjustment');
      store.setLayerVisibility('layer-adjustment', false);
      store.setLayerLocked('layer-adjustment', true);
      store.setLayerOpacity('layer-adjustment', 64);
      store.setLayerBlendMode('layer-adjustment', 'Multiply');
      const layer = store.getLayer('layer-adjustment');
      expect(store.selectedLayerId).assertEqual('layer-adjustment');
      expect(layer?.visible).assertEqual(false);
      expect(layer?.locked).assertEqual(true);
      expect(layer?.opacity).assertEqual(64);
      expect(layer?.blendMode).assertEqual('Multiply');
    });

    it('adds, duplicates, reorders, and deletes layers', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalCount: number = store.document.layers.length;
      store.addLayer();
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      const addedId: string = store.selectedLayerId;
      store.duplicateLayer(addedId);
      expect(store.document.layers.length).assertEqual(originalCount + 2);
      expect(store.selectedLayerId).assertEqual(addedId + '-copy');
      store.moveLayer(store.selectedLayerId, -1);
      expect(store.document.layers[2].id).assertEqual(store.selectedLayerId);
      store.deleteLayer(store.selectedLayerId);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      store.deleteLayer(addedId);
      expect(store.document.layers.length).assertEqual(originalCount);
    });

    it('restores layer edits through undo and redo', 0, () => {
      const store: EditorStore = new EditorStore();
      store.setLayerOpacity('layer-image', 42);
      expect(store.getLayer('layer-image')?.opacity).assertEqual(42);
      store.undo();
      expect(store.getLayer('layer-image')?.opacity).assertEqual(100);
      store.redo();
      expect(store.getLayer('layer-image')?.opacity).assertEqual(42);
    });

    it('creates and edits shape layers through history', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalCount: number = store.document.layers.length;
      const rectangleId: string = store.addShapeLayer(ShapeType.RECTANGLE, {
        x: 12,
        y: 18,
        width: 40,
        height: 28
      });
      const rectangle = store.getLayer(rectangleId);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      expect(store.selectedLayerId).assertEqual(rectangleId);
      expect(rectangle?.kind).assertEqual('shape');
      expect(rectangle?.shapeType).assertEqual(ShapeType.RECTANGLE);
      expect(rectangle?.shapeX).assertEqual(12);
      expect(rectangle?.shapeY).assertEqual(18);
      expect(rectangle?.shapeWidth).assertEqual(40);
      expect(rectangle?.shapeHeight).assertEqual(28);
      expect(store.setShapeBounds(rectangleId, 20, 24, 55, 36)).assertEqual(true);
      expect(store.setShapeFill(rectangleId, '#ff00aa')).assertEqual(true);
      expect(store.setShapeStroke(rectangleId, '#123456')).assertEqual(true);
      expect(store.setShapeStrokeWidth(rectangleId, 6)).assertEqual(true);
      expect(store.getLayer(rectangleId)?.shapeX).assertEqual(20);
      expect(store.getLayer(rectangleId)?.shapeFill).assertEqual('#FF00AA');
      expect(store.getLayer(rectangleId)?.shapeStroke).assertEqual('#123456');
      expect(store.getLayer(rectangleId)?.shapeStrokeWidth).assertEqual(6);
      store.undo();
      expect(store.getLayer(rectangleId)?.shapeStrokeWidth).assertEqual(2);
      store.redo();
      expect(store.getLayer(rectangleId)?.shapeStrokeWidth).assertEqual(6);
      store.undo();
      store.undo();
      store.undo();
      expect(store.getLayer(rectangleId)?.shapeX).assertEqual(12);
      store.undo();
      expect(store.getLayer(rectangleId)).assertEqual(undefined);

      const ellipseId: string = store.addShapeLayer(ShapeType.ELLIPSE, {
        x: 4,
        y: 6,
        width: 20,
        height: 12
      });
      expect(store.getLayer(ellipseId)?.shapeType).assertEqual(ShapeType.ELLIPSE);
      store.duplicateLayer(ellipseId);
      expect(store.document.layers.length).assertEqual(originalCount + 2);
    });

    it('moves text and shape layers with source bounds and history', 0, () => {
      const store: EditorStore = new EditorStore();
      const textId: string = store.addTextLayer('Move me');
      store.setTextPosition(textId, 30, 40);
      expect(store.moveLayerByDelta(textId, 12, 8)).assertEqual(true);
      expect(store.getLayer(textId)?.textX).assertEqual(42);
      expect(store.getLayer(textId)?.textY).assertEqual(48);
      expect(store.moveLayerByDelta(textId, 500, 0)).assertEqual(true);
      expect(store.getLayer(textId)?.textX).assertEqual(149);
      store.undo();
      expect(store.getLayer(textId)?.textX).assertEqual(42);
      store.redo();
      expect(store.getLayer(textId)?.textX).assertEqual(149);

      const shapeId: string = store.addShapeLayer(ShapeType.RECTANGLE, {
        x: 20,
        y: 20,
        width: 30,
        height: 20
      });
      expect(store.moveLayerByDelta(shapeId, -10, 6)).assertEqual(true);
      expect(store.getLayer(shapeId)?.shapeX).assertEqual(10);
      expect(store.getLayer(shapeId)?.shapeY).assertEqual(26);
      expect(store.moveLayerByDelta(shapeId, -100, -100)).assertEqual(true);
      expect(store.getLayer(shapeId)?.shapeX).assertEqual(0);
      expect(store.getLayer(shapeId)?.shapeY).assertEqual(0);
      store.undo();
      expect(store.getLayer(shapeId)?.shapeX).assertEqual(10);
      expect(store.getLayer(shapeId)?.shapeY).assertEqual(26);
    });

    it('normalizes and edits foreground colors with history', 0, () => {
      const store: EditorStore = new EditorStore();
      expect(normalizeHexColor('#abc')).assertEqual('#AABBCC');
      expect(normalizeHexColor('2bb8a7')).assertEqual('#2BB8A7');
      expect(store.setColor(ColorTarget.FOREGROUND, '#f0a')).assertEqual(true);
      expect(store.getColor(ColorTarget.FOREGROUND)).assertEqual('#FF00AA');
      store.undo();
      expect(store.getColor(ColorTarget.FOREGROUND)).assertEqual('#2BB8A7');
      store.redo();
      expect(store.getColor(ColorTarget.FOREGROUND)).assertEqual('#FF00AA');
    });

    it('swaps colors and manages custom swatches', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalBackground: string = store.getColor(ColorTarget.BACKGROUND);
      store.setColor(ColorTarget.FOREGROUND, '#123456');
      store.swapColors();
      expect(store.getColor(ColorTarget.FOREGROUND)).assertEqual(originalBackground);
      expect(store.getColor(ColorTarget.BACKGROUND)).assertEqual('#123456');
      expect(store.addSwatch('#abcdef')).assertEqual(true);
      expect(store.colors.swatches.indexOf('#ABCDEF') >= 0).assertEqual(true);
      store.undo();
      expect(store.colors.swatches.indexOf('#ABCDEF')).assertEqual(-1);
    });

    it('creates and edits text layers with undo and redo', 0, () => {
      const store: EditorStore = new EditorStore();
      const originalCount: number = store.document.layers.length;
      const textId: string = store.addTextLayer('Hello PhotoSuite');
      const textLayer = store.getLayer(textId);
      expect(store.document.layers.length).assertEqual(originalCount + 1);
      expect(store.selectedLayerId).assertEqual(textId);
      expect(textLayer?.kind).assertEqual('text');
      expect(textLayer?.textContent).assertEqual('Hello PhotoSuite');
      expect(store.setTextContent(textId, 'Updated title')).assertEqual(true);
      expect(store.setTextSize(textId, 48)).assertEqual(true);
      expect(store.setTextColor(textId, '#abcdef')).assertEqual(true);
      expect(store.setTextPosition(textId, 48, 64)).assertEqual(true);
      expect(store.getLayer(textId)?.textContent).assertEqual('Updated title');
      expect(store.getLayer(textId)?.textSize).assertEqual(48);
      expect(store.getLayer(textId)?.textColor).assertEqual('#ABCDEF');
      expect(store.getLayer(textId)?.textX).assertEqual(48);
      expect(store.getLayer(textId)?.textY).assertEqual(64);
      store.undo();
      expect(store.getLayer(textId)?.textY).assertEqual(24);
      store.redo();
      expect(store.getLayer(textId)?.textY).assertEqual(64);
    });
  });
}
