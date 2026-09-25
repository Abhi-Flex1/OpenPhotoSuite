export enum EditorTool {
  MOVE = 'Move',
  RECT_SELECT = 'Rectangular selection',
  LASSO = 'Lasso',
  MAGIC_WAND = 'Magic Wand',
  CROP = 'Crop',
  EYEDROPPER = 'Eyedropper',
  RULER = 'Ruler',
  SPOT_HEAL = 'Spot Healing Brush',
  BRUSH = 'Brush',
  PAINT_BUCKET = 'Paint Bucket',
  CLONE = 'Clone Stamp',
  ERASER = 'Eraser',
  GRADIENT = 'Gradient',
  BLUR = 'Blur',
  SHARPEN = 'Sharpen',
  SMUDGE = 'Smudge',
  SPONGE = 'Sponge',
  RED_EYE = 'Red Eye',
  DODGE = 'Dodge',
  BURN = 'Burn',
  PEN = 'Pen',
  TYPE = 'Type',
  PATH_SELECT = 'Path Selection',
  RECT_SHAPE = 'Rectangle',
  ELLIPSE_SHAPE = 'Ellipse',
  HAND = 'Hand',
  ZOOM = 'Zoom'
}

export enum SidebarTab {
  PROPERTIES = 'Properties',
  LAYERS = 'Layers',
  HISTORY = 'History',
  COLOR = 'Color',
  FILTERS = 'Filters'
}

export enum ExportFormat {
  JPEG = 'image/jpeg',
  PNG = 'image/png'
}

export enum ShapeType {
  RECTANGLE = 'rectangle',
  ELLIPSE = 'ellipse'
}

export enum PaintMode {
  BRUSH = 'brush',
  PENCIL = 'pencil',
  ERASER = 'eraser',
  GRADIENT = 'gradient',
  FILL = 'fill',
  CLONE = 'clone',
  BLUR = 'blur',
  SHARPEN = 'sharpen',
  SMUDGE = 'smudge',
  SPONGE = 'sponge',
  RED_EYE = 'redeye',
  SPOT_HEAL = 'spot_heal',
  DODGE = 'dodge',
  BURN = 'burn'
}

export enum PaintGradientStyle {
  LINEAR = 'linear'
}

export enum ColorTarget {
  FOREGROUND = 'Foreground',
  BACKGROUND = 'Background'
}

export const LAYER_BLEND_MODES: string[] = [
  'Normal',
  'Darken',
  'Multiply',
  'Color Burn',
  'Lighten',
  'Screen',
  'Color Dodge',
  'Overlay',
  'Soft Light',
  'Hard Light',
  'Difference',
  'Exclusion'
];

export const DEFAULT_SWATCHES: string[] = [
  '#000000',
  '#404040',
  '#808080',
  '#FFFFFF',
  '#7A1F1F',
  '#C4511C',
  '#E0A126',
  '#2F7D4A',
  '#2BB8A7',
  '#2878B5',
  '#4054B2',
  '#7A4E9F',
  '#B34C7A',
  '#8A4B35',
  '#D96C4F',
  '#4B6478'
];

export const DEFAULT_FOREGROUND_COLOR: string = '#2BB8A7';
export const DEFAULT_BACKGROUND_COLOR: string = '#F2F5F3';
export const DEFAULT_PAINT_WIDTH: number = 12;
export const DEFAULT_FILL_TOLERANCE: number = 40;
export const DEFAULT_RETOUCH_STRENGTH: number = 50;
export const DEFAULT_RETOUCH_RANGE: number = 1;
export const DEFAULT_FILTER_PRESET: string = 'none';
export const FILTER_PRESET_KEYS: string[] = [
  'none',
  'warm',
  'cool',
  'vivid',
  'vintage',
  'mono',
  'softLight'
];
export const FILTER_PRESET_NAMES: string[] = [
  'None',
  'Warm',
  'Cool',
  'Vivid',
  'Vintage',
  'Mono',
  'Soft Light'
];

export interface ToolDefinition {
  id: EditorTool;
  label: string;
  resource: Resource;
  shortcut: string;
}

export interface LayerModel {
  id: string;
  name: string;
  kind: 'image' | 'adjustment' | 'text' | 'shape' | 'paint' | 'group';
  visible: boolean;
  locked: boolean;
  opacity: number;
  blendMode: string;
  textContent: string;
  textSize: number;
  textColor: string;
  textX: number;
  textY: number;
  shapeType: ShapeType;
  shapeX: number;
  shapeY: number;
  shapeWidth: number;
  shapeHeight: number;
  shapeFill: string;
  shapeStroke: string;
  shapeStrokeWidth: number;
  paintPoints: TransformPoint[];
  paintColor: string;
  paintWidth: number;
  paintMode: PaintMode;
  paintTargetId: string;
  paintSecondaryColor: string;
  paintGradientStyle: PaintGradientStyle;
  paintGradientReverse: boolean;
  paintClip: SelectionRect;
  /**
   * Optional per-pixel source-space clip coverage. Empty means "use
   * paintClip bounds", which is what rectangle selection and free painting
   * need. Lasso and magic wand selection store the exact selected region so
   * strokes do not spill outside it.
   */
  paintClipMask: number[];
  /** Source raster width that indexes paintClipMask. Zero when there is no mask. */
  paintClipMaskWidth: number;
  paintFillTolerance: number;
  paintFillContiguous: boolean;
  paintFillAntialias: boolean;
  paintCloneSource: TransformPoint;
  paintRetouchStrength: number;
  paintSpongeMode: number;
  paintRetouchRange: number;
}

export interface AdjustmentValues {
  exposure: number;
  contrast: number;
  saturation: number;
  temperature: number;
  blur: number;
}

export interface FilterState {
  preset: string;
  intensity: number;
}

export interface TransformState {
  rotation: number;
  flipHorizontal: boolean;
  flipVertical: boolean;
}

export interface TransformSize {
  width: number;
  height: number;
}

export interface TransformPoint {
  x: number;
  y: number;
}

export interface CropRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface CropState {
  rect: CropRect;
}

export interface SelectionRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export type SelectionMode = 'rectangle' | 'lasso' | 'magicWand';

export interface SelectionState {
  active: boolean;
  mode: SelectionMode;
  rect: SelectionRect;
  points: TransformPoint[];
}

export type CropAspect = 'free' | 'square' | 'fourThree' | 'sixteenNine';

export interface ColorState {
  foreground: string;
  background: string;
  swatches: string[];
}

export interface HistoryEntry {
  id: string;
  label: string;
  detail: string;
  time: string;
  kind: 'open' | 'edit' | 'layer' | 'paint' | 'color' | 'transform' | 'crop' | 'select' | 'export' | 'view';
}

export type HistoryKind = 'open' | 'edit' | 'layer' | 'paint' | 'color' | 'transform' | 'crop' | 'select' | 'export' | 'view';

export interface DocumentState {
  name: string;
  uri: string;
  sourceWidth: number;
  sourceHeight: number;
  width: number;
  height: number;
  source: PixelMap | string;
  layers: LayerModel[];
  adjustments: AdjustmentValues;
  filter: FilterState;
  transform: TransformState;
  crop: CropState;
  selection: SelectionState;
  history: HistoryEntry[];
  dirty: boolean;
}

export interface OpenDocument {
  name: string;
  uri: string;
  width: number;
  height: number;
  source: PixelMap | string;
}

export interface ExportedDocument {
  name: string;
  uri: string;
}
