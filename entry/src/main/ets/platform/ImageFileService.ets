import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AdjustmentValues,
  CropRect,
  ExportFormat,
  FilterState,
  LayerModel,
  OpenDocument,
  PaintGradientStyle,
  PaintMode,
  SelectionRect,
  ShapeType,
  TransformPoint,
  TransformState
} from '../model/EditorTypes';
import {
  applyRgbaFilter,
  applyHealPlan,
  dodgeBurnExposureFlow,
  dodgeBurnToneValue,
  documentFilterMatrix,
  floodFillMask,
  HealPatch,
  HealPlan,
  healPatchPlan,
  healPoissonBlend,
  HslColor,
  normalizeTransform,
  redEyeCorrection
} from '../model/EditorMath';

const DOMAIN: number = 0x0A25;
/** Poisson sweep count for the heal blend, matching upstream's fill budget. */
const HEAL_POISSON_ITERATIONS: number = 200;
const TAG: string = 'OpenPhotoSuiteFiles';
const MAX_PREVIEW_EDGE: number = 4096;
const FILTERS: string[] = [
  'Images (.png,.jpg,.jpeg,.webp,.gif,.bmp)|.png,.jpg,.jpeg,.webp,.gif,.bmp',
  'Layered documents (.psd,.psb)|.psd,.psb',
  'Vector documents (.svg,.ai,.eps,.pdf)|.svg,.ai,.eps,.pdf',
  'Camera RAW (.dng,.cr2,.cr3,.nef,.arw,.raf)|.dng,.cr2,.cr3,.nef,.arw,.raf'
];

function uriName(uri: string, fallback: string): string {
  const cleanUri: string = uri.split('?')[0];
  const slash: number = cleanUri.lastIndexOf('/');
  const rawName: string = slash >= 0 ? cleanUri.substring(slash + 1) : cleanUri;
  try {
    return decodeURIComponent(rawName);
  } catch (error) {
    return rawName.length > 0 ? rawName : fallback;
  }
}

function baseName(name: string): string {
  const dot: number = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

function safeExportName(name: string): string {
  const cleaned: string = baseName(name).replace(/[^A-Za-z0-9_-]+/g, '-');
  return cleaned.length > 0 ? cleaned : 'photosuite-export';
}

async function closeFile(file: fileIo.File | undefined): Promise<void> {
  if (file === undefined) {
    return;
  }
  try {
    await fileIo.close(file);
  } catch (error) {
  }
}

function colorToArgb(value: string, opacity: number): number {
  const hex: string = value.substring(1);
  const red: number = parseInt(hex.substring(0, 2), 16);
  const green: number = parseInt(hex.substring(2, 4), 16);
  const blue: number = parseInt(hex.substring(4, 6), 16);
  const alpha: number = Math.max(0, Math.min(255, Math.round(255 * opacity / 100)));
  return (alpha << 24) | (red << 16) | (green << 8) | blue;
}

function textBaseline(textY: number, fontSize: number): number {
  return Math.round(textY + fontSize * 0.82);
}

async function cloneEditablePixelMap(pixelMap: image.PixelMap): Promise<image.PixelMap> {
  const info: image.ImageInfo = await pixelMap.getImageInfo();
  const buffer: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
  await pixelMap.readPixelsToBuffer(buffer);
  return image.createPixelMap(buffer, {
    size: info.size,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    editable: true
  });
}

async function verifyExportedDocument(uri: string): Promise<void> {
  let destination: fileIo.File | undefined = undefined;
  let source: image.ImageSource | undefined = undefined;
  let decoded: image.PixelMap | undefined = undefined;
  try {
    destination = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    const fileInfo: fileIo.Stat = await fileIo.stat(destination.fd);
    const bytes: ArrayBuffer = new ArrayBuffer(fileInfo.size);
    const readBytes: number = await fileIo.read(destination.fd, bytes, {
      offset: 0,
      length: fileInfo.size
    });
    if (readBytes !== fileInfo.size) {
      throw new Error('Short exported file read');
    }
    source = image.createImageSource(bytes);
    const info: image.ImageInfo = await source.getImageInfo();
    decoded = await source.createPixelMap({
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
    const decodedInfo: image.ImageInfo = await decoded.getImageInfo();
    const buffer: ArrayBuffer = new ArrayBuffer(decoded.getPixelBytesNumber());
    await decoded.readPixelsToBuffer(buffer);
    const pixels: Uint8Array = new Uint8Array(buffer);
    let checksum: number = 0;
    for (let index: number = 0; index < pixels.length; index += 97) {
      checksum = (checksum * 33 + pixels[index]) >>> 0;
    }
    hilog.info(DOMAIN, TAG,
      'export file bytes=%{public}d decoded width=%{public}d height=%{public}d pixelBytes=%{public}d checksum=%{public}d',
      fileInfo.size, decodedInfo.size.width, decodedInfo.size.height, pixels.byteLength, checksum);
  } finally {
    if (decoded !== undefined) {
      try {
        await decoded.release();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'decoded export PixelMap release failed');
      }
    }
    if (source !== undefined) {
      try {
        await source.release();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'export verification source release failed');
      }
    }
    await closeFile(destination);
    if (source === undefined) {
      hilog.warn(DOMAIN, TAG, 'export verification source unavailable');
    }
  }
}

function drawTextLayers(pixelMap: image.PixelMap, layers: LayerModel[]): void {
  const canvas: drawing.Canvas = new drawing.Canvas(pixelMap);
  for (const layer of layers) {
    if (layer.kind !== 'text' || !layer.visible || layer.textContent.length === 0 || layer.opacity <= 0) {
      continue;
    }
    const font: drawing.Font = new drawing.Font();
    font.setSize(layer.textSize);
    font.enableSubpixel(true);
    font.enableEmbolden(true);
    const brush: drawing.Brush = new drawing.Brush();
    brush.setColor(colorToArgb(layer.textColor, layer.opacity));
    brush.setAntiAlias(true);
    canvas.attachBrush(brush);
    const lines: string[] = layer.textContent.split('\n');
    for (let lineIndex: number = 0; lineIndex < lines.length; lineIndex++) {
      const blob: drawing.TextBlob = drawing.TextBlob.makeFromString(lines[lineIndex], font);
      const baseline: number = textBaseline(layer.textY + lineIndex * layer.textSize * 1.2, layer.textSize);
      canvas.drawTextBlob(blob, layer.textX, baseline);
    }
    canvas.detachBrush();
  }
}

interface PaintSurface {
  layer: LayerModel;
  pixelMap: image.PixelMap;
}

interface BlurPixel {
  red: number;
  green: number;
  blue: number;
}

function distanceToSegment(x: number, y: number, startX: number, startY: number,
  endX: number, endY: number): number {
  const deltaX: number = endX - startX;
  const deltaY: number = endY - startY;
  const lengthSquared: number = deltaX * deltaX + deltaY * deltaY;
  let ratio: number = 0;
  if (lengthSquared > 0) {
    ratio = Math.max(0, Math.min(1, ((x - startX) * deltaX + (y - startY) * deltaY) /
      lengthSquared));
  }
  const nearestX: number = startX + ratio * deltaX;
  const nearestY: number = startY + ratio * deltaY;
  return Math.sqrt((x - nearestX) * (x - nearestX) + (y - nearestY) * (y - nearestY));
}

function distanceToPaintStroke(x: number, y: number, layer: LayerModel): number {
  if (layer.paintPoints.length === 0) {
    return Number.MAX_VALUE;
  }
  if (layer.paintPoints.length === 1) {
    const point = layer.paintPoints[0];
    return Math.sqrt((x - point.x) * (x - point.x) + (y - point.y) * (y - point.y));
  }
  let nearest: number = Number.MAX_VALUE;
  for (let index: number = 1; index < layer.paintPoints.length; index++) {
    const start = layer.paintPoints[index - 1];
    const end = layer.paintPoints[index];
    nearest = Math.min(nearest, distanceToSegment(x, y, start.x, start.y, end.x, end.y));
  }
  return nearest;
}

/**
 * True when a source pixel may be painted for this layer.
 *
 * `paintClip` is the fast bounds reject that every paint mode already used.
 * `paintClipMask`, when present, carries per-pixel source-space coverage for
 * lasso and magic wand selection, so a stroke cannot spill into the
 * unselected region inside those bounds. An empty mask means the selection is
 * a plain rectangle (or there is no selection), so bounds alone is correct.
 *
 * The mask is indexed in source space, so callers pass the source width that
 * produced it rather than relying on the layer.
 */
function isPixelInsidePaintClip(layer: LayerModel, x: number, y: number): boolean {
  const clip: SelectionRect = layer.paintClip;
  if (x < clip.x || x >= clip.x + clip.width || y < clip.y || y >= clip.y + clip.height) {
    return false;
  }
  const mask: number[] = layer.paintClipMask;
  if (mask.length === 0) {
    return true;
  }
  const index: number = y * layer.paintClipMaskWidth + x;
  if (index < 0 || index >= mask.length) {
    return false;
  }
  return mask[index] !== 0;
}


/**
 * Build a clip region for a canvas-drawn layer (gradient today) from the
 * layer's per-pixel clip mask. Each horizontal run of selected pixels is
 * unioned into the region, which reproduces an arbitrary lasso or wand
 * selection exactly. Returns undefined when the layer has no mask, so the
 * caller keeps using its rectangular clip.
 */
function paintClipRegion(layer: LayerModel, sourceWidth: number): drawing.Region | undefined {
  const mask: number[] = layer.paintClipMask;
  if (mask.length === 0) {
    return undefined;
  }
  let region: drawing.Region | undefined = undefined;
  for (let y: number = 0; y * sourceWidth < mask.length; y++) {
    let runStart: number = -1;
    for (let x: number = 0; x <= sourceWidth; x++) {
      const index: number = y * sourceWidth + x;
      const selected: boolean = index < mask.length && mask[index] !== 0;
      if (selected && runStart < 0) {
        runStart = x;
      } else if (!selected && runStart >= 0) {
        const run: drawing.Region = new drawing.Region(runStart, y, x, y + 1);
        if (region === undefined) {
          region = run;
        } else {
          region.op(run, drawing.RegionOp.UNION);
        }
        runStart = -1;
      }
    }
  }
  return region;
}

function blurredReferencePixel(reference: Uint8Array, width: number, height: number, stride: number,
  x: number, y: number, radius: number): BlurPixel {
  let red: number = 0;
  let green: number = 0;
  let blue: number = 0;
  let count: number = 0;
  const left: number = Math.max(0, x - radius);
  const right: number = Math.min(width - 1, x + radius);
  const top: number = Math.max(0, y - radius);
  const bottom: number = Math.min(height - 1, y + radius);
  for (let sampleY: number = top; sampleY <= bottom; sampleY++) {
    for (let sampleX: number = left; sampleX <= right; sampleX++) {
      const index: number = sampleY * stride + sampleX * 4;
      red += reference[index];
      green += reference[index + 1];
      blue += reference[index + 2];
      count += 1;
    }
  }
  return {
    red: Math.round(red / Math.max(1, count)),
    green: Math.round(green / Math.max(1, count)),
    blue: Math.round(blue / Math.max(1, count))
  };
}

async function createBlurSurface(layer: LayerModel, reference: image.PixelMap,
  sourceInfo: image.ImageInfo): Promise<image.PixelMap> {
  const width: number = sourceInfo.size.width;
  const height: number = sourceInfo.size.height;
  const output: Uint8Array = new Uint8Array(width * height * 4);
  if (layer.paintPoints.length === 0 || layer.paintRetouchStrength <= 0) {
    return image.createPixelMap(output.buffer as ArrayBuffer, {
      size: sourceInfo.size,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    });
  }
  const referenceBuffer: ArrayBuffer = new ArrayBuffer(reference.getPixelBytesNumber());
  await reference.readPixelsToBuffer(referenceBuffer);
  const referencePixels: Uint8Array = new Uint8Array(referenceBuffer);
  const brushRadius: number = Math.max(0.5, layer.paintWidth / 2);
  const strength: number = Math.max(1, Math.min(100, layer.paintRetouchStrength)) / 100;
  const layerOpacity: number = Math.max(0, Math.min(100, layer.opacity)) / 100;
  const blurRadius: number = Math.max(1, Math.min(24,
    Math.round(layer.paintWidth * strength)));
  let minX: number = Number.MAX_VALUE;
  let minY: number = Number.MAX_VALUE;
  let maxX: number = Number.MIN_VALUE;
  let maxY: number = Number.MIN_VALUE;
  for (const point of layer.paintPoints) {
    minX = Math.min(minX, point.x);
    minY = Math.min(minY, point.y);
    maxX = Math.max(maxX, point.x);
    maxY = Math.max(maxY, point.y);
  }
  const clip: SelectionRect = layer.paintClip;
  const left: number = Math.max(clip.x, Math.floor(minX - brushRadius - blurRadius));
  const top: number = Math.max(clip.y, Math.floor(minY - brushRadius - blurRadius));
  const right: number = Math.min(clip.x + clip.width - 1,
    Math.ceil(maxX + brushRadius + blurRadius));
  const bottom: number = Math.min(clip.y + clip.height - 1,
    Math.ceil(maxY + brushRadius + blurRadius));
  if (left <= right && top <= bottom) {
    for (let y: number = top; y <= bottom; y++) {
      for (let x: number = left; x <= right; x++) {
        if (!isPixelInsidePaintClip(layer, x, y)) {
          continue;
        }
        const distance: number = distanceToPaintStroke(x, y, layer);
        if (distance > brushRadius) {
          continue;
        }
        const sourceIndex: number = y * sourceInfo.stride + x * 4;
        if (sourceIndex < 0 || sourceIndex + 3 >= referencePixels.length) {
          continue;
        }
        const edge: number = Math.max(0, Math.min(1, brushRadius - distance));
        const mask: number = Math.round(255 * edge * layerOpacity);
        if (mask === 0) {
          continue;
        }
        const blurred: BlurPixel = blurredReferencePixel(referencePixels, width, height,
          sourceInfo.stride, x, y, blurRadius);
        const outputIndex: number = (y * width + x) * 4;
        const red: number = Math.round(referencePixels[sourceIndex] * (1 - strength) +
          blurred.red * strength);
        const green: number = Math.round(referencePixels[sourceIndex + 1] * (1 - strength) +
          blurred.green * strength);
        const blue: number = Math.round(referencePixels[sourceIndex + 2] * (1 - strength) +
          blurred.blue * strength);
        output[outputIndex] = blue;
        output[outputIndex + 1] = green;
        output[outputIndex + 2] = red;
        output[outputIndex + 3] = Math.round(referencePixels[sourceIndex + 3] * mask / 255);
      }
    }
  }
  return image.createPixelMap(output.buffer as ArrayBuffer, {
    size: sourceInfo.size,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    editable: true
  });
}

function sharpenedReferencePixel(reference: Uint8Array, width: number, height: number, stride: number,
  x: number, y: number): BlurPixel {
  const centerX: number = Math.max(0, Math.min(width - 1, x));
  const centerY: number = Math.max(0, Math.min(height - 1, y));
  const centerIndex: number = centerY * stride + centerX * 4;
  const centerRed: number = reference[centerIndex];
  const centerGreen: number = reference[centerIndex + 1];
  const centerBlue: number = reference[centerIndex + 2];
  let neighborRed: number = 0;
  let neighborGreen: number = 0;
  let neighborBlue: number = 0;
  for (let offsetY: number = -1; offsetY <= 1; offsetY++) {
    for (let offsetX: number = -1; offsetX <= 1; offsetX++) {
      if (offsetX === 0 && offsetY === 0) {
        continue;
      }
      const sampleX: number = Math.max(0, Math.min(width - 1, centerX + offsetX));
      const sampleY: number = Math.max(0, Math.min(height - 1, centerY + offsetY));
      const sampleIndex: number = sampleY * stride + sampleX * 4;
      neighborRed += reference[sampleIndex];
      neighborGreen += reference[sampleIndex + 1];
      neighborBlue += reference[sampleIndex + 2];
    }
  }
  return {
    red: Math.max(0, Math.min(255, Math.round((centerRed * 25 - neighborRed) / 17))),
    green: Math.max(0, Math.min(255, Math.round((centerGreen * 25 - neighborGreen) / 17))),
    blue: Math.max(0, Math.min(255, Math.round((centerBlue * 25 - neighborBlue) / 17)))
  };
}

function smudgeDirectionAt(x: number, y: number, layer: LayerModel): TransformPoint {
  if (layer.paintPoints.length < 2) {
    return { x: 1, y: 0 };
  }
  let nearestDistance: number = Number.MAX_VALUE;
  let directionX: number = 1;
  let directionY: number = 0;
  for (let index: number = 1; index < layer.paintPoints.length; index++) {
    const start: TransformPoint = layer.paintPoints[index - 1];
    const end: TransformPoint = layer.paintPoints[index];
    const deltaX: number = end.x - start.x;
    const deltaY: number = end.y - start.y;
    const lengthSquared: number = deltaX * deltaX + deltaY * deltaY;
    let ratio: number = 0;
    if (lengthSquared > 0) {
      ratio = Math.max(0, Math.min(1, ((x - start.x) * deltaX + (y - start.y) * deltaY) /
        lengthSquared));
    }
    const nearestX: number = start.x + ratio * deltaX;
    const nearestY: number = start.y + ratio * deltaY;
    const distance: number = Math.sqrt((x - nearestX) * (x - nearestX) +
      (y - nearestY) * (y - nearestY));
    if (distance < nearestDistance) {
      nearestDistance = distance;
      directionX = deltaX;
      directionY = deltaY;
    }
  }
  const length: number = Math.sqrt(directionX * directionX + directionY * directionY);
  if (length < 0.001) {
    return { x: 1, y: 0 };
  }
  return { x: directionX / length, y: directionY / length };
}

function smudgedReferencePixel(reference: Uint8Array, width: number, height: number, stride: number,
  x: number, y: number, directionX: number, directionY: number, distance: number): BlurPixel {
  let red: number = 0;
  let green: number = 0;
  let blue: number = 0;
  const samples: number = 3;
  for (let sample: number = 0; sample < samples; sample++) {
    const distanceFactor: number = sample / (samples - 1);
    const sampleX: number = Math.max(0, Math.min(width - 1,
      Math.round(x - directionX * distance * distanceFactor)));
    const sampleY: number = Math.max(0, Math.min(height - 1,
      Math.round(y - directionY * distance * distanceFactor)));
    const index: number = sampleY * stride + sampleX * 4;
    red += reference[index];
    green += reference[index + 1];
    blue += reference[index + 2];
  }
  return {
    red: Math.round(red / samples),
    green: Math.round(green / samples),
    blue: Math.round(blue / samples)
  };
}

async function createSharpenSurface(layer: LayerModel, reference: image.PixelMap,
  sourceInfo: image.ImageInfo): Promise<image.PixelMap> {
  const width: number = sourceInfo.size.width;
  const height: number = sourceInfo.size.height;
  const output: Uint8Array = new Uint8Array(width * height * 4);
  if (layer.paintPoints.length === 0 || layer.paintRetouchStrength <= 0) {
    return image.createPixelMap(output.buffer as ArrayBuffer, {
      size: sourceInfo.size,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    });
  }
  const referenceBuffer: ArrayBuffer = new ArrayBuffer(reference.getPixelBytesNumber());
  await reference.readPixelsToBuffer(referenceBuffer);
  const referencePixels: Uint8Array = new Uint8Array(referenceBuffer);
  const brushRadius: number = Math.max(0.5, layer.paintWidth / 2);
  const strength: number = Math.max(1, Math.min(100, layer.paintRetouchStrength)) / 100;
  const layerOpacity: number = Math.max(0, Math.min(100, layer.opacity)) / 100;
  let minX: number = Number.MAX_VALUE;
  let minY: number = Number.MAX_VALUE;
  let maxX: number = Number.MIN_VALUE;
  let maxY: number = Number.MIN_VALUE;
  for (const point of layer.paintPoints) {
    minX = Math.min(minX, point.x);
    minY = Math.min(minY, point.y);
    maxX = Math.max(maxX, point.x);
    maxY = Math.max(maxY, point.y);
  }
  const clip: SelectionRect = layer.paintClip;
  const left: number = Math.max(clip.x, Math.floor(minX - brushRadius));
  const top: number = Math.max(clip.y, Math.floor(minY - brushRadius));
  const right: number = Math.min(clip.x + clip.width - 1, Math.ceil(maxX + brushRadius));
  const bottom: number = Math.min(clip.y + clip.height - 1, Math.ceil(maxY + brushRadius));
  if (left <= right && top <= bottom) {
    for (let y: number = top; y <= bottom; y++) {
      for (let x: number = left; x <= right; x++) {
        if (!isPixelInsidePaintClip(layer, x, y)) {
          continue;
        }
        const distance: number = distanceToPaintStroke(x, y, layer);
        if (distance > brushRadius) {
          continue;
        }
        const sourceIndex: number = y * sourceInfo.stride + x * 4;
        if (sourceIndex < 0 || sourceIndex + 3 >= referencePixels.length) {
          continue;
        }
        const edge: number = Math.max(0, Math.min(1, brushRadius - distance));
        const mask: number = Math.round(255 * edge * layerOpacity);
        if (mask === 0) {
          continue;
        }
        const sharpened: BlurPixel = sharpenedReferencePixel(referencePixels, width, height,
          sourceInfo.stride, x, y);
        const outputIndex: number = (y * width + x) * 4;
        const red: number = Math.round(referencePixels[sourceIndex] * (1 - strength) +
          sharpened.red * strength);
        const green: number = Math.round(referencePixels[sourceIndex + 1] * (1 - strength) +
          sharpened.green * strength);
        const blue: number = Math.round(referencePixels[sourceIndex + 2] * (1 - strength) +
          sharpened.blue * strength);
        output[outputIndex] = blue;
        output[outputIndex + 1] = green;
        output[outputIndex + 2] = red;
        output[outputIndex + 3] = Math.round(referencePixels[sourceIndex + 3] * mask / 255);
      }
    }
  }
  return image.createPixelMap(output.buffer as ArrayBuffer, {
    size: sourceInfo.size,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    editable: true
  });
}

async function createSmudgeSurface(layer: LayerModel, reference: image.PixelMap,
  sourceInfo: image.ImageInfo): Promise<image.PixelMap> {
  const width: number = sourceInfo.size.width;
  const height: number = sourceInfo.size.height;
  const output: Uint8Array = new Uint8Array(width * height * 4);
  if (layer.paintPoints.length === 0 || layer.paintRetouchStrength <= 0) {
    return image.createPixelMap(output.buffer as ArrayBuffer, {
      size: sourceInfo.size,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    });
  }
  const referenceBuffer: ArrayBuffer = new ArrayBuffer(reference.getPixelBytesNumber());
  await reference.readPixelsToBuffer(referenceBuffer);
  const referencePixels: Uint8Array = new Uint8Array(referenceBuffer);
  const brushRadius: number = Math.max(0.5, layer.paintWidth / 2);
  const strength: number = Math.max(1, Math.min(100, layer.paintRetouchStrength)) / 100;
  const layerOpacity: number = Math.max(0, Math.min(100, layer.opacity)) / 100;
  const smearDistance: number = Math.max(1, Math.min(12,
    Math.round(brushRadius * strength)));
  let minX: number = Number.MAX_VALUE;
  let minY: number = Number.MAX_VALUE;
  let maxX: number = Number.MIN_VALUE;
  let maxY: number = Number.MIN_VALUE;
  for (const point of layer.paintPoints) {
    minX = Math.min(minX, point.x);
    minY = Math.min(minY, point.y);
    maxX = Math.max(maxX, point.x);
    maxY = Math.max(maxY, point.y);
  }
  const clip: SelectionRect = layer.paintClip;
  const left: number = Math.max(clip.x, Math.floor(minX - brushRadius));
  const top: number = Math.max(clip.y, Math.floor(minY - brushRadius));
  const right: number = Math.min(clip.x + clip.width - 1, Math.ceil(maxX + brushRadius));
  const bottom: number = Math.min(clip.y + clip.height - 1, Math.ceil(maxY + brushRadius));
  if (left <= right && top <= bottom) {
    for (let y: number = top; y <= bottom; y++) {
      for (let x: number = left; x <= right; x++) {
        if (!isPixelInsidePaintClip(layer, x, y)) {
          continue;
        }
        const distance: number = distanceToPaintStroke(x, y, layer);
        if (distance > brushRadius) {
          continue;
        }
        const sourceIndex: number = y * sourceInfo.stride + x * 4;
        if (sourceIndex < 0 || sourceIndex + 3 >= referencePixels.length) {
          continue;
        }
        const direction: TransformPoint = smudgeDirectionAt(x, y, layer);
        const smudged: BlurPixel = smudgedReferencePixel(referencePixels, width, height,
          sourceInfo.stride, x, y, direction.x, direction.y, smearDistance);
        const edge: number = Math.max(0, Math.min(1, brushRadius - distance));
        const mask: number = Math.round(255 * edge * layerOpacity);
        if (mask === 0) {
          continue;
        }
        const outputIndex: number = (y * width + x) * 4;
        const red: number = Math.round(referencePixels[sourceIndex] * (1 - strength) +
          smudged.red * strength);
        const green: number = Math.round(referencePixels[sourceIndex + 1] * (1 - strength) +
          smudged.green * strength);
        const blue: number = Math.round(referencePixels[sourceIndex + 2] * (1 - strength) +
          smudged.blue * strength);
        output[outputIndex] = blue;
        output[outputIndex + 1] = green;
        output[outputIndex + 2] = red;
        output[outputIndex + 3] = Math.round(referencePixels[sourceIndex + 3] * mask / 255);
      }
    }
  }
  return image.createPixelMap(output.buffer as ArrayBuffer, {
    size: sourceInfo.size,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    editable: true
  });
}

function saturatedReferencePixel(reference: Uint8Array, width: number, height: number, stride: number,
  x: number, y: number, mode: number): BlurPixel {
  const centerX: number = Math.max(0, Math.min(width - 1, x));
  const centerY: number = Math.max(0, Math.min(height - 1, y));
  const index: number = centerY * stride + centerX * 4;
  const red: number = reference[index] / 255;
  const green: number = reference[index + 1] / 255;
  const blue: number = reference[index + 2] / 255;
  const luminance: number = red * 0.2126 + green * 0.7152 + blue * 0.0722;
  const saturation: number = mode === 0 ? 0.25 : 1.65;
  return {
    red: Math.max(0, Math.min(255, Math.round((luminance + (red - luminance) * saturation) * 255))),
    green: Math.max(0, Math.min(255, Math.round((luminance + (green - luminance) * saturation) * 255))),
    blue: Math.max(0, Math.min(255, Math.round((luminance + (blue - luminance) * saturation) * 255)))
  };
}

async function createSpongeSurface(layer: LayerModel, reference: image.PixelMap,
  sourceInfo: image.ImageInfo): Promise<image.PixelMap> {
  const width: number = sourceInfo.size.width;
  const height: number = sourceInfo.size.height;
  const output: Uint8Array = new Uint8Array(width * height * 4);
  if (layer.paintPoints.length === 0 || layer.paintRetouchStrength <= 0) {
    return image.createPixelMap(output.buffer as ArrayBuffer, {
      size: sourceInfo.size,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    });
  }
  const referenceBuffer: ArrayBuffer = new ArrayBuffer(reference.getPixelBytesNumber());
  await reference.readPixelsToBuffer(referenceBuffer);
  const referencePixels: Uint8Array = new Uint8Array(referenceBuffer);
  const brushRadius: number = Math.max(0.5, layer.paintWidth / 2);
  const flow: number = Math.max(1, Math.min(100, layer.paintRetouchStrength)) / 100;
  const layerOpacity: number = Math.max(0, Math.min(100, layer.opacity)) / 100;
  let minX: number = Number.MAX_VALUE;
  let minY: number = Number.MAX_VALUE;
  let maxX: number = Number.MIN_VALUE;
  let maxY: number = Number.MIN_VALUE;
  for (const point of layer.paintPoints) {
    minX = Math.min(minX, point.x);
    minY = Math.min(minY, point.y);
    maxX = Math.max(maxX, point.x);
    maxY = Math.max(maxY, point.y);
  }
  const clip: SelectionRect = layer.paintClip;
  const left: number = Math.max(clip.x, Math.floor(minX - brushRadius));
  const top: number = Math.max(clip.y, Math.floor(minY - brushRadius));
  const right: number = Math.min(clip.x + clip.width - 1, Math.ceil(maxX + brushRadius));
  const bottom: number = Math.min(clip.y + clip.height - 1, Math.ceil(maxY + brushRadius));
  if (left <= right && top <= bottom) {
    for (let y: number = top; y <= bottom; y++) {
      for (let x: number = left; x <= right; x++) {
        if (!isPixelInsidePaintClip(layer, x, y)) {
          continue;
        }
        const distance: number = distanceToPaintStroke(x, y, layer);
        if (distance > brushRadius) {
          continue;
        }
        const sourceIndex: number = y * sourceInfo.stride + x * 4;
        if (sourceIndex < 0 || sourceIndex + 3 >= referencePixels.length) {
          continue;
        }
        const edge: number = Math.max(0, Math.min(1, brushRadius - distance));
        const mask: number = Math.round(255 * edge * layerOpacity);
        if (mask === 0) {
          continue;
        }
        const saturated: BlurPixel = saturatedReferencePixel(referencePixels, width, height,
          sourceInfo.stride, x, y, layer.paintSpongeMode);
        const outputIndex: number = (y * width + x) * 4;
        const red: number = Math.round(referencePixels[sourceIndex] * (1 - flow) +
          saturated.red * flow);
        const green: number = Math.round(referencePixels[sourceIndex + 1] * (1 - flow) +
          saturated.green * flow);
        const blue: number = Math.round(referencePixels[sourceIndex + 2] * (1 - flow) +
          saturated.blue * flow);
        output[outputIndex] = blue;
        output[outputIndex + 1] = green;
        output[outputIndex + 2] = red;
        output[outputIndex + 3] = Math.round(referencePixels[sourceIndex + 3] * mask / 255);
      }
    }
  }
  return image.createPixelMap(output.buffer as ArrayBuffer, {
    size: sourceInfo.size,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    editable: true
  });
}

async function createDodgeBurnSurface(layer: LayerModel, reference: image.PixelMap,
  sourceInfo: image.ImageInfo): Promise<image.PixelMap> {
  const width: number = sourceInfo.size.width;
  const height: number = sourceInfo.size.height;
  const output: Uint8Array = new Uint8Array(width * height * 4);
  if (layer.paintPoints.length === 0 || layer.paintRetouchStrength <= 0) {
    return image.createPixelMap(output.buffer as ArrayBuffer, {
      size: sourceInfo.size,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    });
  }
  const referenceBuffer: ArrayBuffer = new ArrayBuffer(reference.getPixelBytesNumber());
  await reference.readPixelsToBuffer(referenceBuffer);
  const referencePixels: Uint8Array = new Uint8Array(referenceBuffer);
  const brushRadius: number = Math.max(0.5, layer.paintWidth / 2);
  const strokeFlow: number = dodgeBurnExposureFlow(layer.paintRetouchStrength, layer.paintMode);
  const layerOpacity: number = Math.max(0, Math.min(100, layer.opacity)) / 100;
  let minX: number = Number.MAX_VALUE;
  let minY: number = Number.MAX_VALUE;
  let maxX: number = Number.MIN_VALUE;
  let maxY: number = Number.MIN_VALUE;
  for (const point of layer.paintPoints) {
    minX = Math.min(minX, point.x);
    minY = Math.min(minY, point.y);
    maxX = Math.max(maxX, point.x);
    maxY = Math.max(maxY, point.y);
  }
  const clip: SelectionRect = layer.paintClip;
  const left: number = Math.max(clip.x, Math.floor(minX - brushRadius));
  const top: number = Math.max(clip.y, Math.floor(minY - brushRadius));
  const right: number = Math.min(clip.x + clip.width - 1, Math.ceil(maxX + brushRadius));
  const bottom: number = Math.min(clip.y + clip.height - 1, Math.ceil(maxY + brushRadius));
  if (left <= right && top <= bottom) {
    for (let y: number = top; y <= bottom; y++) {
      for (let x: number = left; x <= right; x++) {
        if (!isPixelInsidePaintClip(layer, x, y)) {
          continue;
        }
        const distance: number = distanceToPaintStroke(x, y, layer);
        if (distance > brushRadius) {
          continue;
        }
        const sourceIndex: number = y * sourceInfo.stride + x * 4;
        if (sourceIndex < 0 || sourceIndex + 3 >= referencePixels.length) {
          continue;
        }
        const edge: number = Math.max(0, Math.min(1, brushRadius - distance));
        const mask: number = Math.round(255 * edge * strokeFlow * layerOpacity);
        if (mask === 0) {
          continue;
        }
        const red: number = Math.round((dodgeBurnToneValue(referencePixels[sourceIndex], layer.paintMode,
          layer.paintRetouchRange) * mask + referencePixels[sourceIndex] * (255 - mask)) / 255);
        const green: number = Math.round((dodgeBurnToneValue(referencePixels[sourceIndex + 1], layer.paintMode,
          layer.paintRetouchRange) * mask + referencePixels[sourceIndex + 1] * (255 - mask)) / 255);
        const blue: number = Math.round((dodgeBurnToneValue(referencePixels[sourceIndex + 2], layer.paintMode,
          layer.paintRetouchRange) * mask + referencePixels[sourceIndex + 2] * (255 - mask)) / 255);
        const outputIndex: number = (y * width + x) * 4;
        output[outputIndex] = blue;
        output[outputIndex + 1] = green;
        output[outputIndex + 2] = red;
        output[outputIndex + 3] = Math.round(referencePixels[sourceIndex + 3] * mask / 255);
      }
    }
  }
  return image.createPixelMap(output.buffer as ArrayBuffer, {
    size: sourceInfo.size,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    editable: true
  });
}


/**
 * Content-aware spot healing.
 *
 * The stroke is rasterised into a mask, the whole document is handed to the
 * patch-match planner, and the repaired pixels are written back with the
 * stroke's flow and layer opacity. The planner works in RGB, while the source
 * buffer read back from a PixelMap is BGRA, so the reference is swizzled first.
 *
 * Healing samples real surrounding texture, so the result replaces the stroke
 * rather than compositing over it: only the masked pixels are written, and the
 * surface is fully transparent everywhere else.
 */
async function createSpotHealSurface(layer: LayerModel, reference: image.PixelMap,
  sourceInfo: image.ImageInfo): Promise<image.PixelMap> {
  const width: number = sourceInfo.size.width;
  const height: number = sourceInfo.size.height;
  const output: Uint8Array = new Uint8Array(width * height * 4);
  if (layer.paintPoints.length === 0 || layer.paintRetouchStrength <= 0) {
    return createTransparentPixelMap(sourceInfo);
  }
  const referenceBuffer: ArrayBuffer = new ArrayBuffer(reference.getPixelBytesNumber());
  await reference.readPixelsToBuffer(referenceBuffer);
  const referencePixels: Uint8Array = new Uint8Array(referenceBuffer);
  const brushRadius: number = Math.max(0.5, layer.paintWidth / 2);
  const flow: number = Math.max(1, Math.min(100, layer.paintRetouchStrength)) / 100;
  const layerOpacity: number = Math.max(0, Math.min(100, layer.opacity)) / 100;
  const stride: number = Math.max(width * 4, sourceInfo.stride);
  // Rasterise the stroke into a hole mask, the same shape the planner expects.
  const mask: Uint8Array = new Uint8Array(width * height);
  let minX: number = Number.MAX_VALUE;
  let minY: number = Number.MAX_VALUE;
  let maxX: number = -Number.MAX_VALUE;
  let maxY: number = -Number.MAX_VALUE;
  for (const point of layer.paintPoints) {
    minX = Math.min(minX, point.x);
    minY = Math.min(minY, point.y);
    maxX = Math.max(maxX, point.x);
    maxY = Math.max(maxY, point.y);
  }
  const clip: SelectionRect = layer.paintClip;
  const left: number = Math.max(clip.x, Math.floor(minX - brushRadius));
  const top: number = Math.max(clip.y, Math.floor(minY - brushRadius));
  const right: number = Math.min(clip.x + clip.width - 1, Math.ceil(maxX + brushRadius));
  const bottom: number = Math.min(clip.y + clip.height - 1, Math.ceil(maxY + brushRadius));
  if (left > right || top > bottom) {
    return createTransparentPixelMap(sourceInfo);
  }
  // Grow the search window: the patch match needs clean context around the hole.
  const margin: number = Math.max(16, Math.round(Math.max(brushRadius * 4, 24)));
  const windowLeft: number = Math.max(0, left - margin);
  const windowTop: number = Math.max(0, top - margin);
  const windowRight: number = Math.min(width - 1, right + margin);
  const windowBottom: number = Math.min(height - 1, bottom + margin);
  const windowWidth: number = windowRight - windowLeft + 1;
  const windowHeight: number = windowBottom - windowTop + 1;
  if (windowWidth < 8 || windowHeight < 8) {
    return createTransparentPixelMap(sourceInfo);
  }
  const rgba: Uint8Array = new Uint8Array(windowWidth * windowHeight * 4);
  const windowMask: Uint8Array = new Uint8Array(windowWidth * windowHeight);
  for (let y: number = windowTop; y <= windowBottom; y++) {
    for (let x: number = windowLeft; x <= windowRight; x++) {
      const sourceIndex: number = y * stride + x * 4;
      const local: number = (y - windowTop) * windowWidth + (x - windowLeft);
      if (sourceIndex < 0 || sourceIndex + 3 >= referencePixels.length) {
        continue;
      }
      const localIndex: number = local << 2;
      // readPixelsToBuffer hands back BGRA for RGBA_8888 PixelMaps, while the
      // patch match's working space is RGB, so the edges are swapped here and
      // swapped back on write.
      rgba[localIndex] = referencePixels[sourceIndex + 2];
      rgba[localIndex + 1] = referencePixels[sourceIndex + 1];
      rgba[localIndex + 2] = referencePixels[sourceIndex];
      rgba[localIndex + 3] = referencePixels[sourceIndex + 3];
      if (x < left || x > right || y < top || y > bottom) {
        continue;
      }
      if (!isPixelInsidePaintClip(layer, x, y)) {
        continue;
      }
      if (distanceToPaintStroke(x, y, layer) > brushRadius) {
        continue;
      }
      windowMask[local] = 255;
    }
  }
  const plan: HealPlan | undefined = healPatchPlan(rgba, windowMask, windowWidth, windowHeight);
  if (plan === undefined || plan.patches.length === 0) {
    return createTransparentPixelMap(sourceInfo);
  }
  const healed: Uint8Array = applyHealPlan(plan, rgba, windowMask, windowWidth, windowHeight);
  // Upstream smooths the pasted region into its surroundings with a Poisson
  // solve before compositing, so the fill does not read as a pasted patch.
  healPoissonBlend(healed, windowMask, windowWidth, windowHeight, HEAL_POISSON_ITERATIONS);
  // Write the repaired pixels back out, weighted by the stroke flow and opacity.
  const factor: number = Math.max(1, plan.downsample);
  for (let index: number = 0; index < plan.labels.length; index++) {
    const localCol: number = plan.holeCols[index] * factor;
    const localRow: number = plan.holeRows[index] * factor;
    if (localCol < 0 || localRow < 0 || localCol >= windowWidth || localRow >= windowHeight) {
      continue;
    }
    const patch: HealPatch = plan.patches[plan.labels[index]];
    const sampleCol: number = localCol + patch.x * factor;
    const sampleRow: number = localRow + patch.y * factor;
    if (sampleCol < 0 || sampleRow < 0 || sampleCol >= windowWidth || sampleRow >= windowHeight) {
      continue;
    }
    const x: number = windowLeft + localCol;
    const y: number = windowTop + localRow;
    const targetIndex: number = y * width + x;
    const edge: number = Math.max(0, Math.min(1, brushRadius - distanceToPaintStroke(x, y, layer)));
    const weight: number = edge * flow * layerOpacity;
    if (weight <= 0) {
      continue;
    }
    const healedIndex: number = targetIndex << 2;
    const healedLocal: number = (localRow * windowWidth + localCol) << 2;
    // `healed` is RGB (the patch match's working space) and the surface buffer
    // is consumed in the same RGB order the reference was read into, so the
    // channels are written straight through.
    output[healedIndex] = healed[healedLocal];
    output[healedIndex + 1] = healed[healedLocal + 1];
    output[healedIndex + 2] = healed[healedLocal + 2];
    output[healedIndex + 3] = Math.round(255 * weight);
  }
  return image.createPixelMap(output.buffer as ArrayBuffer, {
    size: sourceInfo.size,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    editable: true
  });
}

async function createRedEyeSurface(layer: LayerModel, reference: image.PixelMap,
  sourceInfo: image.ImageInfo): Promise<image.PixelMap> {
  const width: number = sourceInfo.size.width;
  const height: number = sourceInfo.size.height;
  const output: Uint8Array = new Uint8Array(width * height * 4);
  if (layer.paintPoints.length === 0 || layer.paintRetouchStrength <= 0) {
    return image.createPixelMap(output.buffer as ArrayBuffer, {
      size: sourceInfo.size,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    });
  }
  const referenceBuffer: ArrayBuffer = new ArrayBuffer(reference.getPixelBytesNumber());
  await reference.readPixelsToBuffer(referenceBuffer);
  const referencePixels: Uint8Array = new Uint8Array(referenceBuffer);
  const brushRadius: number = Math.max(0.5, layer.paintWidth / 2);
  const flow: number = Math.max(1, Math.min(100, layer.paintRetouchStrength)) / 100;
  const layerOpacity: number = Math.max(0, Math.min(100, layer.opacity)) / 100;
  let minX: number = Number.MAX_VALUE;
  let minY: number = Number.MAX_VALUE;
  let maxX: number = Number.MIN_VALUE;
  let maxY: number = Number.MIN_VALUE;
  for (const point of layer.paintPoints) {
    minX = Math.min(minX, point.x);
    minY = Math.min(minY, point.y);
    maxX = Math.max(maxX, point.x);
    maxY = Math.max(maxY, point.y);
  }
  const clip: SelectionRect = layer.paintClip;
  const left: number = Math.max(clip.x, Math.floor(minX - brushRadius));
  const top: number = Math.max(clip.y, Math.floor(minY - brushRadius));
  const right: number = Math.min(clip.x + clip.width - 1, Math.ceil(maxX + brushRadius));
  const bottom: number = Math.min(clip.y + clip.height - 1, Math.ceil(maxY + brushRadius));
  if (left <= right && top <= bottom) {
    for (let y: number = top; y <= bottom; y++) {
      for (let x: number = left; x <= right; x++) {
        if (!isPixelInsidePaintClip(layer, x, y)) {
          continue;
        }
        const distance: number = distanceToPaintStroke(x, y, layer);
        if (distance > brushRadius) {
          continue;
        }
        const sourceIndex: number = y * sourceInfo.stride + x * 4;
        if (sourceIndex < 0 || sourceIndex + 3 >= referencePixels.length) {
          continue;
        }
        const edge: number = Math.max(0, Math.min(1, brushRadius - distance));
        const mask: number = Math.round(255 * edge * flow * layerOpacity);
        if (mask === 0) {
          continue;
        }
        // Source buffers are BGRA ordered; the red-eye kernel works in RGB.
        const corrected: HslColor = redEyeCorrection(referencePixels[sourceIndex] / 255,
          referencePixels[sourceIndex + 1] / 255, referencePixels[sourceIndex + 2] / 255);
        const red: number = Math.round(corrected.hue * 255);
        const green: number = Math.round(corrected.saturation * 255);
        const blue: number = Math.round(corrected.lightness * 255);
        const outputIndex: number = (y * width + x) * 4;
        output[outputIndex] = blue;
        output[outputIndex + 1] = green;
        output[outputIndex + 2] = red;
        output[outputIndex + 3] = Math.round(referencePixels[sourceIndex + 3] * mask / 255);
      }
    }
  }
  return image.createPixelMap(output.buffer as ArrayBuffer, {
    size: sourceInfo.size,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    editable: true
  });
}

async function createFillSurface(layer: LayerModel, reference: image.PixelMap,
  sourceInfo: image.ImageInfo): Promise<image.PixelMap> {
  const width: number = sourceInfo.size.width;
  const height: number = sourceInfo.size.height;
  const referenceBuffer: ArrayBuffer = new ArrayBuffer(reference.getPixelBytesNumber());
  await reference.readPixelsToBuffer(referenceBuffer);
  const referencePixels: Uint8Array = new Uint8Array(referenceBuffer);
  const seed: TransformPoint = layer.paintPoints.length > 0 ? layer.paintPoints[0] : { x: 0, y: 0 };
  const mask: Uint8Array = floodFillMask(referencePixels, width, height, sourceInfo.stride,
    seed.x, seed.y, layer.paintFillTolerance, layer.paintFillContiguous, layer.paintFillAntialias);
  const fillBuffer: ArrayBuffer = new ArrayBuffer(width * height * 4);
  const fillPixels: Uint8Array = new Uint8Array(fillBuffer);
  const argb: number = colorToArgb(layer.paintColor, layer.opacity);
  const red: number = (argb >> 16) & 255;
  const green: number = (argb >> 8) & 255;
  const blue: number = argb & 255;
  const clip: SelectionRect = layer.paintClip;
  for (let y: number = 0; y < height; y++) {
    for (let x: number = 0; x < width; x++) {
      const outputIndex: number = (y * width + x) * 4;
      const inside: boolean = isPixelInsidePaintClip(layer, x, y);
      fillPixels[outputIndex] = red;
      fillPixels[outputIndex + 1] = green;
      fillPixels[outputIndex + 2] = blue;
      fillPixels[outputIndex + 3] = inside ? mask[y * width + x] : 0;
    }
  }
  return image.createPixelMap(fillBuffer, {
    size: sourceInfo.size,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    editable: true
  });
}

async function createCloneSurface(layer: LayerModel, reference: image.PixelMap,
  sourceInfo: image.ImageInfo): Promise<image.PixelMap> {
  const width: number = sourceInfo.size.width;
  const height: number = sourceInfo.size.height;
  const referenceBuffer: ArrayBuffer = new ArrayBuffer(reference.getPixelBytesNumber());
  await reference.readPixelsToBuffer(referenceBuffer);
  const referencePixels: Uint8Array = new Uint8Array(referenceBuffer);
  const output: Uint8Array = new Uint8Array(width * height * 4);
  if (layer.paintPoints.length === 0) {
    return image.createPixelMap(output.buffer as ArrayBuffer, {
      size: sourceInfo.size,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    });
  }
  const firstTarget: TransformPoint = layer.paintPoints[0];
  const clip: SelectionRect = layer.paintClip;
  const opacity: number = Math.max(0, Math.min(100, layer.opacity)) / 100;
  const sampleAt: (targetX: number, targetY: number) => void = (targetX: number,
    targetY: number): void => {
    const sourceX: number = Math.round(layer.paintCloneSource.x + targetX - firstTarget.x);
    const sourceY: number = Math.round(layer.paintCloneSource.y + targetY - firstTarget.y);
    if (sourceX < 0 || sourceX >= width || sourceY < 0 || sourceY >= height ||
      !isPixelInsidePaintClip(layer, targetX, targetY)) {
      return;
    }
    const sourceIndex: number = sourceY * sourceInfo.stride + sourceX * 4;
    const targetIndex: number = (targetY * width + targetX) * 4;
    if (sourceIndex < 0 || sourceIndex + 3 >= referencePixels.length) {
      return;
    }
    const sourceAlpha: number = referencePixels[sourceIndex + 3];
    if (sourceAlpha === 0) {
      return;
    }
    output[targetIndex] = referencePixels[sourceIndex];
    output[targetIndex + 1] = referencePixels[sourceIndex + 1];
    output[targetIndex + 2] = referencePixels[sourceIndex + 2];
    output[targetIndex + 3] = Math.round(sourceAlpha * opacity);
  };
  sampleAt(firstTarget.x, firstTarget.y);
  for (let pointIndex: number = 1; pointIndex < layer.paintPoints.length; pointIndex++) {
    const previous: TransformPoint = layer.paintPoints[pointIndex - 1];
    const current: TransformPoint = layer.paintPoints[pointIndex];
    const distance: number = Math.max(Math.abs(current.x - previous.x), Math.abs(current.y - previous.y));
    const steps: number = Math.max(1, Math.round(distance));
    for (let step: number = 1; step <= steps; step++) {
      const ratio: number = step / steps;
      sampleAt(Math.round(previous.x + (current.x - previous.x) * ratio),
        Math.round(previous.y + (current.y - previous.y) * ratio));
    }
  }
  const radius: number = Math.max(0, Math.round((layer.paintWidth - 1) / 2));
  if (radius > 0) {
    for (let pointIndex: number = 0; pointIndex < layer.paintPoints.length; pointIndex++) {
      const point: TransformPoint = layer.paintPoints[pointIndex];
      for (let y: number = point.y - radius; y <= point.y + radius; y++) {
        for (let x: number = point.x - radius; x <= point.x + radius; x++) {
          if (Math.abs(x - point.x) + Math.abs(y - point.y) > radius) {
            continue;
          }
          const sourceX: number = Math.round(layer.paintCloneSource.x + x - firstTarget.x);
          const sourceY: number = Math.round(layer.paintCloneSource.y + y - firstTarget.y);
          if (sourceX < 0 || sourceX >= width || sourceY < 0 || sourceY >= height ||
            !isPixelInsidePaintClip(layer, x, y)) {
            continue;
          }
          const sourceIndex: number = sourceY * sourceInfo.stride + sourceX * 4;
          const targetIndex: number = (y * width + x) * 4;
          if (sourceIndex >= 0 && sourceIndex + 3 < referencePixels.length) {
            const sourceAlpha: number = referencePixels[sourceIndex + 3];
            output[targetIndex] = referencePixels[sourceIndex];
            output[targetIndex + 1] = referencePixels[sourceIndex + 1];
            output[targetIndex + 2] = referencePixels[sourceIndex + 2];
            output[targetIndex + 3] = Math.round(sourceAlpha * opacity);
          }
        }
      }
    }
  }
  return image.createPixelMap(output.buffer as ArrayBuffer, {
    size: sourceInfo.size,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    editable: true
  });
}

async function createTransparentPixelMap(sourceInfo: image.ImageInfo): Promise<image.PixelMap> {
  const transparent: ArrayBuffer = new ArrayBuffer(
    sourceInfo.size.width * sourceInfo.size.height * 4);
  return image.createPixelMap(transparent, {
    size: sourceInfo.size,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    editable: true
  });
}

async function rebuildPaintReference(base: image.PixelMap, surfaces: PaintSurface[],
  previous: image.PixelMap): Promise<image.PixelMap> {
  const rebuilt: image.PixelMap = await cloneEditablePixelMap(base);
  const canvas: drawing.Canvas = new drawing.Canvas(rebuilt);
  for (const surface of surfaces) {
    canvas.drawImage(surface.pixelMap, 0, 0);
  }
  try {
    await previous.release();
  } catch (error) {
  }
  return rebuilt;
}

async function drawPaintLayers(pixelMap: image.PixelMap, layers: LayerModel[],
  sourceInfo: image.ImageInfo): Promise<void> {
  const surfaces: PaintSurface[] = [];
  const base: image.PixelMap = await cloneEditablePixelMap(pixelMap);
  let paintReference: image.PixelMap = await cloneEditablePixelMap(base);
  try {
    for (const layer of layers) {
      if (layer.kind !== 'paint' || !layer.visible) {
        continue;
      }
      if (layer.paintMode === PaintMode.ERASER) {
        if (layer.opacity <= 0 || layer.paintPoints.length === 0 ||
          layer.paintTargetId.length === 0) {
          continue;
        }
        for (const surface of surfaces) {
          if (surface.layer.id === layer.paintTargetId) {
            drawEraserStroke(new drawing.Canvas(surface.pixelMap), layer);
            paintReference = await rebuildPaintReference(base, surfaces, paintReference);
            break;
          }
        }
        continue;
      }
      if ((layer.paintMode !== PaintMode.BRUSH && layer.paintMode !== PaintMode.PENCIL &&
        layer.paintMode !== PaintMode.GRADIENT &&
        layer.paintMode !== PaintMode.FILL && layer.paintMode !== PaintMode.CLONE &&
        layer.paintMode !== PaintMode.BLUR && layer.paintMode !== PaintMode.SHARPEN &&
        layer.paintMode !== PaintMode.SMUDGE && layer.paintMode !== PaintMode.SPONGE &&
        layer.paintMode !== PaintMode.RED_EYE &&
        layer.paintMode !== PaintMode.SPOT_HEAL &&
        layer.paintMode !== PaintMode.DODGE && layer.paintMode !== PaintMode.BURN) || layer.opacity <= 0 ||
        layer.paintPoints.length === 0) {
        continue;
      }
      const surface: PaintSurface = {
        layer: layer,
        pixelMap: layer.paintMode === PaintMode.FILL ?
          await createFillSurface(layer, paintReference, sourceInfo) :
          layer.paintMode === PaintMode.CLONE ?
          await createCloneSurface(layer, paintReference, sourceInfo) :
          layer.paintMode === PaintMode.BLUR ?
          await createBlurSurface(layer, paintReference, sourceInfo) :
          layer.paintMode === PaintMode.SHARPEN ?
          await createSharpenSurface(layer, paintReference, sourceInfo) :
          layer.paintMode === PaintMode.SMUDGE ?
          await createSmudgeSurface(layer, paintReference, sourceInfo) :
          layer.paintMode === PaintMode.SPONGE ?
          await createSpongeSurface(layer, paintReference, sourceInfo) :
          layer.paintMode === PaintMode.RED_EYE ?
          await createRedEyeSurface(layer, paintReference, sourceInfo) :
          layer.paintMode === PaintMode.SPOT_HEAL ?
          await createSpotHealSurface(layer, paintReference, sourceInfo) :
          layer.paintMode === PaintMode.DODGE || layer.paintMode === PaintMode.BURN ?
          await createDodgeBurnSurface(layer, paintReference, sourceInfo) :
          await createTransparentPixelMap(sourceInfo)
      };
      if (layer.paintMode === PaintMode.GRADIENT) {
        drawGradientLayer(new drawing.Canvas(surface.pixelMap), layer);
      } else if (layer.paintMode === PaintMode.BRUSH || layer.paintMode === PaintMode.PENCIL) {
        drawPaintLayer(new drawing.Canvas(surface.pixelMap), layer);
      }
      surfaces.push(surface);
      new drawing.Canvas(paintReference).drawImage(surface.pixelMap, 0, 0);
    }
    const canvas: drawing.Canvas = new drawing.Canvas(pixelMap);
    for (const layer of layers) {
      if (layer.kind !== 'paint' ||
        (layer.paintMode !== PaintMode.BRUSH && layer.paintMode !== PaintMode.PENCIL &&
          layer.paintMode !== PaintMode.GRADIENT &&
          layer.paintMode !== PaintMode.FILL && layer.paintMode !== PaintMode.CLONE &&
          layer.paintMode !== PaintMode.BLUR && layer.paintMode !== PaintMode.SHARPEN &&
          layer.paintMode !== PaintMode.SMUDGE && layer.paintMode !== PaintMode.SPONGE &&
          layer.paintMode !== PaintMode.RED_EYE &&
          layer.paintMode !== PaintMode.SPOT_HEAL &&
          layer.paintMode !== PaintMode.DODGE && layer.paintMode !== PaintMode.BURN) ||
        !layer.visible) {
        continue;
      }
      for (const surface of surfaces) {
        if (surface.layer.id === layer.id) {
          canvas.drawImage(surface.pixelMap, 0, 0);
          break;
        }
      }
    }
  } finally {
    try {
      await paintReference.release();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'paint reference release failed');
    }
    try {
      await base.release();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'paint base release failed');
    }
    for (const surface of surfaces) {
      try {
        await surface.pixelMap.release();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'paint surface release failed');
      }
    }
  }
}

function drawPaintLayer(canvas: drawing.Canvas, layer: LayerModel): void {
  const color: number = colorToArgb(layer.paintColor, layer.opacity);
  if (layer.paintPoints.length === 1) {
    const point = layer.paintPoints[0];
    const brush: drawing.Brush = new drawing.Brush();
    brush.setColor(color);
    brush.setAntiAlias(layer.paintMode !== PaintMode.PENCIL);
    canvas.attachBrush(brush);
    canvas.drawCircle(point.x, point.y, Math.max(0.5, layer.paintWidth / 2));
    canvas.detachBrush();
    return;
  }
  const path: drawing.Path = new drawing.Path();
  const first = layer.paintPoints[0];
  path.moveTo(first.x, first.y);
  for (let index: number = 1; index < layer.paintPoints.length; index++) {
    const point = layer.paintPoints[index];
    path.lineTo(point.x, point.y);
  }
  const pen: drawing.Pen = new drawing.Pen();
  pen.setColor(color);
  pen.setStrokeWidth(layer.paintWidth);
  pen.setAntiAlias(layer.paintMode !== PaintMode.PENCIL);
  pen.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
  pen.setCapStyle(drawing.CapStyle.ROUND_CAP);
  canvas.attachPen(pen);
  canvas.drawPath(path);
  canvas.detachPen();
}

function drawGradientLayer(canvas: drawing.Canvas, layer: LayerModel): void {
  if (layer.paintMode !== PaintMode.GRADIENT || layer.paintGradientStyle !== PaintGradientStyle.LINEAR ||
    layer.paintPoints.length < 2) {
    return;
  }
  const start = layer.paintPoints[0];
  const end = layer.paintPoints[layer.paintPoints.length - 1];
  const colors: number[] = [
    colorToArgb(layer.paintColor, layer.opacity),
    colorToArgb(layer.paintSecondaryColor, layer.opacity)
  ];
  if (layer.paintGradientReverse) {
    const first: number = colors[0];
    colors[0] = colors[1];
    colors[1] = first;
  }
  const startPoint: common2D.Point = { x: start.x, y: start.y };
  const endPoint: common2D.Point = { x: end.x, y: end.y };
  const shader: drawing.ShaderEffect = drawing.ShaderEffect.createLinearGradient(startPoint,
    endPoint, colors, drawing.TileMode.CLAMP, [0, 1], null);
  const brush: drawing.Brush = new drawing.Brush();
  brush.setShaderEffect(shader);
  brush.setAntiAlias(true);
  canvas.save();
  const clip = layer.paintClip;
  const clipRegion: drawing.Region | undefined = paintClipRegion(layer, layer.paintClipMaskWidth);
  if (clipRegion !== undefined) {
    canvas.clipRegion(clipRegion, drawing.ClipOp.INTERSECT);
  } else {
    canvas.clipRect({
      left: clip.x,
      top: clip.y,
      right: clip.x + clip.width,
      bottom: clip.y + clip.height
    }, drawing.ClipOp.INTERSECT, true);
  }
  canvas.attachBrush(brush);
  canvas.drawRect(0, 0, Math.max(1, clip.x + clip.width), Math.max(1, clip.y + clip.height));
  canvas.detachBrush();
  canvas.restore();
}

function drawEraserStroke(canvas: drawing.Canvas, eraser: LayerModel): void {
  const color: number = colorToArgb('#000000', eraser.opacity);
  if (eraser.paintPoints.length === 1) {
    const point = eraser.paintPoints[0];
    const brush: drawing.Brush = new drawing.Brush();
    brush.setColor(color);
    brush.setAntiAlias(true);
    brush.setBlendMode(drawing.BlendMode.DST_OUT);
    canvas.attachBrush(brush);
    canvas.drawCircle(point.x, point.y, Math.max(0.5, eraser.paintWidth / 2));
    canvas.detachBrush();
    return;
  }
  const path: drawing.Path = new drawing.Path();
  const first = eraser.paintPoints[0];
  path.moveTo(first.x, first.y);
  for (let index: number = 1; index < eraser.paintPoints.length; index++) {
    const point = eraser.paintPoints[index];
    path.lineTo(point.x, point.y);
  }
  const pen: drawing.Pen = new drawing.Pen();
  pen.setColor(color);
  pen.setStrokeWidth(eraser.paintWidth);
  pen.setAntiAlias(true);
  pen.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
  pen.setCapStyle(drawing.CapStyle.ROUND_CAP);
  pen.setBlendMode(drawing.BlendMode.DST_OUT);
  canvas.attachPen(pen);
  canvas.drawPath(path);
  canvas.detachPen();
}

function drawShapeLayers(pixelMap: image.PixelMap, layers: LayerModel[]): void {
  const canvas: drawing.Canvas = new drawing.Canvas(pixelMap);
  for (const layer of layers) {
    if (layer.kind !== 'shape' || !layer.visible || layer.opacity <= 0 || layer.shapeWidth <= 0 ||
      layer.shapeHeight <= 0) {
      continue;
    }
    const left: number = layer.shapeX;
    const top: number = layer.shapeY;
    const right: number = left + layer.shapeWidth;
    const bottom: number = top + layer.shapeHeight;
    const brush: drawing.Brush = new drawing.Brush();
    brush.setColor(colorToArgb(layer.shapeFill, layer.opacity));
    brush.setAntiAlias(true);
    canvas.attachBrush(brush);
    const pen: drawing.Pen = new drawing.Pen();
    pen.setColor(colorToArgb(layer.shapeStroke, layer.opacity));
    pen.setStrokeWidth(layer.shapeStrokeWidth);
    pen.setAntiAlias(true);
    canvas.attachPen(pen);
    if (layer.shapeType === ShapeType.ELLIPSE) {
      const bounds: common2D.Rect = {
        left: left,
        top: top,
        right: right,
        bottom: bottom
      };
      canvas.drawOval(bounds);
    } else {
      canvas.drawRect(left, top, right, bottom);
    }
    canvas.detachPen();
    canvas.detachBrush();
  }
}

async function applyDocumentTransform(pixelMap: image.PixelMap, transform: TransformState): Promise<void> {
  const normalized: TransformState = normalizeTransform(transform);
  if (normalized.rotation !== 0) {
    await pixelMap.rotate(normalized.rotation);
  }
  if (normalized.flipHorizontal || normalized.flipVertical) {
    await pixelMap.flip(normalized.flipHorizontal, normalized.flipVertical);
  }
}

async function applyCrop(pixelMap: image.PixelMap, crop: CropRect): Promise<void> {
  await pixelMap.crop({
    x: crop.x,
    y: crop.y,
    size: {
      width: crop.width,
      height: crop.height
    }
  });
}

export async function pickAndDecodeImage(context: common.UIAbilityContext): Promise<OpenDocument> {
  const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
  const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
  options.maxSelectNumber = 1;
  options.fileSuffixFilters = FILTERS;
  const uris: string[] = await documentPicker.select(options);
  if (uris.length === 0) {
    return { name: '', uri: '', width: 0, height: 0, source: '' };
  }

  const uri: string = uris[0];
  const source: image.ImageSource = image.createImageSource(uri);
  try {
    const info: image.ImageInfo = await source.getImageInfo();
    const longestEdge: number = Math.max(info.size.width, info.size.height);
    const sampleSize: number = longestEdge > MAX_PREVIEW_EDGE ?
      Math.ceil(longestEdge / MAX_PREVIEW_EDGE) : 1;
    const decodingOptions: image.DecodingOptions = {
      desiredSize: {
        width: Math.max(1, Math.floor(info.size.width / sampleSize)),
        height: Math.max(1, Math.floor(info.size.height / sampleSize))
      },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    };
    const pixelMap: image.PixelMap = await source.createPixelMap(decodingOptions);
    const decodedInfo: image.ImageInfo = await pixelMap.getImageInfo();
    return {
      name: uriName(uri, 'Untitled image'),
      uri: uri,
      width: decodedInfo.size.width,
      height: decodedInfo.size.height,
      source: pixelMap
    };
  } finally {
    await source.release();
  }
}

export async function decodeBundledSample(context: common.UIAbilityContext): Promise<image.PixelMap> {
  const rawFile: Uint8Array = await context.resourceManager.getRawFileContent('sample_beach.jpg');
  const source: image.ImageSource = image.createImageSource(rawFile.buffer as ArrayBuffer);
  try {
    return await source.createPixelMap({
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
  } finally {
    await source.release();
  }
}

export async function renderPreviewPixelMap(pixelMap: image.PixelMap,
  adjustments: AdjustmentValues, filter: FilterState, layers: LayerModel[]): Promise<image.PixelMap> {
  let baked: image.PixelMap | undefined = undefined;
  let rendered: image.PixelMap | undefined = undefined;
  try {
  const sourceInfo: image.ImageInfo = await pixelMap.getImageInfo();
    const sourceBuffer: ArrayBuffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
    await pixelMap.readPixelsToBuffer(sourceBuffer);
    const adjustedBuffer: ArrayBuffer = applyRgbaFilter(sourceBuffer, sourceInfo.size.width,
      sourceInfo.size.height, sourceInfo.stride,
      documentFilterMatrix(adjustments, filter.preset, filter.intensity));
    baked = await image.createPixelMap(adjustedBuffer, {
      size: sourceInfo.size,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    });
    if (adjustments.blur > 0) {
      const effect: effectKit.Filter = effectKit.createEffect(baked);
      effect.blur(adjustments.blur);
      rendered = await effect.getEffectPixelMap();
    } else {
      rendered = baked;
      baked = undefined;
    }
    const composed: image.PixelMap = await cloneEditablePixelMap(rendered);
    await drawPaintLayers(composed, layers, sourceInfo);
    drawTextLayers(composed, layers);
    drawShapeLayers(composed, layers);
    return composed;
  } finally {
    if (baked !== undefined && baked !== rendered) {
      try {
        await baked.release();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'preview baked PixelMap release failed');
      }
    }
    if (rendered !== undefined) {
      try {
        await rendered.release();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'preview rendered PixelMap release failed');
      }
    }
  }
}

export async function exportPixelMap(context: common.UIAbilityContext, pixelMap: image.PixelMap,
  documentName: string, format: ExportFormat, quality: number,
  adjustments: AdjustmentValues, filter: FilterState, layers: LayerModel[],
  transform: TransformState, crop: CropRect): Promise<string> {
  const packer: image.ImagePacker = image.createImagePacker();
  let composed: image.PixelMap | undefined = undefined;
  try {
    composed = await renderPreviewPixelMap(pixelMap, adjustments, filter, layers);
    await applyCrop(composed, crop);
    await applyDocumentTransform(composed, transform);
    const packingOption: image.PackingOption = {
      format: format,
      quality: quality
    };
    const bytes: ArrayBuffer = await packer.packToData(composed, packingOption);
    const extension: string = format === ExportFormat.PNG ? 'png' : 'jpg';
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const saveOptions: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    saveOptions.newFileNames = [safeExportName(documentName) + '-edited.' + extension];
    saveOptions.fileSuffixChoices = ['JPEG (.jpg)|.jpg', 'PNG (.png)|.png'];
    saveOptions.defaultFilePathUri = 'file://docs/storage/Users/currentUser/Download/';
    const uris: string[] = await documentPicker.save(saveOptions);
    if (uris.length === 0) {
      return '';
    }
    hilog.info(DOMAIN, TAG, 'export destination uri=%{public}s', uris[0]);
    hilog.info(DOMAIN, TAG, 'export destination selected bytes=%{public}d', bytes.byteLength);

    let destination: fileIo.File | undefined = undefined;
    try {
      destination = await fileIo.open(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      const written: number = await fileIo.write(destination.fd, bytes);
      if (written !== bytes.byteLength) {
        throw new Error('Short image export write');
      }
      hilog.info(DOMAIN, TAG, 'export written bytes=%{public}d', written);
      try {
        await verifyExportedDocument(uris[0]);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'export verification unavailable');
      }
      return uris[0];
    } finally {
      await closeFile(destination);
    }
  } catch (error) {
    const businessError: BusinessError = error as BusinessError;
    hilog.error(DOMAIN, TAG, 'write export failed: %{public}d %{public}s', businessError.code,
      businessError.message);
    throw new Error('image export write failed');
  } finally {
    if (composed !== undefined) {
      try {
        await composed.release();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'composed PixelMap release failed');
      }
    }
    try {
      await packer.release();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'ImagePacker release failed');
    }
  }
}
