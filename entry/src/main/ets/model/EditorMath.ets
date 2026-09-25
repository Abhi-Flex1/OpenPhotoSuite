import {
  AdjustmentValues,
  DEFAULT_FILTER_PRESET,
  FILTER_PRESET_KEYS,
  FILTER_PRESET_NAMES,
  CropAspect,
  CropRect,
  PaintMode,
  SelectionRect,
  TransformPoint,
  TransformSize,
  TransformState
} from './EditorTypes';

export function normalizeHexColor(value: string): string {
  let normalized: string = value.trim().toUpperCase();
  if (!normalized.startsWith('#')) {
    normalized = '#' + normalized;
  }
  if (normalized.length === 4) {
    const red: string = normalized.charAt(1);
    const green: string = normalized.charAt(2);
    const blue: string = normalized.charAt(3);
    if (isHexDigit(red) && isHexDigit(green) && isHexDigit(blue)) {
      return '#' + red + red + green + green + blue + blue;
    }
  }
  if (normalized.length === 7) {
    if (isHexDigit(normalized.charAt(1)) && isHexDigit(normalized.charAt(2)) &&
      isHexDigit(normalized.charAt(3)) && isHexDigit(normalized.charAt(4)) &&
      isHexDigit(normalized.charAt(5)) && isHexDigit(normalized.charAt(6))) {
      return normalized;
    }
  }
  return '';
}

export function clamp(value: number, minimum: number, maximum: number): number {
  if (Number.isNaN(value)) {
    return minimum;
  }
  return Math.min(maximum, Math.max(minimum, value));
}

export function dodgeBurnToneValue(channelValue: number, mode: PaintMode, range: number): number {
  const source: number = clamp(Math.round(channelValue), 0, 255) / 255;
  const normalizedRange: number = clamp(Math.round(range), 0, 2);
  let multiplyFactor: number = 1;
  let gammaExponent: number = 1;
  let exposureOffset: number = 0;
  if (mode === PaintMode.DODGE) {
    if (normalizedRange === 0) {
      multiplyFactor = 0.5;
      exposureOffset = 0.5;
    } else if (normalizedRange === 1) {
      gammaExponent = 0.5;
    } else if (normalizedRange === 2) {
      multiplyFactor = 2;
    }
  } else if (normalizedRange === 0) {
    multiplyFactor = 2;
    exposureOffset = -1;
  } else if (normalizedRange === 1) {
    gammaExponent = 2;
  } else if (normalizedRange === 2) {
    multiplyFactor = 0.5;
  }
  const adjusted: number = exposureOffset + multiplyFactor * Math.pow(source, gammaExponent);
  return Math.round(clamp(adjusted, 0, 1) * 255);
}

export function dodgeBurnExposureFlow(exposure: number, mode: PaintMode): number {
  const normalizedExposure: number = clamp(exposure, 0, 100) / 100;
  if (mode === PaintMode.DODGE) {
    return normalizedExposure / Math.PI;
  }
  if (mode === PaintMode.BURN) {
    return normalizedExposure / Math.E;
  }
  return 0;
}

function isHexDigit(value: string): boolean {
  const code: number = value.charCodeAt(0);
  return (code >= 48 && code <= 57) || (code >= 65 && code <= 70);
}

export function clampAdjustment(key: string, value: number): number {
  if (Number.isNaN(value)) {
    return 0;
  }
  if (key === 'blur') {
    return clamp(value, 0, 24);
  }
  return clamp(value, -100, 100);
}

export function cloneAdjustments(values: AdjustmentValues): AdjustmentValues {
  return {
    exposure: values.exposure,
    contrast: values.contrast,
    saturation: values.saturation,
    temperature: values.temperature,
    blur: values.blur
  };
}

export function adjustmentsAreNeutral(values: AdjustmentValues): boolean {
  return values.exposure === 0 && values.contrast === 0 && values.saturation === 0 &&
    values.temperature === 0 && values.blur === 0;
}

export function normalizeTransform(transform: TransformState): TransformState {
  const rotation: number = !Number.isFinite(transform.rotation) ? 0 :
    ((Math.round(transform.rotation / 90) * 90) % 360 + 360) % 360;
  return {
    rotation: rotation,
    flipHorizontal: transform.flipHorizontal,
    flipVertical: transform.flipVertical
  };
}

export function cloneTransform(transform: TransformState): TransformState {
  return normalizeTransform(transform);
}

export function transformIsNeutral(transform: TransformState): boolean {
  const normalized: TransformState = normalizeTransform(transform);
  return normalized.rotation === 0 && !normalized.flipHorizontal && !normalized.flipVertical;
}

export function transformedSize(width: number, height: number, transform: TransformState): TransformSize {
  const normalized: TransformState = normalizeTransform(transform);
  const swapsAxes: boolean = normalized.rotation === 90 || normalized.rotation === 270;
  return {
    width: swapsAxes ? height : width,
    height: swapsAxes ? width : height
  };
}

export function transformPoint(x: number, y: number, width: number, height: number,
  transform: TransformState): TransformPoint {
  const normalized: TransformState = normalizeTransform(transform);
  const size: TransformSize = transformedSize(width, height, normalized);
  let transformedX: number = x;
  let transformedY: number = y;
  if (normalized.rotation === 90) {
    transformedX = height - y;
    transformedY = x;
  } else if (normalized.rotation === 180) {
    transformedX = width - x;
    transformedY = height - y;
  } else if (normalized.rotation === 270) {
    transformedX = y;
    transformedY = width - x;
  }
  if (normalized.flipHorizontal) {
    transformedX = size.width - transformedX;
  }
  if (normalized.flipVertical) {
    transformedY = size.height - transformedY;
  }
  return {
    x: transformedX,
    y: transformedY
  };
}

export function fullCropRect(width: number, height: number): CropRect {
  return {
    x: 0,
    y: 0,
    width: Math.max(1, Math.round(width)),
    height: Math.max(1, Math.round(height))
  };
}

export function normalizeCropRect(rect: CropRect, width: number, height: number): CropRect {
  const safeWidth: number = Math.max(1, Math.round(width));
  const safeHeight: number = Math.max(1, Math.round(height));
  const nextWidth: number = Math.max(1, Math.min(safeWidth,
    Number.isFinite(rect.width) ? Math.round(rect.width) : safeWidth));
  const nextHeight: number = Math.max(1, Math.min(safeHeight,
    Number.isFinite(rect.height) ? Math.round(rect.height) : safeHeight));
  return {
    x: Math.max(0, Math.min(safeWidth - nextWidth,
      Number.isFinite(rect.x) ? Math.round(rect.x) : 0)),
    y: Math.max(0, Math.min(safeHeight - nextHeight,
      Number.isFinite(rect.y) ? Math.round(rect.y) : 0)),
    width: nextWidth,
    height: nextHeight
  };
}

export function cropIsFull(rect: CropRect, width: number, height: number): boolean {
  return rect.x === 0 && rect.y === 0 && rect.width === Math.round(width) &&
    rect.height === Math.round(height);
}

export function centeredCropRect(width: number, height: number, aspect: CropAspect): CropRect {
  const safeWidth: number = Math.max(1, Math.round(width));
  const safeHeight: number = Math.max(1, Math.round(height));
  if (aspect === 'free') {
    return fullCropRect(safeWidth, safeHeight);
  }
  const ratio: number = aspect === 'square' ? 1 : aspect === 'fourThree' ? 4 / 3 : 16 / 9;
  let cropWidth: number = safeWidth;
  let cropHeight: number = safeWidth / ratio;
  if (cropHeight > safeHeight) {
    cropHeight = safeHeight;
    cropWidth = safeHeight * ratio;
  }
  cropWidth = Math.max(1, Math.min(safeWidth, Math.round(cropWidth)));
  cropHeight = Math.max(1, Math.min(safeHeight, Math.round(cropHeight)));
  return {
    x: Math.max(0, Math.round((safeWidth - cropWidth) / 2)),
    y: Math.max(0, Math.round((safeHeight - cropHeight) / 2)),
    width: cropWidth,
    height: cropHeight
  };
}

export function cropAspectForRect(rect: CropRect): CropAspect {
  if (rect.width === rect.height) {
    return 'square';
  }
  const ratio: number = rect.width / Math.max(1, rect.height);
  if (Math.abs(ratio - 4 / 3) < 0.01) {
    return 'fourThree';
  }
  if (Math.abs(ratio - 16 / 9) < 0.01) {
    return 'sixteenNine';
  }
  return 'free';
}

export function fullSelectionRect(width: number, height: number): SelectionRect {
  return {
    x: 0,
    y: 0,
    width: Math.max(1, Math.round(width)),
    height: Math.max(1, Math.round(height))
  };
}

export function normalizeSelectionRect(rect: SelectionRect, width: number, height: number): SelectionRect {
  const safeWidth: number = Math.max(1, Math.round(width));
  const safeHeight: number = Math.max(1, Math.round(height));
  const nextWidth: number = Math.max(1, Math.min(safeWidth,
    Number.isFinite(rect.width) ? Math.round(rect.width) : safeWidth));
  const nextHeight: number = Math.max(1, Math.min(safeHeight,
    Number.isFinite(rect.height) ? Math.round(rect.height) : safeHeight));
  return {
    x: Math.max(0, Math.min(safeWidth - nextWidth,
      Number.isFinite(rect.x) ? Math.round(rect.x) : 0)),
    y: Math.max(0, Math.min(safeHeight - nextHeight,
      Number.isFinite(rect.y) ? Math.round(rect.y) : 0)),
    width: nextWidth,
    height: nextHeight
  };
}

export function normalizePaintPoints(points: TransformPoint[], width: number, height: number): TransformPoint[] {
  const safeWidth: number = Math.max(1, Math.round(width));
  const safeHeight: number = Math.max(1, Math.round(height));
  const result: TransformPoint[] = [];
  const maximumPoints: number = 4096;
  for (const point of points) {
    if (result.length >= maximumPoints) {
      break;
    }
    const x: number = Math.max(0, Math.min(safeWidth - 1,
      Number.isFinite(point.x) ? Math.round(point.x) : 0));
    const y: number = Math.max(0, Math.min(safeHeight - 1,
      Number.isFinite(point.y) ? Math.round(point.y) : 0));
    const previous: TransformPoint | undefined = result.length > 0 ? result[result.length - 1] : undefined;
    if (previous === undefined || previous.x !== x || previous.y !== y) {
      result.push({ x: x, y: y });
    }
  }
  return result;
}

export function normalizeSelectionPoints(points: TransformPoint[], width: number,
  height: number): TransformPoint[] {
  return normalizePaintPoints(points, width, height);
}

export function rectangleSelectionPoints(rect: SelectionRect): TransformPoint[] {
  return [
    { x: rect.x, y: rect.y },
    { x: rect.x + rect.width, y: rect.y },
    { x: rect.x + rect.width, y: rect.y + rect.height },
    { x: rect.x, y: rect.y + rect.height }
  ];
}

export function selectionRectFromPoints(points: TransformPoint[]): SelectionRect {
  if (points.length === 0) {
    return { x: 0, y: 0, width: 1, height: 1 };
  }
  let left: number = points[0].x;
  let top: number = points[0].y;
  let right: number = points[0].x;
  let bottom: number = points[0].y;
  for (const point of points) {
    left = Math.min(left, point.x);
    top = Math.min(top, point.y);
    right = Math.max(right, point.x);
    bottom = Math.max(bottom, point.y);
  }
  return {
    x: left,
    y: top,
    width: Math.max(1, right - left),
    height: Math.max(1, bottom - top)
  };
}

export function selectionPointsFromMask(mask: Uint8Array, width: number,
  height: number): TransformPoint[] {
  const safeWidth: number = Math.max(1, Math.round(width));
  const safeHeight: number = Math.max(1, Math.round(height));
  const points: TransformPoint[] = [];
  for (let y: number = 0; y < safeHeight; y++) {
    for (let x: number = 0; x < safeWidth; x++) {
      if (mask[y * safeWidth + x] === 0) {
        continue;
      }
      if (y === 0 || mask[(y - 1) * safeWidth + x] === 0 ||
        mask[y * safeWidth + (x > 0 ? x - 1 : 0)] === 0) {
        const point: TransformPoint = { x: x, y: y };
        points.push(point);
      }
    }
  }
  return points;
}

/**
 * Even-odd ray cast against a closed polygon given in source space.
 */
function pointInPolygon(x: number, y: number, polygon: TransformPoint[]): boolean {
  if (polygon.length < 3) {
    return false;
  }
  let inside: boolean = false;
  for (let i: number = 0, j: number = polygon.length - 1; i < polygon.length; j = i++) {
    const a: TransformPoint = polygon[i];
    const b: TransformPoint = polygon[j];
    const straddles: boolean = (a.y > y) !== (b.y > y);
    if (straddles) {
      const crossingX: number = (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x;
      if (x < crossingX) {
        inside = !inside;
      }
    }
  }
  return inside;
}

/**
 * Rasterize a closed source-space polygon into a per-pixel coverage mask.
 * A lasso outline is a real ring, so this is the exact region it encloses.
 */
export function rasterizePolygonMask(points: TransformPoint[], width: number,
  height: number): Uint8Array {
  const safeWidth: number = Math.max(1, Math.round(width));
  const safeHeight: number = Math.max(1, Math.round(height));
  const mask: Uint8Array = new Uint8Array(safeWidth * safeHeight);
  if (points.length < 3) {
    return mask;
  }
  let left: number = safeWidth;
  let top: number = safeHeight;
  let right: number = 0;
  let bottom: number = 0;
  for (const point of points) {
    left = Math.min(left, point.x);
    top = Math.min(top, point.y);
    right = Math.max(right, point.x);
    bottom = Math.max(bottom, point.y);
  }
  const firstX: number = Math.max(0, Math.floor(left));
  const firstY: number = Math.max(0, Math.floor(top));
  const lastX: number = Math.min(safeWidth - 1, Math.ceil(right));
  const lastY: number = Math.min(safeHeight - 1, Math.ceil(bottom));
  for (let y: number = firstY; y <= lastY; y++) {
    for (let x: number = firstX; x <= lastX; x++) {
      if (pointInPolygon(x, y, points)) {
        mask[y * safeWidth + x] = 255;
      }
    }
  }
  return mask;
}


export interface HslColor {
  hue: number;
  saturation: number;
  lightness: number;
}

export function rgbToHsl(red: number, green: number, blue: number): HslColor {
  const max: number = Math.max(red, green, blue);
  const min: number = Math.min(red, green, blue);
  let hue: number = 0;
  let saturation: number = 0;
  const lightness: number = (max + min) * 0.5;
  if (max !== min) {
    const delta: number = max - min;
    saturation = lightness > 0.5 ? delta / (2 - (max + min)) : delta / (max + min);
    let sector: number = 0;
    if (max === red) {
      sector = (green - blue) / delta;
    }
    if (max === green) {
      sector = 2 + (blue - red) / delta;
    }
    if (max === blue) {
      sector = 4 + (red - green) / delta;
    }
    if (sector < 0) {
      sector += 6;
    }
    hue = sector / 6;
  }
  return { hue: hue, saturation: saturation, lightness: lightness };
}

function hslComponent(t1: number, t2: number, hue: number): number {
  let wrapped: number = hue;
  if (wrapped < 0) {
    wrapped += 1;
  }
  if (wrapped > 1) {
    wrapped -= 1;
  }
  if (wrapped < 1 / 6) {
    return t1 + (t2 - t1) * 6 * wrapped;
  }
  if (wrapped < 1 / 2) {
    return t2;
  }
  if (wrapped < 2 / 3) {
    return t1 + (t2 - t1) * (2 / 3 - wrapped) * 6;
  }
  return t1;
}

export function hslToRgb(hue: number, saturation: number, lightness: number): HslColor {
  let red: number;
  let green: number;
  let blue: number;
  if (saturation === 0) {
    red = lightness;
    green = lightness;
    blue = lightness;
  } else {
    const chroma: number = lightness < 0.5 ? lightness * (1 + saturation) :
      lightness + saturation - lightness * saturation;
    const wrapped: number = 2 * lightness - chroma;
    red = hslComponent(wrapped, chroma, hue + 1 / 3);
    green = hslComponent(wrapped, chroma, hue);
    blue = hslComponent(wrapped, chroma, hue - 1 / 3);
  }
  return { hue: red, saturation: green, lightness: blue };
}

export function saturationCurve(saturation: number): number {
  if (saturation < 0) {
    return saturation;
  }
  return Math.pow(Math.tan(Math.PI / 2 * saturation), 1.3);
}

export function saturationCurveInverse(saturation: number): number {
  if (saturation < 0) {
    return saturation;
  }
  return Math.atan2(Math.pow(saturation, 1 / 1.3), 1) / (Math.PI / 2);
}

function hueRangeWeight(hueDegrees: number, boundStart: number, boundRampEnd: number,
  boundFallStart: number, boundEnd: number): number {
  const lower: number = (hueDegrees - boundStart) / (boundRampEnd - boundStart);
  const upper: number = (hueDegrees - boundFallStart) / (boundEnd - boundFallStart);
  if (lower < 0) {
    return 0;
  }
  if (lower < 1) {
    return lower;
  }
  if (upper < 0) {
    return 1;
  }
  if (upper < 1) {
    return 1 - upper;
  }
  return 0;
}

/**
 * Red-eye band weight from the upstream hue2 descriptor.
 *
 * Upstream stores the range as [beginRange, beginSaturation, endSaturation,
 * endRange] and wraps any trailing bound that falls below the first by +360.
 * The red-eye entry [265, 305, 25, 55] therefore becomes 265..415 degrees,
 * which is the red band: it ramps in across the reds, holds, then falls off.
 */
export function redEyeWeight(red: number, green: number, blue: number): number {
  const hsl: HslColor = rgbToHsl(red, green, blue);
  let hueDegrees: number = hsl.hue * 360;
  if (hueDegrees < 265) {
    hueDegrees += 360;
  }
  return hueRangeWeight(hueDegrees, 265, 305, 385, 415);
}

/**
 * Red-eye correction ported from the upstream `hue2` path: hue shifted by
 * -90 deg, saturation by -90% and lightness by -70%, weighted by the red band,
 * so only reddish pixels are pulled toward the neighbouring sclera colour.
 *
 * Returns the corrected 0..1 red, green and blue channels.
 */
export function redEyeCorrection(red: number, green: number, blue: number): HslColor {
  const hsl: HslColor = rgbToHsl(red, green, blue);
  const weight: number = redEyeWeight(red, green, blue);
  // Upstream applies the [0, -90, -70] hue2 descriptor: a hue rotation and a
  // desaturating power-curve shift. Colorize is off for this descriptor, so the
  // pixel keeps its original lightness and saturation basis; red is pulled
  // toward the neutral sclera tone while other hues are left alone.
  let hue: number = hsl.hue - weight * (90 / 360);
  if (hue < 0) {
    hue += 1;
  }
  if (hue > 1) {
    hue -= 1;
  }
  const saturationShift: number = saturationCurve(-0.9) * weight;
  const saturation: number = Math.max(0, Math.min(1, hsl.saturation * (1 + saturationShift)));
  return hslToRgb(hue, saturation, hsl.lightness);
}






/**
 * Content-aware healing, ported from the upstream patch-match core.
 *
 * Upstream runs an 8x8 patch match: it converts to YCbCr, builds per-candidate
 * 8x8 FWHT features, looks up each candidate's nearest neighbour, and votes for
 * the translation offset between them. The winning offset says where the
 * replacement texture should be sampled from, which is what repairs a blemish.
 *
 * The graph-cut label optimisation and Poisson blend that upstream applies
 * afterwards are not reproduced here; this returns the voted offset so the
 * caller can paste real surrounding texture over the mask.
 */
export interface HealOffset {
  x: number;
  y: number;
  votes: number;
}

/** ITU-R BT.601 YCbCr, matching the upstream integer rounding. */
export function rgbaToYcbcr(pixels: Uint8Array): Int16Array {
  const out: Int16Array = new Int16Array(pixels.length);
  for (let index: number = 0; index + 3 < pixels.length; index += 4) {
    const red: number = pixels[index];
    const green: number = pixels[index + 1];
    const blue: number = pixels[index + 2];
    out[index] = 16 + Math.floor(65.481 / 255 * red + 128.553 / 255 * green + 24.966 / 255 * blue + 0.5);
    out[index + 1] = 128 - Math.floor(37.797 / 255 * red - 74.203 / 255 * green + 112 / 255 * blue + 0.5);
    out[index + 2] = 128 + Math.floor(112 / 255 * red - 93.786 / 255 * green - 18.214 / 255 * blue + 0.5);
    out[index + 3] = pixels[index + 3];
  }
  return out;
}

const HEAL_PATCH_HALF: number = 3;
const HEAL_PATCH_SIZE: number = 8;
const HEAL_BLOCK_SIZE: number = 64;
const HEAL_Y_COEFFS: number = 12;
const HEAL_CHROMA_COEFFS: number = 4;
const HEAL_FEATURE_COEFF_START: number = 4;
const HEAL_FEATURE_RECORD_SIZE: number = 24;
const HEAL_ALPHA_MIN: number = 200;
const HEAL_MASK_HOLE: number = 255;
const HEAL_KD_LEAF: number = 99;
const HEAL_KD_LEAF_THRESHOLD: number = 16;
const HEAL_INFINITE_COST: number = 1e9;
const HEAL_AXIS_RANGE_MIN: number = 3e4;
const HEAL_AXIS_RANGE_MAX: number = -3e4;
const HEAL_PATCH_SIZE_DIVISOR: number = 15;
const HEAL_DOWNSAMPLE_AVG_TARGET: number = 400;

/**
 * Separable 8x8 fast Walsh-Hadamard transform, in place and unnormalised.
 *
 * Upstream writes a hand-unrolled 160-line variant that reorders the 32
 * high-frequency coefficients. The healing descriptor only ever reads the first
 * 16 coefficients, which are bit-identical to the plain 8x8 transform, so this
 * keeps the readable form and matches upstream's output exactly.
 */
export function fwht64(block: Float64Array): void {
  const line: Float64Array = new Float64Array(HEAL_PATCH_SIZE);
  let step: number = 1;
  while (step < HEAL_PATCH_SIZE) {
    // Rows.
    for (let row: number = 0; row < HEAL_PATCH_SIZE; row++) {
      const offset: number = row * HEAL_PATCH_SIZE;
      for (let index: number = 0; index < HEAL_PATCH_SIZE; index++) {
        line[index] = block[offset + index];
      }
      for (let base: number = 0; base < HEAL_PATCH_SIZE; base += step << 1) {
        for (let k: number = 0; k < step; k++) {
          const left: number = line[base + k];
          const right: number = line[base + k + step];
          line[base + k] = left + right;
          line[base + k + step] = left - right;
        }
      }
      for (let index: number = 0; index < HEAL_PATCH_SIZE; index++) {
        block[offset + index] = line[index];
      }
    }
    // Columns.
    for (let col: number = 0; col < HEAL_PATCH_SIZE; col++) {
      for (let index: number = 0; index < HEAL_PATCH_SIZE; index++) {
        line[index] = block[index * HEAL_PATCH_SIZE + col];
      }
      for (let base: number = 0; base < HEAL_PATCH_SIZE; base += step << 1) {
        for (let k: number = 0; k < step; k++) {
          const left: number = line[base + k];
          const right: number = line[base + k + step];
          line[base + k] = left + right;
          line[base + k + step] = left - right;
        }
      }
      for (let index: number = 0; index < HEAL_PATCH_SIZE; index++) {
        block[index * HEAL_PATCH_SIZE + col] = line[index];
      }
    }
    step <<= 1;
  }
}

/** Wrap a float back into the signed 16-bit range, as the Int16 blocks do. */
function wrapInt16(value: number): number {
  const wrapped: number = Math.round(value) % 65536;
  return wrapped > 32767 ? wrapped - 65536 : wrapped;
}

/**
 * Sample one 8x8 patch into Y/Cb/Cr blocks, or return false when the patch
 * touches the mask or is not fully opaque, exactly as upstream rejects it.
 */
function sampleHealPatch(ycbcr: Int16Array, mask: Uint8Array, col: number, row: number,
  width: number, height: number, yBlock: Float64Array, cbBlock: Float64Array,
  crBlock: Float64Array): boolean {
  let maskOffset: number = (row - HEAL_PATCH_HALF) * width + (col - HEAL_PATCH_HALF);
  let rgbaOffset: number = maskOffset << 2;
  for (let patchRow: number = 0; patchRow < HEAL_PATCH_SIZE; patchRow++) {
    let maskSum: number = 0;
    for (let index: number = 0; index < HEAL_PATCH_SIZE; index++) {
      maskSum += mask[maskOffset + index];
    }
    if (maskSum !== 0) {
      return false;
    }
    for (let index: number = 0; index < HEAL_PATCH_SIZE; index++) {
      if (ycbcr[rgbaOffset + index * 4 + 3] < HEAL_ALPHA_MIN) {
        return false;
      }
    }
    const blockOffset: number = patchRow << 3;
    for (let index: number = 0; index < HEAL_PATCH_SIZE; index++) {
      const sample: number = rgbaOffset + index * 4;
      yBlock[blockOffset + index] = ycbcr[sample];
      cbBlock[blockOffset + index] = ycbcr[sample + 1];
      crBlock[blockOffset + index] = ycbcr[sample + 2];
    }
    rgbaOffset += width << 2;
    maskOffset += width;
  }
  return true;
}

/**
 * Build the flat feature records upstream keeps in one Int16Array: each record is
 * the patch centre followed by 12 luma and 4+4 chroma low-frequency coefficients.
 */
function extractHealFeatures(ycbcr: Int16Array, mask: Uint8Array, width: number,
  height: number): Int16Array {
  const capacity: number = (width - HEAL_PATCH_HALF - 4) * (height - HEAL_PATCH_HALF - 4);
  if (capacity <= 0) {
    return new Int16Array(0);
  }
  const records: Int16Array = new Int16Array(capacity * HEAL_FEATURE_RECORD_SIZE);
  let writeOffset: number = 0;
  const yBlock: Float64Array = new Float64Array(HEAL_BLOCK_SIZE);
  const cbBlock: Float64Array = new Float64Array(HEAL_BLOCK_SIZE);
  const crBlock: Float64Array = new Float64Array(HEAL_BLOCK_SIZE);
  for (let row: number = HEAL_PATCH_HALF; row < height - 4; row++) {
    for (let col: number = HEAL_PATCH_HALF; col < width - 4; col++) {
      if (mask[row * width + col] === HEAL_MASK_HOLE) {
        continue;
      }
      yBlock.fill(0);
      cbBlock.fill(0);
      crBlock.fill(0);
      if (!sampleHealPatch(ycbcr, mask, col, row, width, height, yBlock, cbBlock, crBlock)) {
        continue;
      }
      fwht64(yBlock);
      fwht64(cbBlock);
      fwht64(crBlock);
      records[writeOffset] = col;
      records[writeOffset + 1] = row;
      for (let index: number = 0; index < HEAL_Y_COEFFS; index++) {
        records[writeOffset + HEAL_FEATURE_COEFF_START + index] = wrapInt16(yBlock[index]);
      }
      for (let index: number = 0; index < HEAL_CHROMA_COEFFS; index++) {
        records[writeOffset + HEAL_FEATURE_COEFF_START + HEAL_Y_COEFFS + index] = wrapInt16(cbBlock[index]);
      }
      for (let index: number = 0; index < HEAL_CHROMA_COEFFS; index++) {
        records[writeOffset + HEAL_FEATURE_COEFF_START + HEAL_Y_COEFFS + HEAL_CHROMA_COEFFS + index] =
          wrapInt16(crBlock[index]);
      }
      // Upstream swaps the interleaved Cr/Cb slots once the record is complete,
      // so the chroma ordering inside the descriptor matches the match metric.
      const slotFive: number = records[writeOffset + 5];
      const slotSix: number = records[writeOffset + 6];
      records[writeOffset + 5] = records[writeOffset + 20];
      records[writeOffset + 6] = records[writeOffset + 16];
      records[writeOffset + 16] = slotSix;
      records[writeOffset + 20] = slotFive;
      writeOffset += HEAL_FEATURE_RECORD_SIZE;
    }
  }
  return records.subarray(0, writeOffset);
}

/**
 * Sum of squared coefficient differences, bailing out as soon as the running
 * error reaches `bestError` so the caller can prune.
 */
function healRecordError(candidateOffset: number, queryOffset: number, features: Int16Array,
  bestError: number): number {
  let error: number = 0;
  for (let slot: number = HEAL_FEATURE_COEFF_START; slot < HEAL_FEATURE_RECORD_SIZE; slot += 4) {
    const d0: number = features[queryOffset + slot] - features[candidateOffset + slot];
    const d1: number = features[queryOffset + slot + 1] - features[candidateOffset + slot + 1];
    const d2: number = features[queryOffset + slot + 2] - features[candidateOffset + slot + 2];
    const d3: number = features[queryOffset + slot + 3] - features[candidateOffset + slot + 3];
    error += d0 * d0 + d1 * d1 + d2 * d2 + d3 * d3;
    if (error >= bestError) {
      return error + 1;
    }
  }
  return error;
}

function healSwapRecords(offsetA: number, offsetB: number, features: Int16Array): void {
  for (let slot: number = 0; slot < HEAL_FEATURE_RECORD_SIZE; slot++) {
    const held: number = features[offsetA + slot];
    features[offsetA + slot] = features[offsetB + slot];
    features[offsetB + slot] = held;
  }
}

/**
 * Hoare-partition the records in [lo, hi] around the midpoint record's axis
 * value, returning the index where the two halves meet.
 */
function healPartition(features: Int16Array, axis: number, lo: number, hi: number): number {
  const pivot: number = features[HEAL_FEATURE_RECORD_SIZE * ((lo + hi) >>> 1) + axis];
  while (lo <= hi) {
    while (features[HEAL_FEATURE_RECORD_SIZE * lo + axis] < pivot) {
      lo++;
    }
    while (features[HEAL_FEATURE_RECORD_SIZE * hi + axis] > pivot) {
      hi--;
    }
    if (lo <= hi) {
      if (features[HEAL_FEATURE_RECORD_SIZE * lo + axis] !== features[HEAL_FEATURE_RECORD_SIZE * hi + axis]) {
        healSwapRecords(lo * HEAL_FEATURE_RECORD_SIZE, hi * HEAL_FEATURE_RECORD_SIZE, features);
      }
      lo++;
      hi--;
    }
  }
  return lo;
}

/** Find the axis value that the record at `targetIndex` settles on when partitioned. */
function healPivotValue(features: Int16Array, targetIndex: number, lo: number, hi: number,
  axis: number): number {
  while (lo !== hi) {
    const splitAt: number = healPartition(features, axis, lo, hi);
    if (targetIndex < splitAt) {
      hi = splitAt - 1;
    } else {
      lo = splitAt;
    }
  }
  return features[targetIndex * HEAL_FEATURE_RECORD_SIZE + axis];
}

/**
 * Build the same median-split KD layout upstream uses, stored as flat
 * [axis, pivot, leftSlot, rightSlot] nodes with a [99, lo, hi] leaf marker.
 */
function healBuildKdTree(lo: number, hi: number, nodes: number[], features: Int16Array,
  axisRanges: Float64Array): void {
  if (hi - lo <= HEAL_KD_LEAF_THRESHOLD) {
    nodes.push(HEAL_KD_LEAF, lo, hi);
    return;
  }
  for (let offset: number = 0; offset < HEAL_FEATURE_RECORD_SIZE * 2; offset += 4) {
    axisRanges[offset] = HEAL_AXIS_RANGE_MIN;
    axisRanges[offset + 1] = HEAL_AXIS_RANGE_MAX;
    axisRanges[offset + 2] = HEAL_AXIS_RANGE_MIN;
    axisRanges[offset + 3] = HEAL_AXIS_RANGE_MAX;
  }
  for (let index: number = lo; index <= hi; index++) {
    const base: number = index * HEAL_FEATURE_RECORD_SIZE;
    for (let slot: number = 0; slot < HEAL_FEATURE_RECORD_SIZE; slot++) {
      const value: number = features[base + slot];
      const minSlot: number = axisRanges[slot << 1];
      const maxSlot: number = axisRanges[(slot << 1) + 1];
      if (value < minSlot) {
        axisRanges[slot << 1] = value;
      }
      if (value > maxSlot) {
        axisRanges[(slot << 1) + 1] = value;
      }
    }
  }
  let splitAxis: number = -1;
  let maxSpan: number = -1;
  for (let axis: number = HEAL_FEATURE_COEFF_START; axis < HEAL_FEATURE_RECORD_SIZE; axis++) {
    const span: number = axisRanges[2 * axis + 1] - axisRanges[2 * axis];
    if (span > maxSpan) {
      maxSpan = span;
      splitAxis = axis;
    }
  }
  let midIndex: number = (lo + hi) >> 1;
  const pivot: number = healPivotValue(features, midIndex, lo, hi, splitAxis);
  let firstEqual: number = -1;
  let lastEqual: number = lo;
  for (let index: number = lo; index <= hi; index++) {
    if (features[HEAL_FEATURE_RECORD_SIZE * index + splitAxis] === pivot) {
      if (firstEqual === -1) {
        firstEqual = index;
      }
      lastEqual = index;
    }
  }
  if (lo + 8 < firstEqual && firstEqual - lo > hi - lastEqual) {
    midIndex = firstEqual;
  } else if (lastEqual + 1 < hi - 8) {
    midIndex = lastEqual + 1;
  } else if (hi - lo >= 64) {
    midIndex = midIndex;
  } else {
    nodes.push(HEAL_KD_LEAF, lo, hi);
    return;
  }
  const slot: number = nodes.length;
  nodes.push(splitAxis, pivot, 0, 0);
  nodes[slot + 2] = slot + 4;
  healBuildKdTree(lo, midIndex - 1, nodes, features, axisRanges);
  nodes[slot + 3] = nodes.length;
  healBuildKdTree(midIndex, hi, nodes, features, axisRanges);
}

/**
 * Nearest-neighbour lookup for one record. Upstream walks greedily to a single
 * leaf without backtracking, so this deliberately does the same: it is an
 * approximate nearest neighbour, and reproducing the tree keeps the port
 * behaviourally identical instead of quietly matching a different patch.
 */
function healNearestRecord(index: number, features: Int16Array, nodes: number[],
  minDistSq: number): number {
  const queryOffset: number = index * HEAL_FEATURE_RECORD_SIZE;
  const cutoff: number = minDistSq * minDistSq;
  let node: number = 0;
  let bestError: number = HEAL_INFINITE_COST;
  while (nodes[node] !== HEAL_KD_LEAF) {
    if (features[queryOffset + nodes[node]] < nodes[node + 1]) {
      node = nodes[node + 2];
    } else {
      node = nodes[node + 3];
    }
  }
  let bestIndex: number = -1;
  for (let candidate: number = nodes[node + 1]; candidate <= nodes[node + 2]; candidate++) {
    const candidateOffset: number = candidate * HEAL_FEATURE_RECORD_SIZE;
    const dx: number = features[candidateOffset] - features[queryOffset];
    const dy: number = features[candidateOffset + 1] - features[queryOffset + 1];
    if (dx * dx + dy * dy < cutoff) {
      continue;
    }
    const error: number = healRecordError(candidateOffset, queryOffset, features, bestError);
    if (error < bestError) {
      bestError = error;
      bestIndex = candidate;
    }
  }
  return bestIndex;
}

/** Uniform downsample factor that keeps the average side near the target. */
function healDownsampleFactor(width: number, height: number): number {
  let factor: number = 1;
  while ((width + height) / 2 / factor > HEAL_DOWNSAMPLE_AVG_TARGET) {
    factor++;
  }
  return factor;
}

function healDownsampleRgba(source: Uint8Array, width: number, height: number, factor: number,
  dstWidth: number, dstHeight: number): Uint8Array {
  const out: Uint8Array = new Uint8Array(dstWidth * dstHeight * 4);
  const block: number = Math.max(1, Math.round(1 / factor));
  for (let row: number = 0; row < dstHeight; row++) {
    for (let col: number = 0; col < dstWidth; col++) {
      const blockWidth: number = Math.min(block, width - col * block);
      const blockHeight: number = Math.min(block, height - row * block);
      let alphaSum: number = 0;
      let redSum: number = 0;
      let greenSum: number = 0;
      let blueSum: number = 0;
      for (let dy: number = 0; dy < blockHeight; dy++) {
        for (let dx: number = 0; dx < blockWidth; dx++) {
          const sample: number = ((block * row + dy) * width + (block * col + dx)) << 2;
          const alpha: number = source[sample + 3];
          alphaSum += alpha;
          redSum += alpha * source[sample];
          greenSum += alpha * source[sample + 1];
          blueSum += alpha * source[sample + 2];
        }
      }
      const target: number = (row * dstWidth + col) << 2;
      if (alphaSum !== 0) {
        const inverse: number = 1 / alphaSum;
        out[target] = Math.floor(redSum * inverse);
        out[target + 1] = Math.floor(greenSum * inverse);
        out[target + 2] = Math.floor(blueSum * inverse);
        out[target + 3] = Math.floor(alphaSum / (blockWidth * blockHeight));
      }
    }
  }
  return out;
}

function healDownsampleMask(source: Uint8Array, width: number, height: number, factor: number,
  dstWidth: number, dstHeight: number): Uint8Array {
  const out: Uint8Array = new Uint8Array(dstWidth * dstHeight);
  const block: number = Math.max(1, Math.round(1 / factor));
  for (let row: number = 0; row < dstHeight; row++) {
    for (let col: number = 0; col < dstWidth; col++) {
      const blockWidth: number = Math.min(block, width - col * block);
      const blockHeight: number = Math.min(block, height - row * block);
      let sum: number = 0;
      for (let dy: number = 0; dy < blockHeight; dy++) {
        for (let dx: number = 0; dx < blockWidth; dx++) {
          sum += source[(block * row + dy) * width + (block * col + dx)];
        }
      }
      out[row * dstWidth + col] = Math.round(sum / (blockWidth * blockHeight));
    }
  }
  return out;
}

/** Tight bounds of the masked content, used to scale the minimum match distance. */
interface HealBounds {
  left: number;
  top: number;
  width: number;
  height: number;
}

function healContentBounds(mask: Uint8Array, width: number, height: number): HealBounds {
  const empty: HealBounds = { left: 0, top: 0, width: 0, height: 0 };
  let top: number = 0;
  while (top < height) {
    let rowOr: number = 0;
    for (let col: number = 0; col < width; col++) {
      rowOr |= mask[top * width + col];
    }
    if (rowOr !== 0) {
      break;
    }
    top++;
  }
  if (top === height) {
    return empty;
  }
  let bottom: number = height;
  while (bottom > top) {
    let rowOr: number = 0;
    for (let col: number = 0; col < width; col++) {
      rowOr |= mask[(bottom - 1) * width + col];
    }
    if (rowOr !== 0) {
      break;
    }
    bottom--;
  }
  let left: number = 0;
  while (left < width) {
    let columnOr: number = 0;
    for (let row: number = top; row < bottom; row++) {
      columnOr |= mask[row * width + left];
    }
    if (columnOr !== 0) {
      break;
    }
    left++;
  }
  let right: number = width;
  while (right > left) {
    let columnOr: number = 0;
    for (let row: number = top; row < bottom; row++) {
      columnOr |= mask[row * width + right - 1];
    }
    if (columnOr !== 0) {
      break;
    }
    right--;
  }
  return { left: left, top: top, width: width - left - (width - right), height: height - top - (height - bottom) };
}

/**
 * A candidate translation for one hole pixel: sample from (col + x, row + y).
 */
export interface HealPatch {
  x: number;
  y: number;
  votes: number;
}

/**
 * The healed region, expressed the way upstream consumes it: a set of candidate
 * patch translations plus the offset chosen for each hole pixel.
 *
 * Upstream does not repair a blemish with a single shift. It votes for many
 * candidate offsets, keeps a diverse subset of them, and labels every hole pixel
 * with one that lands on real source texture before the graph-cut stage refines
 * those labels. Returning the per-pixel labels is what makes the result usable:
 * one global offset only ever repairs the pixels that happen to line up.
 */
export interface HealPlan {
  patches: HealPatch[];
  labels: Int32Array;
  holeCols: Int32Array;
  holeRows: Int32Array;
  sourceWidth: number;
  sourceHeight: number;
  downsample: number;
}

const HEAL_LABEL_SOURCE: number = -1;
const HEAL_LABEL_HOLE_BASE: number = 0;
const HEAL_MAX_SEED_OFFSETS: number = 60;
const HEAL_MIN_OFFSET_DIST_SQ: number = 25;

function healIsInBounds(col: number, row: number, width: number, height: number): boolean {
  return col >= 0 && col < width && row >= 0 && row < height;
}

/** Fraction of hole pixels whose source sample lands on real content. */
function healOverlapRatio(patch: HealPatch, labelGrid: Int32Array, holeCols: Int32Array,
  holeRows: Int32Array, holeCount: number, width: number, height: number): number {
  if (holeCount === 0) {
    return 0;
  }
  let overlaps: number = 0;
  for (let index: number = 0; index < holeCount; index++) {
    const col: number = holeCols[index] + patch.x;
    const row: number = holeRows[index] + patch.y;
    if (healIsInBounds(col, row, width, height) && labelGrid[row * width + col] === HEAL_LABEL_SOURCE) {
      overlaps++;
    }
  }
  return overlaps / holeCount;
}

/**
 * Pick the highest-voted offset that is far enough from the patches already
 * chosen and that actually covers the hole with source pixels.
 */
function healPickDistantPatch(patches: HealPatch[], minDistSq: number, votes: HealPatch[],
  labelGrid: Int32Array, holeCols: Int32Array, holeRows: Int32Array, holeCount: number,
  width: number, height: number, col: number, row: number): HealPatch | undefined {
  for (let index: number = 0; index < votes.length; index++) {
    const candidate: HealPatch = votes[index];
    if (col >= 0 && !(
      healIsInBounds(col + candidate.x, row + candidate.y, width, height) &&
      labelGrid[(row + candidate.y) * width + col + candidate.x] === HEAL_LABEL_SOURCE)) {
      continue;
    }
    if (healOverlapRatio(candidate, labelGrid, holeCols, holeRows, holeCount, width, height) <= 0) {
      continue;
    }
    let farEnough: boolean = true;
    for (let chosen: number = 0; chosen < patches.length; chosen++) {
      const dx: number = candidate.x - patches[chosen].x;
      const dy: number = candidate.y - patches[chosen].y;
      if (dx * dx + dy * dy < minDistSq) {
        farEnough = false;
        break;
      }
    }
    if (farEnough) {
      return candidate;
    }
  }
  return undefined;
}

/**
 * Vote for the patch translations that best repair the masked region, and label
 * every hole pixel with one that lands on real texture.
 */
export function healPatchPlan(pixels: Uint8Array, mask: Uint8Array, width: number,
  height: number): HealPlan | undefined {
  const empty: HealPlan = {
    patches: [], labels: new Int32Array(0), holeCols: new Int32Array(0),
    holeRows: new Int32Array(0), sourceWidth: width, sourceHeight: height, downsample: 1
  };
  if (width < HEAL_PATCH_SIZE || height < HEAL_PATCH_SIZE) {
    return empty;
  }
  const factor: number = healDownsampleFactor(width, height);
  const dsWidth: number = Math.floor(width / factor);
  const dsHeight: number = Math.floor(height / factor);
  if (dsWidth < HEAL_PATCH_SIZE || dsHeight < HEAL_PATCH_SIZE) {
    return empty;
  }
  const source: Uint8Array = factor > 1 ?
    healDownsampleRgba(pixels, width, height, factor, dsWidth, dsHeight) : pixels;
  const dsMask: Uint8Array = factor > 1 ?
    healDownsampleMask(mask, width, height, factor, dsWidth, dsHeight) : mask;
  for (let index: number = 0; index < dsMask.length; index++) {
    dsMask[index] = dsMask[index] < 1 ? 0 : 255;
  }
  const bounds: HealBounds = healContentBounds(dsMask, dsWidth, dsHeight);
  if (bounds.width === 0 || bounds.height === 0) {
    return empty;
  }
  const minDistSq: number = Math.round((bounds.width + bounds.height) / 2 / HEAL_PATCH_SIZE_DIVISOR);
  const ycbcr: Int16Array = rgbaToYcbcr(source);
  const features: Int16Array = extractHealFeatures(ycbcr, dsMask, dsWidth, dsHeight);
  const featureCount: number = features.length / HEAL_FEATURE_RECORD_SIZE;
  if (featureCount === 0) {
    return empty;
  }
  const nodes: number[] = [];
  healBuildKdTree(0, featureCount - 1, nodes, features,
    new Float64Array(2 * HEAL_FEATURE_RECORD_SIZE));
  const histogram: Float64Array = new Float64Array(dsWidth * dsHeight * 4);
  for (let index: number = 0; index < featureCount; index++) {
    const nearest: number = healNearestRecord(index, features, nodes, minDistSq);
    if (nearest === -1) {
      continue;
    }
    const queryOffset: number = index * HEAL_FEATURE_RECORD_SIZE;
    const nearestOffset: number = nearest * HEAL_FEATURE_RECORD_SIZE;
    const offsetX: number = features[nearestOffset] - features[queryOffset];
    const offsetY: number = features[nearestOffset + 1] - features[queryOffset + 1];
    histogram[(dsHeight + offsetY) * 2 * dsWidth + (dsWidth + offsetX)] += 1;
  }
  // Sparse votes, strongest first, exactly as upstream sorts the histogram.
  const votes: HealPatch[] = [];
  for (let voteIndex: number = 0; voteIndex < histogram.length; voteIndex++) {
    if (histogram[voteIndex] > 0) {
      const row: number = Math.floor(voteIndex / (2 * dsWidth));
      votes.push({
        x: voteIndex - row * 2 * dsWidth - dsWidth,
        y: row - dsHeight,
        votes: histogram[voteIndex]
      });
    }
  }
  votes.sort((left: HealPatch, right: HealPatch): number => right.votes - left.votes);
  if (votes.length === 0) {
    return empty;
  }
  // Label the hole: masked pixels are hole ids, transparent pixels are excluded
  // from sampling, and everything else is usable source.
  const labelGrid: Int32Array = new Int32Array(dsWidth * dsHeight);
  let holeCount: number = 0;
  for (let pixel: number = 0; pixel < dsWidth * dsHeight; pixel++) {
    if (dsMask[pixel] === HEAL_MASK_HOLE) {
      labelGrid[pixel] = HEAL_LABEL_HOLE_BASE + holeCount;
      holeCount++;
    } else if (source[(pixel << 2) + 3] < HEAL_ALPHA_MIN) {
      labelGrid[pixel] = -2;
    } else {
      labelGrid[pixel] = HEAL_LABEL_SOURCE;
    }
  }
  if (holeCount === 0) {
    return empty;
  }
  const holeCols: Int32Array = new Int32Array(holeCount);
  const holeRows: Int32Array = new Int32Array(holeCount);
  for (let pixel: number = 0; pixel < dsWidth * dsHeight; pixel++) {
    const label: number = labelGrid[pixel];
    if (label >= HEAL_LABEL_HOLE_BASE) {
      holeCols[label] = pixel % dsWidth;
      holeRows[label] = Math.floor(pixel / dsWidth);
    }
  }
  // Keep a diverse set of offsets so the hole can be covered from several sides.
  const patches: HealPatch[] = [];
  for (let seed: number = 0; seed < HEAL_MAX_SEED_OFFSETS; seed++) {
    const candidate: HealPatch | undefined = healPickDistantPatch(patches,
      HEAL_MIN_OFFSET_DIST_SQ, votes, labelGrid, holeCols, holeRows, holeCount,
      dsWidth, dsHeight, -1, -1);
    if (candidate === undefined) {
      break;
    }
    patches.push(candidate);
  }
  if (patches.length === 0) {
    return empty;
  }
  // Every hole pixel takes the strongest patch that lands on source texture.
  const labels: Int32Array = new Int32Array(holeCount);
  for (let index: number = 0; index < holeCount; index++) {
    const col: number = holeCols[index];
    const row: number = holeRows[index];
    let chosen: number = -1;
    for (let attempt: number = 0; attempt < 100; attempt++) {
      for (let index2: number = 0; index2 < patches.length; index2++) {
        const sampleCol: number = col + patches[index2].x;
        const sampleRow: number = row + patches[index2].y;
        if (healIsInBounds(sampleCol, sampleRow, dsWidth, dsHeight) &&
          labelGrid[sampleRow * dsWidth + sampleCol] === HEAL_LABEL_SOURCE) {
          chosen = index2;
          break;
        }
      }
      if (chosen >= 0) {
        break;
      }
      // Widen the set when the current patches cannot cover this pixel.
      const fallback: HealPatch | undefined = healPickDistantPatch(patches, 0, votes, labelGrid,
        holeCols, holeRows, holeCount, dsWidth, dsHeight, col, row);
      if (fallback === undefined) {
        return empty;
      }
      patches.push(fallback);
    }
    if (chosen < 0) {
      return empty;
    }
    labels[index] = chosen;
  }
  return {
    patches: patches,
    labels: labels,
    holeCols: holeCols,
    holeRows: holeRows,
    sourceWidth: width,
    sourceHeight: height,
    downsample: factor
  };
}

/**
 * Apply a heal plan to full-resolution pixels, sampling the chosen patch for each
 * hole pixel. This is upstream's `pasteLabeledPatches` without the graph-cut
 * refinement and Poisson smoothing that follow it.
 */
export function applyHealPlan(plan: HealPlan, pixels: Uint8Array, mask: Uint8Array,
  width: number, height: number): Uint8Array {
  const output: Uint8Array = new Uint8Array(pixels.length);
  output.set(pixels);
  if (plan.patches.length === 0) {
    return output;
  }
  const factor: number = Math.max(1, plan.downsample);
  for (let index: number = 0; index < plan.labels.length; index++) {
    const holeCol: number = plan.holeCols[index] * factor;
    const holeRow: number = plan.holeRows[index] * factor;
    const patch: HealPatch = plan.patches[plan.labels[index]];
    const sampleCol: number = holeCol + patch.x * factor;
    const sampleRow: number = holeRow + patch.y * factor;
    if (!healIsInBounds(sampleCol, sampleRow, width, height) ||
      !healIsInBounds(holeCol, holeRow, width, height)) {
      continue;
    }
    const target: number = (holeRow * width + holeCol) << 2;
    const source: number = (sampleRow * width + sampleCol) << 2;
    output[target] = pixels[source];
    output[target + 1] = pixels[source + 1];
    output[target + 2] = pixels[source + 2];
    output[target + 3] = pixels[source + 3];
  }
  return output;
}



const HEAL_SOURCE_TREE: number = 1;
const HEAL_SINK_TREE: number = 2;
const HEAL_INF_BOTTLENECK: number = 1e30;
const HEAL_INF_DISTANCE: number = 1e9;

/**
 * Ring-buffer mask: the largest `2^n - 1` not below the request, matching
 * upstream's `nextPowerOfTwoCapacity`. Rounding up instead would leave the
 * buffer one slot short of the capacity the caller asked for.
 */
function healNextPowerOfTwo(requested: number): number {
  let value: number = requested;
  value |= value >> 1;
  value |= value >> 2;
  value |= value >> 4;
  value |= value >> 8;
  value |= value >> 16;
  return value;
}

/** Ring queue with O(1) membership, remove and tail peek, as upstream uses. */
class HealIndexedQueue {
  private buffer: Uint32Array;
  private positions: Uint32Array;
  private mask: number;
  private head: number = 0;
  private tail: number = 0;

  constructor(capacity: number) {
    this.mask = healNextPowerOfTwo(capacity);
    this.buffer = new Uint32Array(this.mask + 1);
    this.positions = new Uint32Array(this.mask + 1);
  }

  top(): number {
    return this.buffer[this.head];
  }

  push(value: number): void {
    if (this.positions[value] !== 0) {
      return;
    }
    this.positions[value] = this.tail + 1;
    const at: number = this.tail;
    this.buffer[at] = value;
    this.tail = (at + 1) & this.mask;
  }

  pop(): number {
    const at: number = this.head;
    const value: number = this.buffer[at];
    this.positions[value] = 0;
    this.head = (at + 1) & this.mask;
    return value;
  }

  isEmpty(): boolean {
    return this.head === this.tail;
  }

  remove(value: number): void {
    const pos: number = this.positions[value] - 1;
    if (pos === -1) {
      return;
    }
    this.positions[value] = 0;
    if (pos === this.head) {
      this.pop();
      return;
    }
    const moved: number = this.pop();
    this.buffer[pos] = moved;
    this.positions[moved] = pos + 1;
  }
}

interface HealCutResult {
  cut: Int32Array | undefined;
  flow: number;
}

interface HealFlowState {
  edges: Uint32Array;
  residual: Float64Array;
  firstEdge: Uint32Array;
  tree: Uint8Array;
  parentEdge: Uint32Array;
  dist: Uint32Array;
  timestamp: Uint32Array;
}

function healSetParent(parent: number, parentEdge: number, child: number, state: HealFlowState): void {
  state.tree[child] = state.tree[parent];
  state.parentEdge[child] = parentEdge + 1;
  state.dist[child] = state.dist[parent] + 1;
  state.timestamp[child] = state.timestamp[parent];
}

function healBuildAdjacency(nodeCount: number, entryCount: number, source: number, sink: number,
  endpoints: Int32Array, caps: Float64Array): HealFlowState {
  const firstEdge: Uint32Array = new Uint32Array(nodeCount);
  const edges: Uint32Array = new Uint32Array(Math.max(1, entryCount) * 4);
  const residual: Float64Array = new Float64Array(edges.buffer);
  let cursor: number = 0;
  for (let entry: number = 0; entry < entryCount; entry += 2) {
    const u: number = endpoints[entry];
    const v: number = endpoints[entry + 1];
    edges[cursor] = v;
    residual[(cursor + 2) >> 1] = caps[entry];
    edges[cursor + 1] = firstEdge[u];
    firstEdge[u] = cursor + 1;
    cursor += 4;
    edges[cursor] = u;
    residual[(cursor + 2) >> 1] = caps[entry + 1];
    edges[cursor + 1] = firstEdge[v];
    firstEdge[v] = cursor + 1;
    cursor += 4;
  }
  return {
    edges: edges,
    residual: residual,
    firstEdge: firstEdge,
    tree: new Uint8Array(nodeCount),
    parentEdge: new Uint32Array(nodeCount),
    dist: new Uint32Array(nodeCount),
    timestamp: new Uint32Array(nodeCount)
  };
}

function healRecomputeDistance(node: number, source: number, sink: number, state: HealFlowState,
  time: number): number {
  const edges: Uint32Array = state.edges;
  const parentEdge: Uint32Array = state.parentEdge;
  const timestamp: Uint32Array = state.timestamp;
  const dist: Uint32Array = state.dist;
  let startNode: number = node;
  let edge: number = parentEdge[node] - 1;
  let steps: number = 0;
  while (edge !== -1 && timestamp[node] !== time) {
    node = edges[edge ^ 4];
    edge = parentEdge[node] - 1;
    steps++;
  }
  if (edge === -1 && node !== source && node !== sink) {
    return HEAL_INF_DISTANCE;
  }
  const baseDist: number = dist[node] + steps;
  steps = 0;
  edge = parentEdge[startNode] - 1;
  while (startNode !== node) {
    dist[startNode] = baseDist - steps;
    steps++;
    timestamp[startNode] = time;
    startNode = edges[edge ^ 4];
    edge = parentEdge[startNode] - 1;
  }
  return baseDist;
}

/** Grow the source and sink trees until an opposing boundary edge appears. */
function healGrowActiveTree(active: HealIndexedQueue, state: HealFlowState,
  source: number, sink: number, time: number): number {
  const edges: Uint32Array = state.edges;
  const residual: Float64Array = state.residual;
  while (!active.isEmpty()) {
    const node: number = active.top();
    const nodeTree: number = state.tree[node];
    let edge: number = state.firstEdge[node] - 1;
    let boundaryEdge: number = -1;
    while (edge !== -1) {
      const neighbor: number = edges[edge];
      const neighborTree: number = state.tree[neighbor];
      const oriented: number = (edge ^ ((nodeTree - 1) << 2)) as number;
      if (residual[(oriented + 2) >> 1] !== 0) {
        if (neighborTree === 0) {
          healSetParent(node, edge, neighbor, state);
          active.push(neighbor);
        } else if (neighborTree === nodeTree && state.timestamp[neighbor] <= state.timestamp[node] &&
          state.dist[neighbor] > state.dist[node]) {
          healSetParent(node, edge, neighbor, state);
        } else if (neighborTree !== nodeTree) {
          boundaryEdge = oriented;
        }
      }
      edge = edges[edge + 1] - 1;
    }
    if (boundaryEdge !== -1) {
      return boundaryEdge;
    }
    active.pop();
  }
  return -1;
}

function healBuildAugmentingPath(boundaryEdge: number, path: Uint32Array, state: HealFlowState): number {
  const edges: Uint32Array = state.edges;
  const parentEdge: Uint32Array = state.parentEdge;
  let pathLen: number = 0;
  let cursor: number = boundaryEdge;
  while (cursor !== -1) {
    path[pathLen] = cursor;
    pathLen++;
    cursor = parentEdge[edges[cursor ^ 4]] - 1;
  }
  const half: number = pathLen >> 1;
  for (let k: number = 0; k < half; k++) {
    const swap: number = path[k];
    path[k] = path[pathLen - k - 1];
    path[pathLen - k - 1] = swap;
  }
  cursor = parentEdge[edges[boundaryEdge]] - 1;
  while (cursor !== -1) {
    path[pathLen] = cursor ^ 4;
    pathLen++;
    cursor = parentEdge[edges[cursor ^ 4]] - 1;
  }
  return pathLen;
}

function healAugmentAlongPath(path: Uint32Array, pathLen: number, state: HealFlowState,
  orphans: HealIndexedQueue): number {
  const edges: Uint32Array = state.edges;
  const residual: Float64Array = state.residual;
  const tree: Uint8Array = state.tree;
  const parentEdge: Uint32Array = state.parentEdge;
  let bottleneck: number = HEAL_INF_BOTTLENECK;
  for (let k: number = 0; k < pathLen; k++) {
    bottleneck = Math.min(bottleneck, residual[(path[k] + 2) >> 1]);
  }
  for (let k: number = 0; k < pathLen; k++) {
    const forwardEdge: number = path[k];
    const reverseEdge: number = forwardEdge ^ 4;
    const tailNode: number = edges[reverseEdge];
    const headNode: number = edges[forwardEdge];
    residual[(forwardEdge + 2) >> 1] -= bottleneck;
    residual[(reverseEdge + 2) >> 1] += bottleneck;
    if (residual[(forwardEdge + 2) >> 1] === 0 && tree[tailNode] === tree[headNode]) {
      if (tree[tailNode] === HEAL_SOURCE_TREE) {
        parentEdge[headNode] = 0;
        orphans.push(headNode);
      }
      if (tree[tailNode] === HEAL_SINK_TREE) {
        parentEdge[tailNode] = 0;
        orphans.push(tailNode);
      }
    }
  }
  return bottleneck;
}

function healAdoptOrphans(orphans: HealIndexedQueue, active: HealIndexedQueue, state: HealFlowState,
  time: number, source: number, sink: number): void {
  const edges: Uint32Array = state.edges;
  const residual: Float64Array = state.residual;
  while (!orphans.isEmpty()) {
    const orphan: number = orphans.pop();
    const orphanTree: number = state.tree[orphan];
    let edge: number = state.firstEdge[orphan] - 1;
    const treeOffset: number = orphanTree === HEAL_SOURCE_TREE ? 4 : 0;
    let bestParent: number = 0;
    let bestParentEdge: number = 0;
    let bestDist: number = HEAL_INF_DISTANCE;
    while (edge !== -1) {
      const neighbor: number = edges[edge];
      const reverseNeighborEdge: number = edge ^ 4;
      const oriented: number = (edge ^ treeOffset) as number;
      if (state.tree[neighbor] === orphanTree && residual[(oriented + 2) >> 1] > 0) {
        const candidate: number = healRecomputeDistance(neighbor, source, sink, state, time) + 1;
        if (candidate < bestDist) {
          bestParent = neighbor;
          bestParentEdge = reverseNeighborEdge;
          bestDist = candidate;
        }
      }
      edge = edges[edge + 1] - 1;
    }
    if (bestParentEdge !== 0) {
      healSetParent(bestParent, bestParentEdge, orphan, state);
      continue;
    }
    edge = state.firstEdge[orphan] - 1;
    while (edge !== -1) {
      const neighbor: number = edges[edge];
      const oriented: number = (edge ^ treeOffset) as number;
      if (state.tree[neighbor] === orphanTree) {
        if (residual[(oriented + 2) >> 1] > 0) {
          active.push(neighbor);
        }
        if (state.parentEdge[neighbor] === edge + 1) {
          state.parentEdge[neighbor] = 0;
          orphans.push(neighbor);
        }
      }
      edge = edges[edge + 1] - 1;
    }
    state.tree[orphan] = 0;
    active.remove(orphan);
  }
}

function healCollectTreeCutEdges(tree: Uint8Array, entryCount: number,
  endpoints: Int32Array): Int32Array {
  const cut: number[] = [];
  for (let entry: number = 0; entry < entryCount; entry += 2) {
    const u: number = endpoints[entry];
    const v: number = endpoints[entry + 1];
    if (tree[u] === HEAL_SOURCE_TREE && tree[v] !== HEAL_SOURCE_TREE) {
      cut.push(entry >> 1);
    }
    if (tree[v] === HEAL_SOURCE_TREE && tree[u] !== HEAL_SOURCE_TREE) {
      cut.push((entryCount + entry) >> 1);
    }
  }
  return Int32Array.from(cut);
}

/**
 * Minimum s-t cut over a small dense-ish graph, used to relabel heal patches so
 * neighbouring hole pixels prefer the same source. Ported from upstream's
 * `computeMinCut`: push-relabel with orphan adoption on a four-slot edge layout.
 */
export function healMinCut(nodeCount: number, entryCount: number, source: number, sink: number,
  endpoints: Int32Array, caps: Float64Array, flowLimit: number): HealCutResult {
  const state: HealFlowState = healBuildAdjacency(nodeCount, entryCount, source, sink, endpoints, caps);
  const path: Uint32Array = new Uint32Array(nodeCount);
  const active: HealIndexedQueue = new HealIndexedQueue(nodeCount);
  const orphans: HealIndexedQueue = new HealIndexedQueue(nodeCount);
  let time: number = 1;
  let flow: number = 0;
  active.push(source);
  active.push(sink);
  state.tree[source] = HEAL_SOURCE_TREE;
  state.tree[sink] = HEAL_SINK_TREE;
  state.dist[source] = 0;
  state.dist[sink] = 0;
  state.timestamp[source] = 1;
  state.timestamp[sink] = 1;
  while (true) {
    const boundaryEdge: number = healGrowActiveTree(active, state, source, sink, time);
    if (boundaryEdge === -1) {
      break;
    }
    time++;
    const pathLen: number = healBuildAugmentingPath(boundaryEdge, path, state);
    flow += healAugmentAlongPath(path, pathLen, state, orphans);
    if (flow >= flowLimit) {
      return { cut: undefined, flow: flow };
    }
    healAdoptOrphans(orphans, active, state, time, source, sink);
  }
  return { cut: healCollectTreeCutEdges(state.tree, entryCount, endpoints), flow: flow };
}

const HEAL_POISSON_UNKNOWN: number = -1;
const HEAL_POISSON_TRANSPARENT: number = -2;
const HEAL_POISSON_ALPHA_MIN: number = 200;
const HEAL_POISSON_SOR_RELAXATION: number = 1.8;

/**
 * Compressed-row sparse matrix holding the Poisson system's diagonal separately,
 * matching the layout upstream's solver expects: `rowPtr` indexes `values`/
 * `colIndices`, and `offDiag*` mirror the same rows without the diagonal.
 */
class HealSparseMatrix {
  private rowCount: number;
  private values: number[] = [];
  private rowPtr: number[] = [0];
  private colIndices: number[] = [];
  private offDiagValues: number[] = [];
  private offDiagRowPtr: number[] = [0];
  private offDiagColIndices: number[] = [];
  private diagInverse: number[] = [];

  constructor(rowCount: number) {
    this.rowCount = rowCount;
  }

  addRow(rowValues: number[], rowCols: number[], entryCount: number): void {
    const rowIndex: number = this.rowPtr.length - 1;
    for (let index: number = 0; index < entryCount; index++) {
      const value: number = rowValues[index];
      const col: number = rowCols[index];
      this.values.push(value);
      this.colIndices.push(col);
      if (col === rowIndex) {
        this.diagInverse.push(value === 0 ? 0 : 1 / value);
      } else {
        this.offDiagValues.push(value);
        this.offDiagColIndices.push(col);
      }
    }
    this.rowPtr.push(this.values.length);
    this.offDiagRowPtr.push(this.offDiagValues.length);
  }

  /** Successive over-relaxation over three interleaved channels at once. */
  solveVector3(solution: Float64Array, rhs: Float64Array, tolerance: number,
    maxIterations: number): void {
    const relaxation: number = HEAL_POISSON_SOR_RELAXATION;
    const damp: number = 1 - relaxation;
    const rows: number = this.rowCount;
    for (let iteration: number = 0; iteration < maxIterations; iteration++) {
      let weightedDeltaSq: number = 0;
      for (let row: number = 0; row < rows; row++) {
        const base: number = row * 3;
        let rhs0: number = rhs[base];
        let rhs1: number = rhs[base + 1];
        let rhs2: number = rhs[base + 2];
        const offStart: number = this.offDiagRowPtr[row];
        const offEnd: number = this.offDiagRowPtr[row + 1];
        for (let off: number = offStart; off < offEnd; off++) {
          const coeff: number = this.offDiagValues[off];
          const colBase: number = this.offDiagColIndices[off] * 3;
          rhs0 -= coeff * solution[colBase];
          rhs1 -= coeff * solution[colBase + 1];
          rhs2 -= coeff * solution[colBase + 2];
        }
        const scale: number = this.diagInverse[row] * relaxation;
        const next0: number = solution[base] * damp + rhs0 * scale;
        const next1: number = solution[base + 1] * damp + rhs1 * scale;
        const next2: number = solution[base + 2] * damp + rhs2 * scale;
        const delta0: number = next0 - solution[base];
        const delta1: number = next1 - solution[base + 1];
        const delta2: number = next2 - solution[base + 2];
        weightedDeltaSq += 0.4 * delta0 * delta0 + 0.5 * delta1 * delta1 + 0.1 * delta2 * delta2;
        solution[base] = next0;
        solution[base + 1] = next1;
        solution[base + 2] = next2;
      }
      if (weightedDeltaSq / Math.max(1, rows) < tolerance) {
        return;
      }
    }
  }
}

/**
 * Blend a pasted region into its surroundings with a Poisson solve, so the fill
 * fades into the original pixels instead of showing a hard patch edge.
 *
 * Ported from upstream's `solvePoissonFill`: the region is the set of pixels to
 * solve for, surrounding opaque pixels contribute a Dirichlet boundary, and
 * interior neighbours contribute the gradient term. Alpha is left untouched.
 */
export function healPoissonBlend(pixels: Uint8Array, regionMask: Uint8Array, width: number,
  height: number, iterations: number): void {
  const pixelCount: number = width * height;
  const unknownIndex: Int32Array = new Int32Array(pixelCount);
  let unknownCount: number = 0;
  for (let index: number = 0; index < pixelCount; index++) {
    if (regionMask[index] !== 0) {
      unknownIndex[index] = unknownCount;
      unknownCount++;
    } else if (pixels[(index << 2) + 3] < HEAL_POISSON_ALPHA_MIN) {
      unknownIndex[index] = HEAL_POISSON_TRANSPARENT;
    } else {
      unknownIndex[index] = HEAL_POISSON_UNKNOWN;
    }
  }
  if (unknownCount === 0) {
    return;
  }
  const matrix: HealSparseMatrix = new HealSparseMatrix(unknownCount);
  const rhs: Float64Array = new Float64Array(3 * unknownCount);
  const solution: Float64Array = new Float64Array(3 * unknownCount);
  const neighborOffsets: number[] = [-width, -1, 1, width];
  for (let row: number = 0; row < height; row++) {
    for (let col: number = 0; col < width; col++) {
      const pixelIndex: number = row * width + col;
      const rgbaOffset: number = pixelIndex << 2;
      const unknown: number = unknownIndex[pixelIndex];
      if (unknown === HEAL_POISSON_UNKNOWN || unknown === HEAL_POISSON_TRANSPARENT) {
        continue;
      }
      const rgbBase: number = unknown * 3;
      let neighborCount: number = 0;
      let diagSlot: number = 0;
      const rowCoeffs: number[] = [];
      const rowCols: number[] = [];
      for (let direction: number = 0; direction < 4; direction++) {
        if (direction === 2) {
          diagSlot = rowCoeffs.length;
          rowCoeffs.push(0);
          rowCols.push(unknown);
        }
        const neighborIndex: number = pixelIndex + neighborOffsets[direction];
        if (neighborIndex < 0 || neighborIndex >= pixelCount) {
          continue;
        }
        if (direction === 0 && row === 0) {
          continue;
        }
        if (direction === 1 && col === 0) {
          continue;
        }
        if (direction === 2 && col === width - 1) {
          continue;
        }
        if (direction === 3 && row === height - 1) {
          continue;
        }
        const neighborUnknown: number = unknownIndex[neighborIndex];
        if (neighborUnknown === HEAL_POISSON_TRANSPARENT) {
          continue;
        }
        const neighborOffset: number = neighborIndex << 2;
        neighborCount++;
        if (neighborUnknown === HEAL_POISSON_UNKNOWN) {
          rhs[rgbBase] += pixels[neighborOffset];
          rhs[rgbBase + 1] += pixels[neighborOffset + 1];
          rhs[rgbBase + 2] += pixels[neighborOffset + 2];
        } else {
          rowCoeffs.push(-1);
          rowCols.push(neighborUnknown);
          if (regionMask[pixelIndex] === regionMask[neighborIndex]) {
            rhs[rgbBase] += pixels[rgbaOffset] - pixels[neighborOffset];
            rhs[rgbBase + 1] += pixels[rgbaOffset + 1] - pixels[neighborOffset + 1];
            rhs[rgbBase + 2] += pixels[rgbaOffset + 2] - pixels[neighborOffset + 2];
          }
        }
      }
      rowCoeffs[diagSlot] = neighborCount;
      matrix.addRow(rowCoeffs, rowCols, rowCoeffs.length);
    }
  }
  for (let index: number = 0; index < pixelCount; index++) {
    if (unknownIndex[index] === HEAL_POISSON_UNKNOWN) {
      continue;
    }
    const rgbaOffset: number = index << 2;
    const solutionOffset: number = unknownIndex[index] * 3;
    solution[solutionOffset] = pixels[rgbaOffset];
    solution[solutionOffset + 1] = pixels[rgbaOffset + 1];
    solution[solutionOffset + 2] = pixels[rgbaOffset + 2];
  }
  matrix.solveVector3(solution, rhs, 5e-5, Math.max(1, Math.round(iterations)));
  for (let index: number = 0; index < pixelCount; index++) {
    const unknown: number = unknownIndex[index];
    if (unknown === HEAL_POISSON_UNKNOWN) {
      continue;
    }
    const solutionOffset: number = unknown * 3;
    const rgbaOffset: number = index << 2;
    if (pixels[rgbaOffset + 3] !== 255) {
      continue;
    }
    pixels[rgbaOffset] = Math.round(Math.max(0, Math.min(255, solution[solutionOffset])));
    pixels[rgbaOffset + 1] = Math.round(Math.max(0, Math.min(255, solution[solutionOffset + 1])));
    pixels[rgbaOffset + 2] = Math.round(Math.max(0, Math.min(255, solution[solutionOffset + 2])));
  }
}

/**
 * Vote for the single strongest translation offset.
 *
 * Retained for callers that only need a directional hint; `healPatchPlan` is
 * what the heal tool itself uses.
 */
export function healVotedOffset(pixels: Uint8Array, mask: Uint8Array, width: number,
  height: number): HealOffset {
  if (width < HEAL_PATCH_SIZE || height < HEAL_PATCH_SIZE) {
    return { x: 0, y: 0, votes: 0 };
  }
  const factor: number = healDownsampleFactor(width, height);
  const dsWidth: number = Math.floor(width / factor);
  const dsHeight: number = Math.floor(height / factor);
  if (dsWidth < HEAL_PATCH_SIZE || dsHeight < HEAL_PATCH_SIZE) {
    return { x: 0, y: 0, votes: 0 };
  }
  const source: Uint8Array = factor > 1 ?
    healDownsampleRgba(pixels, width, height, factor, dsWidth, dsHeight) : pixels;
  const dsMask: Uint8Array = factor > 1 ?
    healDownsampleMask(mask, width, height, factor, dsWidth, dsHeight) : mask;
  for (let index: number = 0; index < dsMask.length; index++) {
    dsMask[index] = dsMask[index] < 1 ? 0 : 255;
  }
  const bounds: HealBounds = healContentBounds(dsMask, dsWidth, dsHeight);
  if (bounds.width === 0 || bounds.height === 0) {
    return { x: 0, y: 0, votes: 0 };
  }
  const minDistSq: number = Math.round((bounds.width + bounds.height) / 2 / HEAL_PATCH_SIZE_DIVISOR);
  const ycbcr: Int16Array = rgbaToYcbcr(source);
  const features: Int16Array = extractHealFeatures(ycbcr, dsMask, dsWidth, dsHeight);
  const featureCount: number = features.length / HEAL_FEATURE_RECORD_SIZE;
  if (featureCount === 0) {
    return { x: 0, y: 0, votes: 0 };
  }
  const nodes: number[] = [];
  healBuildKdTree(0, featureCount - 1, nodes, features,
    new Float64Array(2 * HEAL_FEATURE_RECORD_SIZE));
  const histogram: Float64Array = new Float64Array(dsWidth * dsHeight * 4);
  for (let index: number = 0; index < featureCount; index++) {
    const nearest: number = healNearestRecord(index, features, nodes, minDistSq);
    if (nearest === -1) {
      continue;
    }
    const queryOffset: number = index * HEAL_FEATURE_RECORD_SIZE;
    const nearestOffset: number = nearest * HEAL_FEATURE_RECORD_SIZE;
    const offsetX: number = features[nearestOffset] - features[queryOffset];
    const offsetY: number = features[nearestOffset + 1] - features[queryOffset + 1];
    histogram[(dsHeight + offsetY) * 2 * dsWidth + (dsWidth + offsetX)] += 1;
  }
  let bestX: number = 0;
  let bestY: number = 0;
  let bestVotes: number = 0;
  for (let voteIndex: number = 0; voteIndex < histogram.length; voteIndex++) {
    if (histogram[voteIndex] > bestVotes) {
      bestVotes = histogram[voteIndex];
      const row: number = Math.floor(voteIndex / (2 * dsWidth));
      bestX = voteIndex - row * 2 * dsWidth - dsWidth;
      bestY = row - dsHeight;
    }
  }
  return { x: bestX, y: bestY, votes: Math.round(bestVotes) };
}

export function floodFillMask(source: Uint8Array, width: number, height: number, stride: number,
  seedX: number, seedY: number, tolerance: number, contiguous: boolean, antialias: boolean): Uint8Array {
  const safeWidth: number = Math.max(1, Math.round(width));
  const safeHeight: number = Math.max(1, Math.round(height));
  const safeStride: number = Math.max(safeWidth * 4, Math.round(stride));
  const safeTolerance: number = Math.max(0, Math.min(255, Math.round(tolerance)));
  const mask: Uint8Array = new Uint8Array(safeWidth * safeHeight);
  const localX: number = Math.max(0, Math.min(safeWidth - 1, Math.round(seedX)));
  const localY: number = Math.max(0, Math.min(safeHeight - 1, Math.round(seedY)));
  const seedIndex: number = localY * safeStride + localX * 4;
  if (seedIndex < 0 || seedIndex + 3 >= source.length) {
    return mask;
  }
  const seedRed: number = source[seedIndex];
  const seedGreen: number = source[seedIndex + 1];
  const seedBlue: number = source[seedIndex + 2];
  const colorDistance: (x: number, y: number) => number = (x: number, y: number): number => {
    const index: number = y * safeStride + x * 4;
    return Math.max(Math.abs(source[index] - seedRed),
      Math.max(Math.abs(source[index + 1] - seedGreen), Math.abs(source[index + 2] - seedBlue)));
  };
  if (contiguous) {
    const visited: Uint8Array = new Uint8Array(safeWidth * safeHeight);
    const stack: number[] = [localY * safeWidth + localX];
    visited[localY * safeWidth + localX] = 1;
    while (stack.length > 0) {
      const packed: number = stack.pop() as number;
      const x: number = packed % safeWidth;
      const y: number = Math.floor(packed / safeWidth);
      if (colorDistance(x, y) <= safeTolerance) {
        mask[y * safeWidth + x] = 255;
        if (x > 0 && visited[y * safeWidth + x - 1] === 0) {
          visited[y * safeWidth + x - 1] = 1;
          stack.push(y * safeWidth + x - 1);
        }
        if (x + 1 < safeWidth && visited[y * safeWidth + x + 1] === 0) {
          visited[y * safeWidth + x + 1] = 1;
          stack.push(y * safeWidth + x + 1);
        }
        if (y > 0 && visited[(y - 1) * safeWidth + x] === 0) {
          visited[(y - 1) * safeWidth + x] = 1;
          stack.push((y - 1) * safeWidth + x);
        }
        if (y + 1 < safeHeight && visited[(y + 1) * safeWidth + x] === 0) {
          visited[(y + 1) * safeWidth + x] = 1;
          stack.push((y + 1) * safeWidth + x);
        }
      } else if (antialias) {
        const distance: number = colorDistance(x, y);
        const edge: number = Math.max(0, Math.min(1,
          1 - (distance - safeTolerance) / Math.max(1, safeTolerance)));
        mask[y * safeWidth + x] = Math.round(255 * edge);
      }
    }
  } else {
    for (let y: number = 0; y < safeHeight; y++) {
      for (let x: number = 0; x < safeWidth; x++) {
        const distance: number = colorDistance(x, y);
        if (distance <= safeTolerance) {
          mask[y * safeWidth + x] = 255;
        } else if (antialias && distance <= safeTolerance * 2) {
          const edge: number = 1 - (distance - safeTolerance) / Math.max(1, safeTolerance);
          mask[y * safeWidth + x] = Math.round(255 * Math.max(0, Math.min(1, edge)));
        }
      }
    }
  }
  return mask;
}

export function clonePaintPoint(point: TransformPoint): TransformPoint {
  const copy: TransformPoint = { x: point.x, y: point.y };
  return copy;
}

export function inverseTransformPoint(x: number, y: number, width: number, height: number,
  transform: TransformState): TransformPoint {
  const normalized: TransformState = normalizeTransform(transform);
  const size: TransformSize = transformedSize(width, height, normalized);
  let rotatedX: number = x;
  let rotatedY: number = y;
  if (normalized.flipHorizontal) {
    rotatedX = size.width - rotatedX;
  }
  if (normalized.flipVertical) {
    rotatedY = size.height - rotatedY;
  }
  if (normalized.rotation === 90) {
    return {
      x: rotatedY,
      y: height - rotatedX
    };
  }
  if (normalized.rotation === 180) {
    return {
      x: width - rotatedX,
      y: height - rotatedY
    };
  }
  if (normalized.rotation === 270) {
    return {
      x: width - rotatedY,
      y: rotatedX
    };
  }
  return {
    x: rotatedX,
    y: rotatedY
  };
}

export function selectionToCropRect(selection: SelectionRect, crop: CropRect,
  transform: TransformState): CropRect {
  const topLeft: TransformPoint = inverseTransformPoint(selection.x, selection.y,
    crop.width, crop.height, transform);
  const bottomRight: TransformPoint = inverseTransformPoint(selection.x + selection.width,
    selection.y + selection.height, crop.width, crop.height, transform);
  const left: number = Math.min(topLeft.x, bottomRight.x);
  const right: number = Math.max(topLeft.x, bottomRight.x);
  const top: number = Math.min(topLeft.y, bottomRight.y);
  const bottom: number = Math.max(topLeft.y, bottomRight.y);
  return {
    x: crop.x + left,
    y: crop.y + top,
    width: Math.max(1, right - left),
    height: Math.max(1, bottom - top)
  };
}

export function sourcePointToCropSpace(point: TransformPoint, crop: CropRect,
  sourceWidth: number, sourceHeight: number, transform: TransformState): TransformPoint {
  const safeWidth: number = Math.max(1, Math.round(sourceWidth));
  const safeHeight: number = Math.max(1, Math.round(sourceHeight));
  const sourcePoint: TransformPoint = {
    x: Math.max(0, Math.min(safeWidth, point.x)),
    y: Math.max(0, Math.min(safeHeight, point.y))
  };
  const transformed: TransformPoint = transformPoint(sourcePoint.x, sourcePoint.y,
    safeWidth, safeHeight, transform);
  const transformedCrop: TransformPoint = transformPoint(crop.x, crop.y,
    safeWidth, safeHeight, transform);
  return {
    x: transformed.x - transformedCrop.x,
    y: transformed.y - transformedCrop.y
  };
}

export function formatAdjustment(key: string, value: number): string {
  if (key === 'blur') {
    return value.toFixed(1) + ' px';
  }
  return (value > 0 ? '+' : '') + Math.round(value).toString();
}

export function filterMatrix(values: AdjustmentValues): number[] {
  const exposure = 1 + values.exposure / 100;
  const contrast = 1 + values.contrast / 100;
  const saturation = 1 + values.saturation / 100;
  const temperature = values.temperature / 100;
  const luminanceR = 0.2126;
  const luminanceG = 0.7152;
  const luminanceB = 0.0722;
  const inverseR = 1 - saturation;
  const scale = exposure * contrast;
  const offset = 0.5 * exposure * (1 - contrast);
  const red = scale * (inverseR * luminanceR + saturation) + temperature * 0.16;
  const green = scale * (inverseR * luminanceG + saturation);
  const blue = scale * (inverseR * luminanceB + saturation) - temperature * 0.16;
  const r = scale * inverseR * luminanceR;
  const g = scale * inverseR * luminanceG;
  const b = scale * inverseR * luminanceB;
  return [
    red, g, b, 0, offset + temperature * 0.16,
    r, green, b, 0, offset,
    r, g, blue, 0, offset - temperature * 0.16,
    0, 0, 0, 1, 0
  ];
}

function filterPresetMatrix(preset: string): number[] {
  switch (preset) {
    case 'warm':
      return [1.08, 0.02, 0, 0, 0.01, 0, 1.02, 0, 0, 0, 0, 0, 0.9, 0, 0.01, 0, 0, 0, 1, 0];
    case 'cool':
      return [0.94, 0, 0, 0, 0, 0, 1, 0.02, 0, 0.01, 0, 0.02, 1.08, 0, 0.02, 0, 0, 0, 1, 0];
    case 'vivid':
      return [1.14, -0.05, 0, 0, 0, -0.05, 1.14, -0.05, 0, 0, 0, -0.05, 1.14, -0.05, 0, 0, 0, 0, 1, 0];
    case 'vintage':
      return [0.92, 0.08, -0.03, 0, 0.03, 0.02, 0.98, 0.01, 0, 0.015, -0.02, 0.04, 0.82, 0, 0.04, 0, 0, 0, 1, 0];
    case 'mono':
      return [0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0, 0, 0, 0, 1, 0];
    case 'softLight':
      return [0.72, 0.18, 0.1, 0, 0.03, 0.16, 0.84, 0, 0, 0.03, 0.14, 0.16, 0.7, 0, 0.04,
        0, 0, 0, 1, 0];
    default:
      return [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
  }
}

export function getFilterPresetMatrix(preset: string, intensity: number): number[] {
  const source: number[] = filterPresetMatrix(preset);
  const amount: number = clamp(Number.isNaN(intensity) ? 0 : intensity / 100, 0, 1);
  const result: number[] = [];
  for (let index: number = 0; index < source.length; index++) {
    // The matrix is row-major 4x5: column 4 is the offset term and the
    // diagonal sits at 0, 6, 12 and 18. Anything else is an off-diagonal
    // weight, which must blend from zero or neutral images wash out to grey.
    const identity: number = index % 5 === 4 ? 0 : (index === 0 || index === 6 || index === 12 ||
      index === 18) ? 1 : 0;
    result.push(identity + (source[index] - identity) * amount);
  }
  return result;
}

export function combineFilterMatrices(first: number[], second: number[]): number[] {
  const result: number[] = [];
  for (let row: number = 0; row < 4; row++) {
    for (let column: number = 0; column < 5; column++) {
      let value: number = 0;
      for (let index: number = 0; index < 4; index++) {
        value += second[row * 5 + index] * first[index * 5 + column];
      }
      value += second[row * 5 + 4];
      result.push(value);
    }
  }
  return result;
}

export function documentFilterMatrix(values: AdjustmentValues, preset: string, intensity: number): number[] {
  return combineFilterMatrices(getFilterPresetMatrix(preset, intensity), filterMatrix(values));
}

export function filterPresetFromLabel(label: string): string {
  const normalized: string = label.trim().toLowerCase().replace(' ', '');
  for (let index: number = 0; index < FILTER_PRESET_NAMES.length; index++) {
    const name: string = FILTER_PRESET_NAMES[index].toLowerCase().replace(' ', '');
    if (name === normalized) {
      return FILTER_PRESET_KEYS[index];
    }
  }
  return DEFAULT_FILTER_PRESET;
}

export function filterPresetLabelFromKey(preset: string): string {
  for (let index: number = 0; index < FILTER_PRESET_KEYS.length; index++) {
    if (FILTER_PRESET_KEYS[index] === preset) {
      return FILTER_PRESET_NAMES[index];
    }
  }
  return FILTER_PRESET_NAMES[0];
}

export function clampFilterIntensity(value: number): number {
  return Number.isNaN(value) ? 0 : Math.max(0, Math.min(100, Math.round(value)));
}

export function applyRgbaFilter(source: ArrayBuffer, width: number, height: number,
  stride: number, matrix: number[]): ArrayBuffer {
  const input: Uint8Array = new Uint8Array(source);
  const output: Uint8Array = new Uint8Array(width * height * 4);
  const sourceStride: number = Math.max(stride, width * 4);
  for (let y: number = 0; y < height; y++) {
    const sourceRow: number = y * sourceStride;
    const outputRow: number = y * width * 4;
    for (let x: number = 0; x < width; x++) {
      const sourceIndex: number = sourceRow + x * 4;
      const outputIndex: number = outputRow + x * 4;
      const red: number = input[sourceIndex] / 255;
      const green: number = input[sourceIndex + 1] / 255;
      const blue: number = input[sourceIndex + 2] / 255;
      const transformedRed: number = matrix[0] * red + matrix[1] * green + matrix[2] * blue + matrix[4];
      const transformedGreen: number = matrix[5] * red + matrix[6] * green + matrix[7] * blue + matrix[9];
      const transformedBlue: number = matrix[10] * red + matrix[11] * green + matrix[12] * blue + matrix[14];
      output[outputIndex] = Math.round(clamp(transformedRed, 0, 1) * 255);
      output[outputIndex + 1] = Math.round(clamp(transformedGreen, 0, 1) * 255);
      output[outputIndex + 2] = Math.round(clamp(transformedBlue, 0, 1) * 255);
      output[outputIndex + 3] = input[sourceIndex + 3];
    }
  }
  return output.buffer;
}

export function applyRgbaAdjustments(source: ArrayBuffer, width: number, height: number,
  stride: number, values: AdjustmentValues): ArrayBuffer {
  const input: Uint8Array = new Uint8Array(source);
  const output: Uint8Array = new Uint8Array(width * height * 4);
  const rowBytes: number = width * 4;
  const sourceStride: number = Math.max(stride, rowBytes);
  const exposure: number = 1 + values.exposure / 100;
  const contrast: number = 1 + values.contrast / 100;
  const saturation: number = 1 + values.saturation / 100;
  const temperature: number = values.temperature / 100;
  const luminanceR: number = 0.2126;
  const luminanceG: number = 0.7152;
  const luminanceB: number = 0.0722;
  for (let y: number = 0; y < height; y++) {
    const sourceRow: number = y * sourceStride;
    const outputRow: number = y * rowBytes;
    for (let x: number = 0; x < width; x++) {
      const sourceIndex: number = sourceRow + x * 4;
      const outputIndex: number = outputRow + x * 4;
      const red: number = input[sourceIndex] / 255;
      const green: number = input[sourceIndex + 1] / 255;
      const blue: number = input[sourceIndex + 2] / 255;
      const luminance: number = luminanceR * red + luminanceG * green + luminanceB * blue;
      let adjustedRed: number = (luminance + saturation * (red - luminance)) * exposure * contrast;
      let adjustedGreen: number = (luminance + saturation * (green - luminance)) * exposure * contrast;
      let adjustedBlue: number = (luminance + saturation * (blue - luminance)) * exposure * contrast;
      adjustedRed = clamp(adjustedRed + temperature * 0.16, 0, 1);
      adjustedGreen = clamp(adjustedGreen, 0, 1);
      adjustedBlue = clamp(adjustedBlue - temperature * 0.16, 0, 1);
      output[outputIndex] = Math.round(adjustedRed * 255);
      output[outputIndex + 1] = Math.round(adjustedGreen * 255);
      output[outputIndex + 2] = Math.round(adjustedBlue * 255);
      output[outputIndex + 3] = input[sourceIndex + 3];
    }
  }
  return output.buffer;
}
