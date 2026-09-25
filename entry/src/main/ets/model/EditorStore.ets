import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AdjustmentValues,
  ColorState,
  ColorTarget,
  CropRect,
  CropState,
  DEFAULT_BACKGROUND_COLOR,
  DEFAULT_FOREGROUND_COLOR,
  DEFAULT_FILL_TOLERANCE,
  DEFAULT_PAINT_WIDTH,
  DEFAULT_RETOUCH_RANGE,
  DEFAULT_RETOUCH_STRENGTH,
  DEFAULT_SWATCHES,
  DocumentState,
  EditorTool,
  FilterState,
  HistoryEntry,
  HistoryKind,
  LayerModel,
  LAYER_BLEND_MODES,
  OpenDocument,
  PaintGradientStyle,
  PaintMode,
  SelectionRect,
  SelectionMode,
  SelectionState,
  ShapeType,
  SidebarTab,
  TransformPoint,
  TransformState
} from './EditorTypes';
import {
  adjustmentsAreNeutral,
  clonePaintPoint,
  cloneTransform,
  clampAdjustment,
  cloneAdjustments,
  clampFilterIntensity,
  cropIsFull,
  floodFillMask,
  fullCropRect,
  normalizeCropRect,
  normalizeHexColor,
  normalizePaintPoints,
  normalizeTransform,
  normalizeSelectionPoints,
  rasterizePolygonMask,
  normalizeSelectionRect,
  rectangleSelectionPoints,
  selectionPointsFromMask,
  selectionRectFromPoints,
  selectionToCropRect,
  transformIsNeutral,
  transformedSize,
  fullSelectionRect
} from './EditorMath';
import { ExportFormat } from './EditorTypes';
import { decodeBundledSample, exportPixelMap, pickAndDecodeImage } from '../platform/ImageFileService';

const DOMAIN: number = 0x0A24;
const TAG: string = 'OpenPhotoSuiteStore';
const HISTORY_LIMIT: number = 80;

interface DocumentSnapshot {
  selectionClipMask: number[];
  layers: LayerModel[];
  adjustments: AdjustmentValues;
  filter: FilterState;
  transform: TransformState;
  crop: CropState;
  selection: SelectionState;
  colors: ColorState;
  selectedLayerId: string;
  dirty: boolean;
}

function timeLabel(): string {
  const now: Date = new Date();
  const hours: string = now.getHours().toString().padStart(2, '0');
  const minutes: string = now.getMinutes().toString().padStart(2, '0');
  return hours + ':' + minutes;
}

function historyEntry(label: string, detail: string,
  kind: HistoryKind): HistoryEntry {
  return {
    id: 'history-' + Date.now().toString() + '-' + Math.random().toString(16).slice(2),
    label: label,
    detail: detail,
    time: timeLabel(),
    kind: kind
  };
}

function defaultLayers(documentName: string, sourceWidth: number = 150,
  sourceHeight: number = 105): LayerModel[] {
  return [
    {
      id: 'layer-adjustment',
      name: 'Light & Color',
      kind: 'adjustment',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
    textColor: DEFAULT_FOREGROUND_COLOR,
    textX: 24,
    textY: 24,
    shapeType: ShapeType.RECTANGLE,
    shapeX: 0,
    shapeY: 0,
    shapeWidth: 0,
    shapeHeight: 0,
    shapeFill: DEFAULT_FOREGROUND_COLOR,
    shapeStroke: DEFAULT_BACKGROUND_COLOR,
    shapeStrokeWidth: 2,
    paintPoints: [],
    paintColor: DEFAULT_FOREGROUND_COLOR,
    paintWidth: DEFAULT_PAINT_WIDTH,
    paintMode: PaintMode.BRUSH,
    paintTargetId: '',
    paintSecondaryColor: DEFAULT_BACKGROUND_COLOR,
    paintGradientStyle: PaintGradientStyle.LINEAR,
    paintGradientReverse: false,
    paintClip: fullSelectionRect(sourceWidth, sourceHeight),
    paintClipMask: [],
    paintClipMaskWidth: 0,
    paintFillTolerance: DEFAULT_FILL_TOLERANCE,
    paintFillContiguous: true,
    paintFillAntialias: true,
    paintCloneSource: { x: 0, y: 0 },
    paintRetouchStrength: DEFAULT_RETOUCH_STRENGTH,
    paintSpongeMode: 1,
    paintRetouchRange: DEFAULT_RETOUCH_RANGE
    },
    {
      id: 'layer-image',
      name: documentName,
      kind: 'image',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
    textColor: DEFAULT_FOREGROUND_COLOR,
    textX: 24,
    textY: 24,
    shapeType: ShapeType.RECTANGLE,
    shapeX: 0,
    shapeY: 0,
    shapeWidth: 0,
    shapeHeight: 0,
    shapeFill: DEFAULT_FOREGROUND_COLOR,
    shapeStroke: DEFAULT_BACKGROUND_COLOR,
    shapeStrokeWidth: 2,
    paintPoints: [],
    paintColor: DEFAULT_FOREGROUND_COLOR,
    paintWidth: DEFAULT_PAINT_WIDTH,
    paintMode: PaintMode.BRUSH,
    paintTargetId: '',
    paintSecondaryColor: DEFAULT_BACKGROUND_COLOR,
    paintGradientStyle: PaintGradientStyle.LINEAR,
    paintGradientReverse: false,
    paintClip: fullSelectionRect(sourceWidth, sourceHeight),
    paintClipMask: [],
    paintClipMaskWidth: 0,
    paintFillTolerance: DEFAULT_FILL_TOLERANCE,
    paintFillContiguous: true,
    paintFillAntialias: true,
    paintCloneSource: { x: 0, y: 0 },
    paintRetouchStrength: DEFAULT_RETOUCH_STRENGTH,
    paintSpongeMode: 1,
    paintRetouchRange: DEFAULT_RETOUCH_RANGE
    }
  ];
}

function cloneLayer(layer: LayerModel): LayerModel {
  return {
    id: layer.id,
    name: layer.name,
    kind: layer.kind,
    visible: layer.visible,
    locked: layer.locked,
    opacity: layer.opacity,
    blendMode: layer.blendMode,
    textContent: layer.textContent,
    textSize: layer.textSize,
    textColor: layer.textColor,
    textX: layer.textX,
    textY: layer.textY,
    shapeType: layer.shapeType,
    shapeX: layer.shapeX,
    shapeY: layer.shapeY,
    shapeWidth: layer.shapeWidth,
    shapeHeight: layer.shapeHeight,
    shapeFill: layer.shapeFill,
    shapeStroke: layer.shapeStroke,
    shapeStrokeWidth: layer.shapeStrokeWidth,
    paintPoints: layer.paintPoints.map((point: TransformPoint) => clonePaintPoint(point)),
    paintColor: layer.paintColor,
    paintWidth: layer.paintWidth,
    paintMode: layer.paintMode,
    paintTargetId: layer.paintTargetId,
    paintSecondaryColor: layer.paintSecondaryColor,
    paintGradientStyle: layer.paintGradientStyle,
    paintGradientReverse: layer.paintGradientReverse,
    paintClip: {
      x: layer.paintClip.x,
      y: layer.paintClip.y,
      width: layer.paintClip.width,
      height: layer.paintClip.height
    },
    paintClipMask: layer.paintClipMask.slice(),
    paintClipMaskWidth: layer.paintClipMaskWidth,
    paintFillTolerance: layer.paintFillTolerance,
    paintFillContiguous: layer.paintFillContiguous,
    paintFillAntialias: layer.paintFillAntialias,
    paintCloneSource: {
      x: layer.paintCloneSource.x,
      y: layer.paintCloneSource.y
    },
    paintRetouchStrength: layer.paintRetouchStrength,
    paintSpongeMode: layer.paintSpongeMode,
    paintRetouchRange: layer.paintRetouchRange
  };
}

function cloneColors(colors: ColorState): ColorState {
  return {
    foreground: colors.foreground,
    background: colors.background,
    swatches: colors.swatches.map((color: string) => color)
  };
}

export class EditorStore {
  document: DocumentState;
  activeTool: EditorTool = EditorTool.MOVE;
  sidebarTab: SidebarTab = SidebarTab.PROPERTIES;
  zoom: number = 1;
  panX: number = 0;
  panY: number = 0;
  canUndo: boolean = false;
  canRedo: boolean = false;
  selectedLayerId: string = 'layer-image';
  colors: ColorState = {
    foreground: DEFAULT_FOREGROUND_COLOR,
    background: DEFAULT_BACKGROUND_COLOR,
    swatches: DEFAULT_SWATCHES.slice()
  };
  private redoStack: DocumentSnapshot[] = [];
  private undoStack: DocumentSnapshot[] = [];
  /**
   * Filled source-space coverage for the active lasso or magic wand
   * selection, captured when the selection is created. A magic wand outline
   * is only the edge of its region, so the interior has to be kept here.
   */
  private selectionClipMask: number[] = [];
  private busy: boolean = false;
  private message: string = '';

  constructor() {
    this.document = {
      name: 'Beach Study',
      uri: 'sample://beach',
      sourceWidth: 150,
      sourceHeight: 105,
      width: 150,
      height: 105,
      source: 'sample://beach',
      layers: defaultLayers('Beach Study', 150, 105),
      adjustments: {
        exposure: 0,
        contrast: 0,
        saturation: 0,
        temperature: 0,
        blur: 0
      },
      filter: {
        preset: 'none',
        intensity: 100
      },
      transform: {
        rotation: 0,
        flipHorizontal: false,
        flipVertical: false
      },
      crop: {
        rect: fullCropRect(150, 105)
      },
      selection: {
        active: false,
        mode: 'rectangle',
        rect: fullSelectionRect(150, 105),
        points: rectangleSelectionPoints(fullSelectionRect(150, 105))
      },
      history: [historyEntry('Open document', 'Beach Study', 'open')],
      dirty: false
    };
  }

  get isBusy(): boolean {
    return this.busy;
  }

  get statusMessage(): string {
    return this.message;
  }

  get neutralAdjustments(): boolean {
    return adjustmentsAreNeutral(this.document.adjustments);
  }

  get selectedLayer(): LayerModel | undefined {
    return this.getLayer(this.selectedLayerId);
  }

  getLayer(id: string): LayerModel | undefined {
    for (const layer of this.document.layers) {
      if (layer.id === id) {
        return layer;
      }
    }
    return undefined;
  }

  selectLayer(id: string): void {
    if (this.getLayer(id) !== undefined) {
      this.selectedLayerId = id;
    }
  }

  setTool(tool: EditorTool): void {
    this.activeTool = tool;
  }

  setSidebarTab(tab: SidebarTab): void {
    this.sidebarTab = tab;
  }

  setZoom(value: number): void {
    this.zoom = Math.max(0.1, Math.min(8, value));
  }

  setPan(x: number, y: number): void {
    this.panX = x;
    this.panY = y;
  }

  rotateClockwise(): void {
    const next: TransformState = normalizeTransform({
      rotation: this.document.transform.rotation + 90,
      flipHorizontal: this.document.transform.flipHorizontal,
      flipVertical: this.document.transform.flipVertical
    });
    if (next.rotation === this.document.transform.rotation) {
      return;
    }
    this.commitBeforeChange();
    this.document.transform = next;
    this.updateDocumentSize();
    this.clearSelectionState();
    this.document.dirty = true;
    this.pushHistory(historyEntry('Rotate document', next.rotation.toString() + '° clockwise', 'transform'));
  }

  flipHorizontal(): void {
    const nextValue: boolean = !this.document.transform.flipHorizontal;
    this.commitBeforeChange();
    this.document.transform.flipHorizontal = nextValue;
    this.updateDocumentSize();
    this.clearSelectionState();
    this.document.dirty = true;
    this.pushHistory(historyEntry('Flip horizontal', nextValue ? 'On' : 'Off', 'transform'));
  }

  flipVertical(): void {
    const nextValue: boolean = !this.document.transform.flipVertical;
    this.commitBeforeChange();
    this.document.transform.flipVertical = nextValue;
    this.updateDocumentSize();
    this.clearSelectionState();
    this.document.dirty = true;
    this.pushHistory(historyEntry('Flip vertical', nextValue ? 'On' : 'Off', 'transform'));
  }

  resetTransform(): void {
    if (transformIsNeutral(this.document.transform)) {
      return;
    }
    this.commitBeforeChange();
    this.document.transform = {
      rotation: 0,
      flipHorizontal: false,
      flipVertical: false
    };
    this.updateDocumentSize();
    this.clearSelectionState();
    this.document.dirty = true;
    this.pushHistory(historyEntry('Reset transform', 'Original orientation', 'transform'));
  }

  getCropRect(): CropRect {
    return {
      x: this.document.crop.rect.x,
      y: this.document.crop.rect.y,
      width: this.document.crop.rect.width,
      height: this.document.crop.rect.height
    };
  }

  applyCrop(rect: CropRect): boolean {
    const next: CropRect = normalizeCropRect(rect, this.document.sourceWidth, this.document.sourceHeight);
    const current: CropRect = this.getCropRect();
    if (next.x === current.x && next.y === current.y && next.width === current.width &&
      next.height === current.height) {
      return false;
    }
    this.commitBeforeChange();
    this.document.crop = { rect: next };
    this.updateDocumentSize();
    this.clearSelectionState();
    this.document.dirty = true;
    this.pushHistory(historyEntry('Crop document',
      next.width.toString() + ' × ' + next.height.toString(), 'crop'));
    return true;
  }

  resetCrop(): void {
    if (cropIsFull(this.getCropRect(), this.document.sourceWidth, this.document.sourceHeight)) {
      return;
    }
    this.commitBeforeChange();
    this.document.crop = {
      rect: fullCropRect(this.document.sourceWidth, this.document.sourceHeight)
    };
    this.updateDocumentSize();
    this.clearSelectionState();
    this.document.dirty = true;
    this.pushHistory(historyEntry('Reset crop', 'Full document bounds', 'crop'));
  }

  getSelectionRect(): SelectionRect {
    return {
      x: this.document.selection.rect.x,
      y: this.document.selection.rect.y,
      width: this.document.selection.rect.width,
      height: this.document.selection.rect.height
    };
  }

  setSelection(rect: SelectionRect): boolean {
    const next: SelectionRect = normalizeSelectionRect(rect, this.document.width, this.document.height);
    this.selectionClipMask = [];
    const current: SelectionRect = this.getSelectionRect();
    if (this.document.selection.active && this.document.selection.mode === 'rectangle' &&
      next.x === current.x && next.y === current.y &&
      next.width === current.width && next.height === current.height) {
      return true;
    }
    this.commitBeforeChange();
    this.document.selection = {
      active: true,
      mode: 'rectangle',
      rect: next,
      points: rectangleSelectionPoints(next)
    };
    this.pushHistory(historyEntry('Select region',
      next.width.toString() + ' × ' + next.height.toString(), 'select'));
    return true;
  }

  selectAll(): void {
    this.selectionClipMask = [];
    const next: SelectionRect = fullSelectionRect(this.document.width, this.document.height);
    if (this.document.selection.active && this.getSelectionRect().width === next.width &&
      this.getSelectionRect().height === next.height && this.getSelectionRect().x === 0 &&
      this.getSelectionRect().y === 0) {
      return;
    }
    this.commitBeforeChange();
    this.document.selection = {
      active: true,
      mode: 'rectangle',
      rect: next,
      points: rectangleSelectionPoints(next)
    };
    this.pushHistory(historyEntry('Select all', 'Full document', 'select'));
  }

  setLassoSelection(points: TransformPoint[]): boolean {
    const normalized: TransformPoint[] = normalizeSelectionPoints(points, this.document.width,
      this.document.height);
    if (normalized.length < 3) {
      return false;
    }
    const next: SelectionRect = normalizeSelectionRect(selectionRectFromPoints(normalized),
      this.document.width, this.document.height);
    this.commitBeforeChange();
    this.selectionClipMask = Array.from(rasterizePolygonMask(normalized, this.document.sourceWidth,
      this.document.sourceHeight));
    this.document.selection = {
      active: true,
      mode: 'lasso',
      rect: next,
      points: normalized
    };
    this.pushHistory(historyEntry('Lasso selection', normalized.length.toString() + ' points',
      'select'));
    return true;
  }

  setMagicWandSelection(points: TransformPoint[]): boolean {
    const normalized: TransformPoint[] = normalizeSelectionPoints(points, this.document.width,
      this.document.height);
    if (normalized.length < 3) {
      return false;
    }
    const next: SelectionRect = normalizeSelectionRect(selectionRectFromPoints(normalized),
      this.document.width, this.document.height);
    const copies: TransformPoint[] = [];
    for (const point of normalized) {
      const copy: TransformPoint = { x: point.x, y: point.y };
      copies.push(copy);
    }
    this.commitBeforeChange();
    this.document.selection = {
      active: true,
      mode: 'magicWand',
      rect: next,
      points: copies
    };
    this.pushHistory(historyEntry('Magic wand selection', copies.length.toString() + ' points',
      'select'));
    return true;
  }

  async selectMagicWand(source: image.PixelMap, x: number, y: number, tolerance: number,
    contiguous: boolean): Promise<boolean> {
    if (typeof source === 'string') {
      return false;
    }
    const info: image.ImageInfo = await source.getImageInfo();
    const buffer: ArrayBuffer = new ArrayBuffer(source.getPixelBytesNumber());
    await source.readPixelsToBuffer(buffer);
    const pixels: Uint8Array = new Uint8Array(buffer);
    const mask: Uint8Array = floodFillMask(pixels, info.size.width, info.size.height,
      info.stride, x, y, tolerance, contiguous, false);
    this.selectionClipMask = Array.from(mask);
    const points: TransformPoint[] = selectionPointsFromMask(mask, info.size.width, info.size.height);
    return this.setMagicWandSelection(points);
  }

  deselect(): void {
    if (!this.document.selection.active) {
      return;
    }
    this.commitBeforeChange();
    this.clearSelectionState();
    this.pushHistory(historyEntry('Deselect', 'Selection cleared', 'select'));
  }

  cropToSelection(): boolean {
    if (!this.document.selection.active) {
      return false;
    }
    const next: CropRect = selectionToCropRect(this.getSelectionRect(), this.document.crop.rect,
      this.document.transform);
    return this.applyCrop(next);
  }

  expandSelection(amount: number): boolean {
    if (!this.document.selection.active) {
      return false;
    }
    const pixels: number = Math.max(0, Math.round(amount));
    if (pixels === 0) {
      return false;
    }
    const current: SelectionRect = this.getSelectionRect();
    return this.commitSelectionRect({
      x: current.x - pixels,
      y: current.y - pixels,
      width: current.width + pixels * 2,
      height: current.height + pixels * 2
    }, 'Expand selection', pixels.toString() + ' px');
  }

  contractSelection(amount: number): boolean {
    if (!this.document.selection.active) {
      return false;
    }
    const pixels: number = Math.max(0, Math.round(amount));
    if (pixels === 0) {
      return false;
    }
    const current: SelectionRect = this.getSelectionRect();
    return this.commitSelectionRect({
      x: current.x + pixels,
      y: current.y + pixels,
      width: Math.max(1, current.width - pixels * 2),
      height: Math.max(1, current.height - pixels * 2)
    }, 'Contract selection', pixels.toString() + ' px');
  }

  private commitSelectionRect(rect: SelectionRect, label: string, detail: string): boolean {
    if (this.document.selection.mode === 'rectangle') {
      this.selectionClipMask = [];
    }
    const next: SelectionRect = normalizeSelectionRect(rect, this.document.width, this.document.height);
    const current: SelectionRect = this.getSelectionRect();
    if (next.x === current.x && next.y === current.y && next.width === current.width &&
      next.height === current.height) {
      return false;
    }
    const points: TransformPoint[] = [];
    for (const point of this.document.selection.points) {
      const copy: TransformPoint = { x: point.x, y: point.y };
      points.push(copy);
    }
    this.commitBeforeChange();
    this.document.selection = {
      active: true,
      mode: this.document.selection.mode,
      rect: next,
      points: this.document.selection.mode === 'lasso' ? points :
        rectangleSelectionPoints(next)
    };
    this.pushHistory(historyEntry(label, detail, 'select'));
    return true;
  }

  /**
   * Resolve the source-space clip for a new layer. Rectangle selection and
   * free painting keep an empty mask (bounds only); lasso and magic wand
   * selections carry per-pixel coverage so strokes cannot spill outside the
   * region the user actually selected.
   */
  private resolveSelectionClipMask(clip: SelectionRect | undefined): number[] {
    if (clip !== undefined || !this.document.selection.active) {
      return [];
    }
    const mode: SelectionMode = this.document.selection.mode;
    if (mode !== 'lasso' && mode !== 'magicWand') {
      return [];
    }
    if (this.selectionClipMask.length > 0) {
      return this.selectionClipMask.slice();
    }
    const points: TransformPoint[] = this.document.selection.points;
    if (mode === 'lasso') {
      const polygonMask: Uint8Array = rasterizePolygonMask(points, this.document.sourceWidth,
        this.document.sourceHeight);
      return Array.from(polygonMask);
    }
    // A magic wand outline is the edge of a pixel mask; fill the region it
    // bounds so strokes cannot spill into the unselected surround.
    const edgeMask: Uint8Array = new Uint8Array(this.document.sourceWidth * this.document.sourceHeight);
    for (const point of points) {
      const index: number = point.y * this.document.sourceWidth + point.x;
      if (index >= 0 && index < edgeMask.length) {
        edgeMask[index] = 255;
      }
    }
    return Array.from(edgeMask);
  }

  setFilterPreset(preset: string): void {
    if (this.document.filter.preset === preset) {
      return;
    }
    this.commitBeforeChange();
    this.document.filter.preset = preset;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Apply filter', preset, 'edit'));
  }

  setFilterIntensity(value: number): void {
    const intensity: number = clampFilterIntensity(value);
    if (this.document.filter.intensity === intensity) {
      return;
    }
    this.commitBeforeChange();
    this.document.filter.intensity = intensity;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Filter intensity', intensity.toString() + '%', 'edit'));
  }

  resetFilter(): void {
    if (this.document.filter.preset === 'none' && this.document.filter.intensity === 100) {
      return;
    }
    this.commitBeforeChange();
    this.document.filter.preset = 'none';
    this.document.filter.intensity = 100;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Reset filters', 'Gallery', 'edit'));
  }

  setColor(target: ColorTarget, value: string): boolean {
    const normalized: string = normalizeHexColor(value);
    if (normalized.length === 0 || this.getColor(target) === normalized) {
      return false;
    }
    this.commitBeforeChange();
    if (target === ColorTarget.FOREGROUND) {
      this.colors.foreground = normalized;
    } else {
      this.colors.background = normalized;
    }
    this.pushHistory(historyEntry('Set ' + target.toString().toLowerCase() + ' color',
      normalized, 'color'));
    return true;
  }

  getColor(target: ColorTarget): string {
    return target === ColorTarget.FOREGROUND ? this.colors.foreground : this.colors.background;
  }

  swapColors(): void {
    if (this.colors.foreground === this.colors.background) {
      return;
    }
    this.commitBeforeChange();
    const foreground: string = this.colors.foreground;
    this.colors.foreground = this.colors.background;
    this.colors.background = foreground;
    this.pushHistory(historyEntry('Swap colors', 'Foreground and background', 'color'));
  }

  resetColors(): void {
    if (this.colors.foreground === DEFAULT_FOREGROUND_COLOR &&
      this.colors.background === DEFAULT_BACKGROUND_COLOR) {
      return;
    }
    this.commitBeforeChange();
    this.colors.foreground = DEFAULT_FOREGROUND_COLOR;
    this.colors.background = DEFAULT_BACKGROUND_COLOR;
    this.pushHistory(historyEntry('Reset colors', 'Default foreground and background', 'color'));
  }

  addSwatch(value: string): boolean {
    const normalized: string = normalizeHexColor(value);
    if (normalized.length === 0 || this.colors.swatches.indexOf(normalized) >= 0 ||
      this.colors.swatches.length >= 24) {
      return false;
    }
    this.commitBeforeChange();
    this.colors.swatches.push(normalized);
    this.pushHistory(historyEntry('Add swatch', normalized, 'color'));
    return true;
  }

  setLayerVisibility(id: string, visible: boolean): void {
    const layer: LayerModel | undefined = this.getLayer(id);
    if (layer === undefined || layer.visible === visible) {
      return;
    }
    this.commitBeforeChange();
    layer.visible = visible;
    this.document.dirty = true;
    this.pushHistory(historyEntry(visible ? 'Show layer' : 'Hide layer', layer.name, 'layer'));
  }

  toggleLayerVisibility(id: string): void {
    const layer: LayerModel | undefined = this.getLayer(id);
    if (layer !== undefined) {
      this.setLayerVisibility(id, !layer.visible);
    }
  }

  setLayerLocked(id: string, locked: boolean): void {
    const layer: LayerModel | undefined = this.getLayer(id);
    if (layer === undefined || layer.locked === locked) {
      return;
    }
    this.commitBeforeChange();
    layer.locked = locked;
    this.document.dirty = true;
    this.pushHistory(historyEntry(locked ? 'Lock layer' : 'Unlock layer', layer.name, 'layer'));
  }

  toggleLayerLocked(id: string): void {
    const layer: LayerModel | undefined = this.getLayer(id);
    if (layer !== undefined) {
      this.setLayerLocked(id, !layer.locked);
    }
  }

  setLayerOpacity(id: string, value: number): void {
    const layer: LayerModel | undefined = this.getLayer(id);
    const opacity: number = Number.isNaN(value) ? 100 : Math.max(0, Math.min(100, Math.round(value)));
    if (layer === undefined || layer.opacity === opacity) {
      return;
    }
    this.commitBeforeChange();
    layer.opacity = opacity;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Layer opacity', layer.name + ' = ' + opacity + '%', 'layer'));
  }

  setLayerBlendMode(id: string, mode: string): void {
    const layer: LayerModel | undefined = this.getLayer(id);
    if (layer === undefined || LAYER_BLEND_MODES.indexOf(mode) < 0 || layer.blendMode === mode) {
      return;
    }
    this.commitBeforeChange();
    layer.blendMode = mode;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Layer blend mode', layer.name + ' = ' + mode, 'layer'));
  }

  addTextLayer(content: string = 'New text'): string {
    let suffix: number = 1;
    let id: string = 'layer-text';
    let name: string = 'Text';
    while (this.getLayer(id) !== undefined) {
      suffix += 1;
      id = 'layer-text-' + suffix.toString();
      name = 'Text ' + suffix.toString();
    }
    const layer: LayerModel = {
      id: id,
      name: name,
      kind: 'text',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: content.length > 0 ? content : 'New text',
      textSize: 32,
      textColor: this.colors.foreground,
      textX: 24,
      textY: 24,
      shapeType: ShapeType.RECTANGLE,
      shapeX: 0,
      shapeY: 0,
      shapeWidth: 0,
      shapeHeight: 0,
      shapeFill: this.colors.foreground,
      shapeStroke: this.colors.background,
      shapeStrokeWidth: 2,
      paintPoints: [],
      paintColor: this.colors.foreground,
      paintWidth: DEFAULT_PAINT_WIDTH,
      paintMode: PaintMode.BRUSH,
      paintTargetId: '',
      paintSecondaryColor: this.colors.background,
      paintGradientStyle: PaintGradientStyle.LINEAR,
      paintGradientReverse: false,
      paintClip: fullSelectionRect(this.document.sourceWidth, this.document.sourceHeight),
      paintClipMask: [],
      paintClipMaskWidth: 0,
      paintFillTolerance: DEFAULT_FILL_TOLERANCE,
      paintFillContiguous: true,
      paintFillAntialias: true,
      paintCloneSource: { x: 0, y: 0 },
      paintRetouchStrength: DEFAULT_RETOUCH_STRENGTH,
      paintSpongeMode: 1,
      paintRetouchRange: DEFAULT_RETOUCH_RANGE
    };
    this.commitBeforeChange();
    const selectedIndex: number = this.findLayerIndex(this.selectedLayerId);
    this.document.layers.splice(selectedIndex + 1, 0, layer);
    this.selectedLayerId = id;
    this.sidebarTab = SidebarTab.PROPERTIES;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Add text layer', layer.textContent, 'layer'));
    return id;
  }

  addShapeLayer(type: ShapeType, rect: SelectionRect): string {
    const next: SelectionRect = normalizeSelectionRect(rect, this.document.sourceWidth,
      this.document.sourceHeight);
    const prefix: string = type === ShapeType.ELLIPSE ? 'layer-ellipse' : 'layer-rectangle';
    const label: string = type === ShapeType.ELLIPSE ? 'Ellipse' : 'Rectangle';
    let suffix: number = 1;
    let id: string = prefix;
    let name: string = label;
    while (this.getLayer(id) !== undefined) {
      suffix += 1;
      id = prefix + '-' + suffix.toString();
      name = label + ' ' + suffix.toString();
    }
    const layer: LayerModel = {
      id: id,
      name: name,
      kind: 'shape',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
      textColor: this.colors.foreground,
      textX: 24,
      textY: 24,
      shapeType: type,
      shapeX: next.x,
      shapeY: next.y,
      shapeWidth: next.width,
      shapeHeight: next.height,
      shapeFill: this.colors.foreground,
      shapeStroke: this.colors.background,
      shapeStrokeWidth: 2,
      paintPoints: [],
      paintColor: this.colors.foreground,
      paintWidth: DEFAULT_PAINT_WIDTH,
      paintMode: PaintMode.BRUSH,
      paintTargetId: '',
      paintSecondaryColor: this.colors.background,
      paintGradientStyle: PaintGradientStyle.LINEAR,
      paintGradientReverse: false,
      paintClip: fullSelectionRect(this.document.sourceWidth, this.document.sourceHeight),
      paintClipMask: [],
      paintClipMaskWidth: 0,
      paintFillTolerance: DEFAULT_FILL_TOLERANCE,
      paintFillContiguous: true,
      paintFillAntialias: true,
      paintCloneSource: { x: 0, y: 0 },
      paintRetouchStrength: DEFAULT_RETOUCH_STRENGTH,
      paintSpongeMode: 1,
      paintRetouchRange: DEFAULT_RETOUCH_RANGE
    };
    this.commitBeforeChange();
    const selectedIndex: number = this.findLayerIndex(this.selectedLayerId);
    this.document.layers.splice(selectedIndex + 1, 0, layer);
    this.selectedLayerId = id;
    this.sidebarTab = SidebarTab.PROPERTIES;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Add ' + label.toLowerCase(), next.width.toString() + ' × ' +
      next.height.toString(), 'layer'));
    return id;
  }

  addPaintLayer(points: TransformPoint[], color: string, width: number,
    paintMode: PaintMode = PaintMode.BRUSH, targetId: string = ''): string {
    const normalizedPoints: TransformPoint[] = normalizePaintPoints(points,
      this.document.sourceWidth, this.document.sourceHeight);
    const normalizedColor: string = normalizeHexColor(color);
    const normalizedWidth: number = Number.isNaN(width) ? DEFAULT_PAINT_WIDTH :
      Math.max(1, Math.min(96, Math.round(width)));
    if (normalizedPoints.length === 0 || normalizedColor.length === 0) {
      return '';
    }
    const paintTargetId: string = paintMode === PaintMode.ERASER ?
      (targetId.length > 0 ? targetId : this.selectedLayerId) : '';
    let suffix: number = 1;
    const prefix: string = paintMode === PaintMode.PENCIL ? 'layer-pencil' : 'layer-paint';
    const label: string = paintMode === PaintMode.ERASER ? 'Eraser stroke' :
      paintMode === PaintMode.PENCIL ? 'Pencil stroke' : 'Brush stroke';
    let id: string = prefix;
    let name: string = label;
    while (this.getLayer(id) !== undefined) {
      suffix += 1;
      id = prefix + '-' + suffix.toString();
      name = label + ' ' + suffix.toString();
    }
    const layer: LayerModel = {
      id: id,
      name: name,
      kind: 'paint',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
      textColor: normalizedColor,
      textX: 24,
      textY: 24,
      shapeType: ShapeType.RECTANGLE,
      shapeX: 0,
      shapeY: 0,
      shapeWidth: 0,
      shapeHeight: 0,
      shapeFill: normalizedColor,
      shapeStroke: this.colors.background,
      shapeStrokeWidth: 2,
      paintPoints: normalizedPoints.map((point: TransformPoint) => clonePaintPoint(point)),
      paintColor: normalizedColor,
      paintWidth: normalizedWidth,
      paintMode: paintMode,
      paintTargetId: paintTargetId,
      paintSecondaryColor: this.colors.background,
      paintGradientStyle: PaintGradientStyle.LINEAR,
      paintGradientReverse: false,
      paintClip: fullSelectionRect(this.document.sourceWidth, this.document.sourceHeight),
      paintClipMask: [],
      paintClipMaskWidth: 0,
      paintFillTolerance: DEFAULT_FILL_TOLERANCE,
      paintFillContiguous: true,
      paintFillAntialias: true,
      paintCloneSource: { x: 0, y: 0 },
      paintRetouchStrength: DEFAULT_RETOUCH_STRENGTH,
      paintSpongeMode: 1,
      paintRetouchRange: DEFAULT_RETOUCH_RANGE
    };
    this.commitBeforeChange();
    const selectedIndex: number = this.findLayerIndex(this.selectedLayerId);
    this.document.layers.splice(selectedIndex + 1, 0, layer);
    this.selectedLayerId = id;
    this.sidebarTab = SidebarTab.PROPERTIES;
    this.document.dirty = true;
    this.pushHistory(historyEntry(label, normalizedPoints.length.toString() + ' points', 'paint'));
    return id;
  }

  addGradientLayer(start: TransformPoint, end: TransformPoint, primaryColor: string,
    secondaryColor: string, reverse: boolean = false, clip?: SelectionRect): string {
    const resolvedClipMask: number[] = this.resolveSelectionClipMask(clip);
    const normalizedPoints: TransformPoint[] = normalizePaintPoints([start, end],
      this.document.sourceWidth, this.document.sourceHeight);
    const normalizedPrimary: string = normalizeHexColor(primaryColor);
    const normalizedSecondary: string = normalizeHexColor(secondaryColor);
    const deltaX: number = normalizedPoints.length > 1 ? normalizedPoints[1].x - normalizedPoints[0].x : 0;
    const deltaY: number = normalizedPoints.length > 1 ? normalizedPoints[1].y - normalizedPoints[0].y : 0;
    const gradientLength: number = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
    if (normalizedPoints.length !== 2 || gradientLength <= 2 || normalizedPrimary.length === 0 ||
      normalizedSecondary.length === 0) {
      return '';
    }
    let suffix: number = 1;
    let id: string = 'layer-gradient';
    let name: string = 'Gradient';
    while (this.getLayer(id) !== undefined) {
      suffix += 1;
      id = 'layer-gradient-' + suffix.toString();
      name = 'Gradient ' + suffix.toString();
    }
    let sourceClip: SelectionRect = clip !== undefined ?
      normalizeSelectionRect(clip, this.document.sourceWidth, this.document.sourceHeight) :
      fullSelectionRect(this.document.sourceWidth, this.document.sourceHeight);
    if (clip === undefined && this.document.selection.active) {
      const selectionCrop: CropRect = selectionToCropRect(this.getSelectionRect(), this.document.crop.rect,
        this.document.transform);
      sourceClip = normalizeSelectionRect({
        x: selectionCrop.x,
        y: selectionCrop.y,
        width: selectionCrop.width,
        height: selectionCrop.height
      }, this.document.sourceWidth, this.document.sourceHeight);
    }
    const layer: LayerModel = {
      id: id,
      name: name,
      kind: 'paint',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
      textColor: normalizedPrimary,
      textX: 24,
      textY: 24,
      shapeType: ShapeType.RECTANGLE,
      shapeX: 0,
      shapeY: 0,
      shapeWidth: 0,
      shapeHeight: 0,
      shapeFill: normalizedPrimary,
      shapeStroke: this.colors.background,
      shapeStrokeWidth: 2,
      paintPoints: normalizedPoints.map((point: TransformPoint) => clonePaintPoint(point)),
      paintColor: normalizedPrimary,
      paintWidth: 1,
      paintMode: PaintMode.GRADIENT,
      paintTargetId: '',
      paintSecondaryColor: normalizedSecondary,
      paintGradientStyle: PaintGradientStyle.LINEAR,
      paintGradientReverse: reverse,
      paintClip: sourceClip,
      paintClipMask: resolvedClipMask,
      paintClipMaskWidth: resolvedClipMask.length > 0 ? this.document.sourceWidth : 0,
      paintFillTolerance: DEFAULT_FILL_TOLERANCE,
      paintFillContiguous: true,
      paintFillAntialias: true,
      paintCloneSource: { x: 0, y: 0 },
      paintRetouchStrength: DEFAULT_RETOUCH_STRENGTH,
      paintSpongeMode: 1,
      paintRetouchRange: DEFAULT_RETOUCH_RANGE
    };
    this.commitBeforeChange();
    const selectedIndex: number = this.findLayerIndex(this.selectedLayerId);
    this.document.layers.splice(selectedIndex + 1, 0, layer);
    this.selectedLayerId = id;
    this.sidebarTab = SidebarTab.PROPERTIES;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Gradient', normalizedPoints.length.toString() + ' points', 'paint'));
    return id;
  }

  addFillLayer(seed: TransformPoint, color: string, tolerance: number = DEFAULT_FILL_TOLERANCE,
    contiguous: boolean = true, antialias: boolean = true, clip?: SelectionRect): string {
    const normalizedPoints: TransformPoint[] = normalizePaintPoints([seed],
      this.document.sourceWidth, this.document.sourceHeight);
    const normalizedColor: string = normalizeHexColor(color);
    const normalizedTolerance: number = Math.max(0, Math.min(255, Math.round(tolerance)));
    if (normalizedPoints.length !== 1 || normalizedColor.length === 0) {
      return '';
    }
    let sourceClip: SelectionRect = clip !== undefined ?
      normalizeSelectionRect(clip, this.document.sourceWidth, this.document.sourceHeight) :
      fullSelectionRect(this.document.sourceWidth, this.document.sourceHeight);
    if (clip === undefined && this.document.selection.active) {
      const selectionCrop: CropRect = selectionToCropRect(this.getSelectionRect(), this.document.crop.rect,
        this.document.transform);
      sourceClip = normalizeSelectionRect({
        x: selectionCrop.x,
        y: selectionCrop.y,
        width: selectionCrop.width,
        height: selectionCrop.height
      }, this.document.sourceWidth, this.document.sourceHeight);
    }
    const resolvedClipMask: number[] = this.resolveSelectionClipMask(clip);
    let suffix: number = 1;
    let id: string = 'layer-fill';
    let name: string = 'Fill';
    while (this.getLayer(id) !== undefined) {
      suffix += 1;
      id = 'layer-fill-' + suffix.toString();
      name = 'Fill ' + suffix.toString();
    }
    const layer: LayerModel = {
      id: id,
      name: name,
      kind: 'paint',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
      textColor: normalizedColor,
      textX: 24,
      textY: 24,
      shapeType: ShapeType.RECTANGLE,
      shapeX: 0,
      shapeY: 0,
      shapeWidth: 0,
      shapeHeight: 0,
      shapeFill: normalizedColor,
      shapeStroke: this.colors.background,
      shapeStrokeWidth: 2,
      paintPoints: normalizedPoints.map((point: TransformPoint) => clonePaintPoint(point)),
      paintColor: normalizedColor,
      paintWidth: 1,
      paintMode: PaintMode.FILL,
      paintTargetId: '',
      paintSecondaryColor: this.colors.background,
      paintGradientStyle: PaintGradientStyle.LINEAR,
      paintGradientReverse: false,
      paintClip: sourceClip,
      paintClipMask: resolvedClipMask,
      paintClipMaskWidth: resolvedClipMask.length > 0 ? this.document.sourceWidth : 0,
      paintFillTolerance: normalizedTolerance,
      paintFillContiguous: contiguous,
      paintFillAntialias: antialias,
      paintCloneSource: { x: 0, y: 0 },
      paintRetouchStrength: DEFAULT_RETOUCH_STRENGTH,
      paintSpongeMode: 1,
      paintRetouchRange: DEFAULT_RETOUCH_RANGE
    };
    this.commitBeforeChange();
    const selectedIndex: number = this.findLayerIndex(this.selectedLayerId);
    this.document.layers.splice(selectedIndex + 1, 0, layer);
    this.selectedLayerId = id;
    this.sidebarTab = SidebarTab.PROPERTIES;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Fill', normalizedPoints[0].x.toString() + ', ' +
      normalizedPoints[0].y.toString(), 'paint'));
    return id;
  }

  addCloneLayer(source: TransformPoint, points: TransformPoint[], width: number = DEFAULT_PAINT_WIDTH,
    clip?: SelectionRect): string {
    const normalizedSource: TransformPoint[] = normalizePaintPoints([source],
      this.document.sourceWidth, this.document.sourceHeight);
    const normalizedPoints: TransformPoint[] = normalizePaintPoints(points,
      this.document.sourceWidth, this.document.sourceHeight);
    const normalizedWidth: number = Number.isNaN(width) ? DEFAULT_PAINT_WIDTH :
      Math.max(1, Math.min(96, Math.round(width)));
    if (normalizedSource.length !== 1 || normalizedPoints.length === 0) {
      return '';
    }
    let sourceClip: SelectionRect = clip !== undefined ?
      normalizeSelectionRect(clip, this.document.sourceWidth, this.document.sourceHeight) :
      fullSelectionRect(this.document.sourceWidth, this.document.sourceHeight);
    if (clip === undefined && this.document.selection.active) {
      const selectionCrop: CropRect = selectionToCropRect(this.getSelectionRect(), this.document.crop.rect,
        this.document.transform);
      sourceClip = normalizeSelectionRect({
        x: selectionCrop.x,
        y: selectionCrop.y,
        width: selectionCrop.width,
        height: selectionCrop.height
      }, this.document.sourceWidth, this.document.sourceHeight);
    }
    const resolvedClipMask: number[] = this.resolveSelectionClipMask(clip);
    let suffix: number = 1;
    let id: string = 'layer-clone';
    let name: string = 'Clone';
    while (this.getLayer(id) !== undefined) {
      suffix += 1;
      id = 'layer-clone-' + suffix.toString();
      name = 'Clone ' + suffix.toString();
    }
    const layer: LayerModel = {
      id: id,
      name: name,
      kind: 'paint',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
      textColor: this.colors.foreground,
      textX: 24,
      textY: 24,
      shapeType: ShapeType.RECTANGLE,
      shapeX: 0,
      shapeY: 0,
      shapeWidth: 0,
      shapeHeight: 0,
      shapeFill: this.colors.foreground,
      shapeStroke: this.colors.background,
      shapeStrokeWidth: 2,
      paintPoints: normalizedPoints.map((point: TransformPoint) => clonePaintPoint(point)),
      paintColor: this.colors.foreground,
      paintWidth: normalizedWidth,
      paintMode: PaintMode.CLONE,
      paintTargetId: '',
      paintSecondaryColor: this.colors.background,
      paintGradientStyle: PaintGradientStyle.LINEAR,
      paintGradientReverse: false,
      paintClip: sourceClip,
      paintClipMask: resolvedClipMask,
      paintClipMaskWidth: resolvedClipMask.length > 0 ? this.document.sourceWidth : 0,
      paintFillTolerance: DEFAULT_FILL_TOLERANCE,
      paintFillContiguous: true,
      paintFillAntialias: true,
      paintCloneSource: clonePaintPoint(normalizedSource[0]),
      paintRetouchStrength: DEFAULT_RETOUCH_STRENGTH,
      paintSpongeMode: 1,
      paintRetouchRange: DEFAULT_RETOUCH_RANGE
    };
    this.commitBeforeChange();
    const selectedIndex: number = this.findLayerIndex(this.selectedLayerId);
    this.document.layers.splice(selectedIndex + 1, 0, layer);
    this.selectedLayerId = id;
    this.sidebarTab = SidebarTab.PROPERTIES;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Clone', normalizedSource[0].x.toString() + ', ' +
      normalizedSource[0].y.toString(), 'paint'));
    return id;
  }

  addBlurLayer(points: TransformPoint[], width: number = DEFAULT_PAINT_WIDTH,
    strength: number = DEFAULT_RETOUCH_STRENGTH, clip?: SelectionRect): string {
    const normalizedPoints: TransformPoint[] = normalizePaintPoints(points,
      this.document.sourceWidth, this.document.sourceHeight);
    const normalizedWidth: number = Number.isNaN(width) ? DEFAULT_PAINT_WIDTH :
      Math.max(1, Math.min(96, Math.round(width)));
    const normalizedStrength: number = Number.isNaN(strength) ? DEFAULT_RETOUCH_STRENGTH :
      Math.max(1, Math.min(100, Math.round(strength)));
    if (normalizedPoints.length === 0) {
      return '';
    }
    let sourceClip: SelectionRect = clip !== undefined ?
      normalizeSelectionRect(clip, this.document.sourceWidth, this.document.sourceHeight) :
      fullSelectionRect(this.document.sourceWidth, this.document.sourceHeight);
    if (clip === undefined && this.document.selection.active) {
      const selectionCrop: CropRect = selectionToCropRect(this.getSelectionRect(), this.document.crop.rect,
        this.document.transform);
      sourceClip = normalizeSelectionRect({
        x: selectionCrop.x,
        y: selectionCrop.y,
        width: selectionCrop.width,
        height: selectionCrop.height
      }, this.document.sourceWidth, this.document.sourceHeight);
    }
    const resolvedClipMask: number[] = this.resolveSelectionClipMask(clip);
    let suffix: number = 1;
    let id: string = 'layer-blur';
    let name: string = 'Blur';
    while (this.getLayer(id) !== undefined) {
      suffix += 1;
      id = 'layer-blur-' + suffix.toString();
      name = 'Blur ' + suffix.toString();
    }
    const layer: LayerModel = {
      id: id,
      name: name,
      kind: 'paint',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
      textColor: this.colors.foreground,
      textX: 24,
      textY: 24,
      shapeType: ShapeType.RECTANGLE,
      shapeX: 0,
      shapeY: 0,
      shapeWidth: 0,
      shapeHeight: 0,
      shapeFill: this.colors.foreground,
      shapeStroke: this.colors.background,
      shapeStrokeWidth: 2,
      paintPoints: normalizedPoints.map((point: TransformPoint) => clonePaintPoint(point)),
      paintColor: this.colors.foreground,
      paintWidth: normalizedWidth,
      paintMode: PaintMode.BLUR,
      paintTargetId: '',
      paintSecondaryColor: this.colors.background,
      paintGradientStyle: PaintGradientStyle.LINEAR,
      paintGradientReverse: false,
      paintClip: sourceClip,
      paintClipMask: resolvedClipMask,
      paintClipMaskWidth: resolvedClipMask.length > 0 ? this.document.sourceWidth : 0,
      paintFillTolerance: DEFAULT_FILL_TOLERANCE,
      paintFillContiguous: true,
      paintFillAntialias: true,
      paintCloneSource: { x: 0, y: 0 },
      paintRetouchStrength: normalizedStrength,
      paintSpongeMode: 1,
      paintRetouchRange: DEFAULT_RETOUCH_RANGE
    };
    this.commitBeforeChange();
    const selectedIndex: number = this.findLayerIndex(this.selectedLayerId);
    this.document.layers.splice(selectedIndex + 1, 0, layer);
    this.selectedLayerId = id;
    this.sidebarTab = SidebarTab.PROPERTIES;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Blur', normalizedPoints.length.toString() + ' points',
      'paint'));
    return id;
  }

  addSharpenLayer(points: TransformPoint[], width: number = DEFAULT_PAINT_WIDTH,
    strength: number = DEFAULT_RETOUCH_STRENGTH, clip?: SelectionRect): string {
    const normalizedPoints: TransformPoint[] = normalizePaintPoints(points,
      this.document.sourceWidth, this.document.sourceHeight);
    const normalizedWidth: number = Number.isNaN(width) ? DEFAULT_PAINT_WIDTH :
      Math.max(1, Math.min(96, Math.round(width)));
    const normalizedStrength: number = Number.isNaN(strength) ? DEFAULT_RETOUCH_STRENGTH :
      Math.max(1, Math.min(100, Math.round(strength)));
    if (normalizedPoints.length === 0) {
      return '';
    }
    let sourceClip: SelectionRect = clip !== undefined ?
      normalizeSelectionRect(clip, this.document.sourceWidth, this.document.sourceHeight) :
      fullSelectionRect(this.document.sourceWidth, this.document.sourceHeight);
    if (clip === undefined && this.document.selection.active) {
      const selectionCrop: CropRect = selectionToCropRect(this.getSelectionRect(), this.document.crop.rect,
        this.document.transform);
      sourceClip = normalizeSelectionRect({
        x: selectionCrop.x,
        y: selectionCrop.y,
        width: selectionCrop.width,
        height: selectionCrop.height
      }, this.document.sourceWidth, this.document.sourceHeight);
    }
    const resolvedClipMask: number[] = this.resolveSelectionClipMask(clip);
    let suffix: number = 1;
    let id: string = 'layer-sharpen';
    let name: string = 'Sharpen';
    while (this.getLayer(id) !== undefined) {
      suffix += 1;
      id = 'layer-sharpen-' + suffix.toString();
      name = 'Sharpen ' + suffix.toString();
    }
    const layer: LayerModel = {
      id: id,
      name: name,
      kind: 'paint',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
      textColor: this.colors.foreground,
      textX: 24,
      textY: 24,
      shapeType: ShapeType.RECTANGLE,
      shapeX: 0,
      shapeY: 0,
      shapeWidth: 0,
      shapeHeight: 0,
      shapeFill: this.colors.foreground,
      shapeStroke: this.colors.background,
      shapeStrokeWidth: 2,
      paintPoints: normalizedPoints.map((point: TransformPoint) => clonePaintPoint(point)),
      paintColor: this.colors.foreground,
      paintWidth: normalizedWidth,
      paintMode: PaintMode.SHARPEN,
      paintTargetId: '',
      paintSecondaryColor: this.colors.background,
      paintGradientStyle: PaintGradientStyle.LINEAR,
      paintGradientReverse: false,
      paintClip: sourceClip,
      paintClipMask: resolvedClipMask,
      paintClipMaskWidth: resolvedClipMask.length > 0 ? this.document.sourceWidth : 0,
      paintFillTolerance: DEFAULT_FILL_TOLERANCE,
      paintFillContiguous: true,
      paintFillAntialias: true,
      paintCloneSource: { x: 0, y: 0 },
      paintRetouchStrength: normalizedStrength,
      paintSpongeMode: 1,
      paintRetouchRange: DEFAULT_RETOUCH_RANGE
    };
    this.commitBeforeChange();
    const selectedIndex: number = this.findLayerIndex(this.selectedLayerId);
    this.document.layers.splice(selectedIndex + 1, 0, layer);
    this.selectedLayerId = id;
    this.sidebarTab = SidebarTab.PROPERTIES;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Sharpen', normalizedPoints.length.toString() + ' points',
      'paint'));
    return id;
  }

  addSmudgeLayer(points: TransformPoint[], width: number = DEFAULT_PAINT_WIDTH,
    strength: number = DEFAULT_RETOUCH_STRENGTH, clip?: SelectionRect): string {
    const normalizedPoints: TransformPoint[] = normalizePaintPoints(points,
      this.document.sourceWidth, this.document.sourceHeight);
    const normalizedWidth: number = Number.isNaN(width) ? DEFAULT_PAINT_WIDTH :
      Math.max(1, Math.min(96, Math.round(width)));
    const normalizedStrength: number = Number.isNaN(strength) ? DEFAULT_RETOUCH_STRENGTH :
      Math.max(1, Math.min(100, Math.round(strength)));
    if (normalizedPoints.length === 0) {
      return '';
    }
    let sourceClip: SelectionRect = clip !== undefined ?
      normalizeSelectionRect(clip, this.document.sourceWidth, this.document.sourceHeight) :
      fullSelectionRect(this.document.sourceWidth, this.document.sourceHeight);
    if (clip === undefined && this.document.selection.active) {
      const selectionCrop: CropRect = selectionToCropRect(this.getSelectionRect(), this.document.crop.rect,
        this.document.transform);
      sourceClip = normalizeSelectionRect({
        x: selectionCrop.x,
        y: selectionCrop.y,
        width: selectionCrop.width,
        height: selectionCrop.height
      }, this.document.sourceWidth, this.document.sourceHeight);
    }
    const resolvedClipMask: number[] = this.resolveSelectionClipMask(clip);
    let suffix: number = 1;
    let id: string = 'layer-smudge';
    let name: string = 'Smudge';
    while (this.getLayer(id) !== undefined) {
      suffix += 1;
      id = 'layer-smudge-' + suffix.toString();
      name = 'Smudge ' + suffix.toString();
    }
    const layer: LayerModel = {
      id: id,
      name: name,
      kind: 'paint',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
      textColor: this.colors.foreground,
      textX: 24,
      textY: 24,
      shapeType: ShapeType.RECTANGLE,
      shapeX: 0,
      shapeY: 0,
      shapeWidth: 0,
      shapeHeight: 0,
      shapeFill: this.colors.foreground,
      shapeStroke: this.colors.background,
      shapeStrokeWidth: 2,
      paintPoints: normalizedPoints.map((point: TransformPoint) => clonePaintPoint(point)),
      paintColor: this.colors.foreground,
      paintWidth: normalizedWidth,
      paintMode: PaintMode.SMUDGE,
      paintTargetId: '',
      paintSecondaryColor: this.colors.background,
      paintGradientStyle: PaintGradientStyle.LINEAR,
      paintGradientReverse: false,
      paintClip: sourceClip,
      paintClipMask: resolvedClipMask,
      paintClipMaskWidth: resolvedClipMask.length > 0 ? this.document.sourceWidth : 0,
      paintFillTolerance: DEFAULT_FILL_TOLERANCE,
      paintFillContiguous: true,
      paintFillAntialias: true,
      paintCloneSource: { x: 0, y: 0 },
      paintRetouchStrength: normalizedStrength,
      paintSpongeMode: 1,
      paintRetouchRange: DEFAULT_RETOUCH_RANGE
    };
    this.commitBeforeChange();
    const selectedIndex: number = this.findLayerIndex(this.selectedLayerId);
    this.document.layers.splice(selectedIndex + 1, 0, layer);
    this.selectedLayerId = id;
    this.sidebarTab = SidebarTab.PROPERTIES;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Smudge', normalizedPoints.length.toString() + ' points',
      'paint'));
    return id;
  }

  addSpongeLayer(points: TransformPoint[], width: number = DEFAULT_PAINT_WIDTH,
    flow: number = DEFAULT_RETOUCH_STRENGTH, mode: number = 1, clip?: SelectionRect): string {
    const normalizedPoints: TransformPoint[] = normalizePaintPoints(points,
      this.document.sourceWidth, this.document.sourceHeight);
    const normalizedWidth: number = Number.isNaN(width) ? DEFAULT_PAINT_WIDTH :
      Math.max(1, Math.min(96, Math.round(width)));
    const normalizedFlow: number = Number.isNaN(flow) ? DEFAULT_RETOUCH_STRENGTH :
      Math.max(1, Math.min(100, Math.round(flow)));
    const normalizedMode: number = mode === 0 ? 0 : 1;
    if (normalizedPoints.length === 0) {
      return '';
    }
    let sourceClip: SelectionRect = clip !== undefined ?
      normalizeSelectionRect(clip, this.document.sourceWidth, this.document.sourceHeight) :
      fullSelectionRect(this.document.sourceWidth, this.document.sourceHeight);
    if (clip === undefined && this.document.selection.active) {
      const selectionCrop: CropRect = selectionToCropRect(this.getSelectionRect(), this.document.crop.rect,
        this.document.transform);
      sourceClip = normalizeSelectionRect({
        x: selectionCrop.x,
        y: selectionCrop.y,
        width: selectionCrop.width,
        height: selectionCrop.height
      }, this.document.sourceWidth, this.document.sourceHeight);
    }
    const resolvedClipMask: number[] = this.resolveSelectionClipMask(clip);
    let suffix: number = 1;
    let id: string = 'layer-sponge';
    let name: string = 'Sponge';
    while (this.getLayer(id) !== undefined) {
      suffix += 1;
      id = 'layer-sponge-' + suffix.toString();
      name = 'Sponge ' + suffix.toString();
    }
    const layer: LayerModel = {
      id: id,
      name: name,
      kind: 'paint',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
      textColor: this.colors.foreground,
      textX: 24,
      textY: 24,
      shapeType: ShapeType.RECTANGLE,
      shapeX: 0,
      shapeY: 0,
      shapeWidth: 0,
      shapeHeight: 0,
      shapeFill: this.colors.foreground,
      shapeStroke: this.colors.background,
      shapeStrokeWidth: 2,
      paintPoints: normalizedPoints.map((point: TransformPoint) => clonePaintPoint(point)),
      paintColor: this.colors.foreground,
      paintWidth: normalizedWidth,
      paintMode: PaintMode.SPONGE,
      paintTargetId: '',
      paintSecondaryColor: this.colors.background,
      paintGradientStyle: PaintGradientStyle.LINEAR,
      paintGradientReverse: false,
      paintClip: sourceClip,
      paintClipMask: resolvedClipMask,
      paintClipMaskWidth: resolvedClipMask.length > 0 ? this.document.sourceWidth : 0,
      paintFillTolerance: DEFAULT_FILL_TOLERANCE,
      paintFillContiguous: true,
      paintFillAntialias: true,
      paintCloneSource: { x: 0, y: 0 },
      paintRetouchStrength: normalizedFlow,
      paintSpongeMode: normalizedMode,
      paintRetouchRange: DEFAULT_RETOUCH_RANGE
    };
    this.commitBeforeChange();
    const selectedIndex: number = this.findLayerIndex(this.selectedLayerId);
    this.document.layers.splice(selectedIndex + 1, 0, layer);
    this.selectedLayerId = id;
    this.sidebarTab = SidebarTab.PROPERTIES;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Sponge', normalizedPoints.length.toString() + ' points',
      'paint'));
    return id;
  }

  private addDodgeBurnLayer(points: TransformPoint[], width: number, exposure: number,
    range: number, mode: PaintMode, clip?: SelectionRect): string {
    const resolvedClipMask: number[] = this.resolveSelectionClipMask(clip);
    const normalizedPoints: TransformPoint[] = normalizePaintPoints(points,
      this.document.sourceWidth, this.document.sourceHeight);
    const normalizedWidth: number = Number.isNaN(width) ? DEFAULT_PAINT_WIDTH :
      Math.max(1, Math.min(96, Math.round(width)));
    const normalizedExposure: number = Number.isNaN(exposure) ? DEFAULT_RETOUCH_STRENGTH :
      Math.max(0, Math.min(100, Math.round(exposure)));
    const normalizedRange: number = Number.isNaN(range) ? DEFAULT_RETOUCH_RANGE :
      Math.max(0, Math.min(2, Math.round(range)));
    if (normalizedPoints.length === 0 ||
      (mode !== PaintMode.DODGE && mode !== PaintMode.BURN)) {
      return '';
    }
    let sourceClip: SelectionRect = clip !== undefined ?
      normalizeSelectionRect(clip, this.document.sourceWidth, this.document.sourceHeight) :
      fullSelectionRect(this.document.sourceWidth, this.document.sourceHeight);
    if (clip === undefined && this.document.selection.active) {
      const selectionCrop: CropRect = selectionToCropRect(this.getSelectionRect(), this.document.crop.rect,
        this.document.transform);
      sourceClip = normalizeSelectionRect({
        x: selectionCrop.x,
        y: selectionCrop.y,
        width: selectionCrop.width,
        height: selectionCrop.height
      }, this.document.sourceWidth, this.document.sourceHeight);
    }
    const label: string = mode === PaintMode.DODGE ? 'Dodge' : 'Burn';
    const prefix: string = mode === PaintMode.DODGE ? 'layer-dodge' : 'layer-burn';
    let suffix: number = 1;
    let id: string = prefix;
    let name: string = label;
    while (this.getLayer(id) !== undefined) {
      suffix += 1;
      id = prefix + '-' + suffix.toString();
      name = label + ' ' + suffix.toString();
    }
    const layer: LayerModel = {
      id: id,
      name: name,
      kind: 'paint',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
      textColor: this.colors.foreground,
      textX: 24,
      textY: 24,
      shapeType: ShapeType.RECTANGLE,
      shapeX: 0,
      shapeY: 0,
      shapeWidth: 0,
      shapeHeight: 0,
      shapeFill: this.colors.foreground,
      shapeStroke: this.colors.background,
      shapeStrokeWidth: 2,
      paintPoints: normalizedPoints.map((point: TransformPoint) => clonePaintPoint(point)),
      paintColor: this.colors.foreground,
      paintWidth: normalizedWidth,
      paintMode: mode,
      paintTargetId: '',
      paintSecondaryColor: this.colors.background,
      paintGradientStyle: PaintGradientStyle.LINEAR,
      paintGradientReverse: false,
      paintClip: sourceClip,
      paintClipMask: resolvedClipMask,
      paintClipMaskWidth: resolvedClipMask.length > 0 ? this.document.sourceWidth : 0,
      paintFillTolerance: DEFAULT_FILL_TOLERANCE,
      paintFillContiguous: true,
      paintFillAntialias: true,
      paintCloneSource: { x: 0, y: 0 },
      paintRetouchStrength: normalizedExposure,
      paintSpongeMode: 1,
      paintRetouchRange: normalizedRange
    };
    this.commitBeforeChange();
    const selectedIndex: number = this.findLayerIndex(this.selectedLayerId);
    this.document.layers.splice(selectedIndex + 1, 0, layer);
    this.selectedLayerId = id;
    this.sidebarTab = SidebarTab.PROPERTIES;
    this.document.dirty = true;
    this.pushHistory(historyEntry(label, normalizedPoints.length.toString() + ' points', 'paint'));
    return id;
  }

  addDodgeLayer(points: TransformPoint[], width: number = DEFAULT_PAINT_WIDTH,
    exposure: number = DEFAULT_RETOUCH_STRENGTH, range: number = DEFAULT_RETOUCH_RANGE,
    clip?: SelectionRect): string {
    return this.addDodgeBurnLayer(points, width, exposure, range, PaintMode.DODGE, clip);
  }

  addBurnLayer(points: TransformPoint[], width: number = DEFAULT_PAINT_WIDTH,
    exposure: number = DEFAULT_RETOUCH_STRENGTH, range: number = DEFAULT_RETOUCH_RANGE,
    clip?: SelectionRect): string {
    return this.addDodgeBurnLayer(points, width, exposure, range, PaintMode.BURN, clip);
  }


  addRedEyeLayer(points: TransformPoint[], width: number = DEFAULT_PAINT_WIDTH,
    flow: number = DEFAULT_RETOUCH_STRENGTH, clip?: SelectionRect): string {
    const normalizedPoints: TransformPoint[] = normalizePaintPoints(points,
      this.document.sourceWidth, this.document.sourceHeight);
    const normalizedWidth: number = Number.isNaN(width) ? DEFAULT_PAINT_WIDTH :
      Math.max(1, Math.min(96, Math.round(width)));
    const normalizedFlow: number = Number.isNaN(flow) ? DEFAULT_RETOUCH_STRENGTH :
      Math.max(1, Math.min(100, Math.round(flow)));
    if (normalizedPoints.length === 0) {
      return '';
    }
    let sourceClip: SelectionRect = clip !== undefined ?
      normalizeSelectionRect(clip, this.document.sourceWidth, this.document.sourceHeight) :
      fullSelectionRect(this.document.sourceWidth, this.document.sourceHeight);
    if (clip === undefined && this.document.selection.active) {
      const selectionCrop: CropRect = selectionToCropRect(this.getSelectionRect(), this.document.crop.rect,
        this.document.transform);
      sourceClip = normalizeSelectionRect({
        x: selectionCrop.x,
        y: selectionCrop.y,
        width: selectionCrop.width,
        height: selectionCrop.height
      }, this.document.sourceWidth, this.document.sourceHeight);
    }
    const resolvedClipMask: number[] = this.resolveSelectionClipMask(clip);
    let suffix: number = 1;
    let id: string = 'layer-redeye';
    let name: string = 'Red Eye';
    while (this.getLayer(id) !== undefined) {
      suffix += 1;
      id = 'layer-redeye-' + suffix.toString();
      name = 'Red Eye ' + suffix.toString();
    }
    const layer: LayerModel = {
      id: id,
      name: name,
      kind: 'paint',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
      textColor: this.colors.foreground,
      textX: 24,
      textY: 24,
      shapeType: ShapeType.RECTANGLE,
      shapeX: 0,
      shapeY: 0,
      shapeWidth: 0,
      shapeHeight: 0,
      shapeFill: this.colors.foreground,
      shapeStroke: this.colors.background,
      shapeStrokeWidth: 2,
      paintPoints: normalizedPoints.map((point: TransformPoint) => clonePaintPoint(point)),
      paintColor: this.colors.foreground,
      paintWidth: normalizedWidth,
      paintMode: PaintMode.RED_EYE,
      paintTargetId: '',
      paintSecondaryColor: this.colors.background,
      paintGradientStyle: PaintGradientStyle.LINEAR,
      paintGradientReverse: false,
      paintClip: sourceClip,
      paintClipMask: resolvedClipMask,
      paintClipMaskWidth: resolvedClipMask.length > 0 ? this.document.sourceWidth : 0,
      paintFillTolerance: DEFAULT_FILL_TOLERANCE,
      paintFillContiguous: true,
      paintFillAntialias: true,
      paintCloneSource: { x: 0, y: 0 },
      paintRetouchStrength: normalizedFlow,
      paintSpongeMode: 1,
      paintRetouchRange: DEFAULT_RETOUCH_RANGE
    };
    this.commitBeforeChange();
    const selectedIndex: number = this.findLayerIndex(this.selectedLayerId);
    this.document.layers.splice(selectedIndex + 1, 0, layer);
    this.selectedLayerId = id;
    this.sidebarTab = SidebarTab.PROPERTIES;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Red Eye', normalizedPoints.length.toString() + ' points', 'paint'));
    return id;
  }

  addSpotHealLayer(points: TransformPoint[], width: number = DEFAULT_PAINT_WIDTH,
    strength: number = DEFAULT_RETOUCH_STRENGTH, clip?: SelectionRect): string {
    const normalizedPoints: TransformPoint[] = normalizePaintPoints(points,
      this.document.sourceWidth, this.document.sourceHeight);
    const normalizedWidth: number = Number.isNaN(width) ? DEFAULT_PAINT_WIDTH :
      Math.max(1, Math.min(96, Math.round(width)));
    const normalizedStrength: number = Number.isNaN(strength) ? DEFAULT_RETOUCH_STRENGTH :
      Math.max(1, Math.min(100, Math.round(strength)));
    if (normalizedPoints.length === 0) {
      return '';
    }
    let sourceClip: SelectionRect = clip !== undefined ?
      normalizeSelectionRect(clip, this.document.sourceWidth, this.document.sourceHeight) :
      fullSelectionRect(this.document.sourceWidth, this.document.sourceHeight);
    if (clip === undefined && this.document.selection.active) {
      const selectionCrop: CropRect = selectionToCropRect(this.getSelectionRect(), this.document.crop.rect,
        this.document.transform);
      sourceClip = normalizeSelectionRect({
        x: selectionCrop.x,
        y: selectionCrop.y,
        width: selectionCrop.width,
        height: selectionCrop.height
      }, this.document.sourceWidth, this.document.sourceHeight);
    }
    const resolvedClipMask: number[] = this.resolveSelectionClipMask(clip);
    let suffix: number = 1;
    let id: string = 'layer-spot-heal';
    let name: string = 'Spot Healing';
    while (this.getLayer(id) !== undefined) {
      suffix += 1;
      id = 'layer-spot-heal-' + suffix.toString();
      name = 'Spot Healing ' + suffix.toString();
    }
    const layer: LayerModel = {
      id: id,
      name: name,
      kind: 'paint',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
      textColor: this.colors.foreground,
      textX: 24,
      textY: 24,
      shapeType: ShapeType.RECTANGLE,
      shapeX: 0,
      shapeY: 0,
      shapeWidth: 0,
      shapeHeight: 0,
      shapeFill: this.colors.foreground,
      shapeStroke: this.colors.background,
      shapeStrokeWidth: 2,
      paintPoints: normalizedPoints.map((point: TransformPoint) => clonePaintPoint(point)),
      paintColor: this.colors.foreground,
      paintWidth: normalizedWidth,
      paintMode: PaintMode.SPOT_HEAL,
      paintTargetId: '',
      paintSecondaryColor: this.colors.background,
      paintGradientStyle: PaintGradientStyle.LINEAR,
      paintGradientReverse: false,
      paintClip: sourceClip,
      paintClipMask: resolvedClipMask,
      paintClipMaskWidth: resolvedClipMask.length > 0 ? this.document.sourceWidth : 0,
      paintFillTolerance: DEFAULT_FILL_TOLERANCE,
      paintFillContiguous: true,
      paintFillAntialias: true,
      paintCloneSource: { x: 0, y: 0 },
      paintRetouchStrength: normalizedStrength,
      paintSpongeMode: 1,
      paintRetouchRange: DEFAULT_RETOUCH_RANGE
    };
    this.commitBeforeChange();
    const selectedIndex: number = this.findLayerIndex(this.selectedLayerId);
    this.document.layers.splice(selectedIndex + 1, 0, layer);
    this.selectedLayerId = id;
    this.sidebarTab = SidebarTab.PROPERTIES;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Spot Healing', normalizedPoints.length.toString() + ' points', 'paint'));
    return id;
  }

  setPaintColor(id: string, value: string): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    const normalized: string = normalizeHexColor(value);
    if (layer === undefined || layer.kind !== 'paint' || normalized.length === 0 ||
      layer.paintColor === normalized) {
      return false;
    }
    this.commitBeforeChange();
    layer.paintColor = normalized;
    this.document.dirty = true;
    this.pushHistory(historyEntry(layer.paintMode === PaintMode.GRADIENT ?
      'Gradient start color' : layer.paintMode === PaintMode.FILL ?
      'Fill color' : 'Brush color', normalized, 'paint'));
    return true;
  }

  setPaintSecondaryColor(id: string, value: string): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    const normalized: string = normalizeHexColor(value);
    if (layer === undefined || layer.kind !== 'paint' ||
      layer.paintMode !== PaintMode.GRADIENT || normalized.length === 0 ||
      layer.paintSecondaryColor === normalized) {
      return false;
    }
    this.commitBeforeChange();
    layer.paintSecondaryColor = normalized;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Gradient color', normalized, 'paint'));
    return true;
  }

  setPaintGradientReverse(id: string, reverse: boolean): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    if (layer === undefined || layer.kind !== 'paint' ||
      layer.paintMode !== PaintMode.GRADIENT || layer.paintGradientReverse === reverse) {
      return false;
    }
    this.commitBeforeChange();
    layer.paintGradientReverse = reverse;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Reverse gradient', reverse ? 'On' : 'Off', 'paint'));
    return true;
  }

  setPaintFillTolerance(id: string, value: number): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    const normalized: number = Math.max(0, Math.min(255, Math.round(value)));
    if (layer === undefined || layer.kind !== 'paint' || layer.paintMode !== PaintMode.FILL ||
      layer.paintFillTolerance === normalized) {
      return false;
    }
    this.commitBeforeChange();
    layer.paintFillTolerance = normalized;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Fill tolerance', normalized.toString(), 'paint'));
    return true;
  }

  setPaintFillContiguous(id: string, contiguous: boolean): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    if (layer === undefined || layer.kind !== 'paint' || layer.paintMode !== PaintMode.FILL ||
      layer.paintFillContiguous === contiguous) {
      return false;
    }
    this.commitBeforeChange();
    layer.paintFillContiguous = contiguous;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Fill contiguous', contiguous ? 'On' : 'Off', 'paint'));
    return true;
  }

  setPaintFillAntialias(id: string, antialias: boolean): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    if (layer === undefined || layer.kind !== 'paint' || layer.paintMode !== PaintMode.FILL ||
      layer.paintFillAntialias === antialias) {
      return false;
    }
    this.commitBeforeChange();
    layer.paintFillAntialias = antialias;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Fill anti-alias', antialias ? 'On' : 'Off', 'paint'));
    return true;
  }

  setPaintWidth(id: string, value: number): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    const normalized: number = Number.isNaN(value) ? DEFAULT_PAINT_WIDTH :
      Math.max(1, Math.min(96, Math.round(value)));
    if (layer === undefined || layer.kind !== 'paint' || layer.paintWidth === normalized) {
      return false;
    }
    this.commitBeforeChange();
    layer.paintWidth = normalized;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Brush size', normalized.toString() + ' px', 'paint'));
    return true;
  }

  setPaintRetouchStrength(id: string, value: number): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    const isDodgeBurn: boolean = layer !== undefined &&
      (layer.paintMode === PaintMode.DODGE || layer.paintMode === PaintMode.BURN);
    const isRedEye: boolean = layer !== undefined && layer.paintMode === PaintMode.RED_EYE;
    const isSpotHeal: boolean = layer !== undefined && layer.paintMode === PaintMode.SPOT_HEAL;
    const normalized: number = Number.isNaN(value) ? DEFAULT_RETOUCH_STRENGTH :
      Math.max(isDodgeBurn ? 0 : 1, Math.min(100, Math.round(value)));
    if (layer === undefined || layer.kind !== 'paint' ||
      (layer.paintMode !== PaintMode.BLUR && layer.paintMode !== PaintMode.SHARPEN &&
        layer.paintMode !== PaintMode.SMUDGE && layer.paintMode !== PaintMode.SPONGE &&
        !isDodgeBurn && !isRedEye && !isSpotHeal) ||
      layer.paintRetouchStrength === normalized) {
      return false;
    }
    this.commitBeforeChange();
    layer.paintRetouchStrength = normalized;
    this.document.dirty = true;
    const label: string = layer.paintMode === PaintMode.BLUR ? 'Blur strength' :
      layer.paintMode === PaintMode.SMUDGE ? 'Smudge strength' :
      layer.paintMode === PaintMode.SPONGE ? 'Sponge flow' :
      layer.paintMode === PaintMode.DODGE ? 'Dodge exposure' :
      layer.paintMode === PaintMode.BURN ? 'Burn exposure' :
      layer.paintMode === PaintMode.RED_EYE ? 'Red eye flow' :
      layer.paintMode === PaintMode.SPOT_HEAL ? 'Heal flow' : 'Sharpen strength';
    this.pushHistory(historyEntry(label, normalized.toString() + '%', 'paint'));
    return true;
  }

  setPaintRetouchRange(id: string, range: number): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    const normalized: number = Number.isNaN(range) ? DEFAULT_RETOUCH_RANGE :
      Math.max(0, Math.min(2, Math.round(range)));
    if (layer === undefined || layer.kind !== 'paint' ||
      (layer.paintMode !== PaintMode.DODGE && layer.paintMode !== PaintMode.BURN) ||
      layer.paintRetouchRange === normalized) {
      return false;
    }
    this.commitBeforeChange();
    layer.paintRetouchRange = normalized;
    this.document.dirty = true;
    const label: string = normalized === 0 ? 'Shadows' :
      normalized === 1 ? 'Midtones' : 'Highlights';
    this.pushHistory(historyEntry(layer.paintMode === PaintMode.DODGE ? 'Dodge range' : 'Burn range',
      label, 'paint'));
    return true;
  }

  setPaintSpongeMode(id: string, mode: number): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    const normalized: number = mode === 0 ? 0 : 1;
    if (layer === undefined || layer.kind !== 'paint' || layer.paintMode !== PaintMode.SPONGE ||
      layer.paintSpongeMode === normalized) {
      return false;
    }
    this.commitBeforeChange();
    layer.paintSpongeMode = normalized;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Sponge mode', normalized === 0 ? 'Desaturate' : 'Saturate',
      'paint'));
    return true;
  }

  setPaintMode(id: string, mode: PaintMode): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    if (layer === undefined || layer.kind !== 'paint' || layer.paintMode === mode) {
      return false;
    }
    this.commitBeforeChange();
    layer.paintMode = mode;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Paint mode', mode, 'paint'));
    return true;
  }

  setShapeBounds(id: string, x: number, y: number, width: number, height: number): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    if (layer === undefined || layer.kind !== 'shape') {
      return false;
    }
    const next: SelectionRect = normalizeSelectionRect({ x: x, y: y, width: width, height: height },
      this.document.sourceWidth, this.document.sourceHeight);
    if (layer.shapeX === next.x && layer.shapeY === next.y && layer.shapeWidth === next.width &&
      layer.shapeHeight === next.height) {
      return false;
    }
    this.commitBeforeChange();
    layer.shapeX = next.x;
    layer.shapeY = next.y;
    layer.shapeWidth = next.width;
    layer.shapeHeight = next.height;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Edit shape', next.width.toString() + ' × ' + next.height.toString(), 'layer'));
    return true;
  }

  setShapeFill(id: string, value: string): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    const normalized: string = normalizeHexColor(value);
    if (layer === undefined || layer.kind !== 'shape' || normalized.length === 0 ||
      layer.shapeFill === normalized) {
      return false;
    }
    this.commitBeforeChange();
    layer.shapeFill = normalized;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Shape fill', normalized, 'layer'));
    return true;
  }

  setShapeStroke(id: string, value: string): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    const normalized: string = normalizeHexColor(value);
    if (layer === undefined || layer.kind !== 'shape' || normalized.length === 0 ||
      layer.shapeStroke === normalized) {
      return false;
    }
    this.commitBeforeChange();
    layer.shapeStroke = normalized;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Shape stroke', normalized, 'layer'));
    return true;
  }

  setShapeStrokeWidth(id: string, value: number): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    const next: number = Number.isNaN(value) ? 2 : Math.max(0, Math.min(24, Math.round(value)));
    if (layer === undefined || layer.kind !== 'shape' || layer.shapeStrokeWidth === next) {
      return false;
    }
    this.commitBeforeChange();
    layer.shapeStrokeWidth = next;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Shape stroke width', next.toString() + ' px', 'layer'));
    return true;
  }

  moveLayerByDelta(id: string, deltaX: number, deltaY: number): boolean {
    const layer: LayerModel | undefined = this.getLayer(id);
    if (layer === undefined || (layer.kind !== 'text' && layer.kind !== 'shape')) {
      return false;
    }
    const dx: number = Number.isFinite(deltaX) ? Math.round(deltaX) : 0;
    const dy: number = Number.isFinite(deltaY) ? Math.round(deltaY) : 0;
    if (dx === 0 && dy === 0) {
      return false;
    }
    if (layer.kind === 'text') {
      const nextX: number = Math.max(0, Math.min(this.document.sourceWidth - 1, layer.textX + dx));
      const nextY: number = Math.max(0, Math.min(this.document.sourceHeight - 1, layer.textY + dy));
      if (nextX === layer.textX && nextY === layer.textY) {
        return false;
      }
      this.commitBeforeChange();
      layer.textX = nextX;
      layer.textY = nextY;
      this.document.dirty = true;
      this.pushHistory(historyEntry('Move text', layer.name, 'layer'));
      return true;
    }
    const nextX: number = Math.max(0, Math.min(this.document.sourceWidth - layer.shapeWidth,
      layer.shapeX + dx));
    const nextY: number = Math.max(0, Math.min(this.document.sourceHeight - layer.shapeHeight,
      layer.shapeY + dy));
    if (nextX === layer.shapeX && nextY === layer.shapeY) {
      return false;
    }
    this.commitBeforeChange();
    layer.shapeX = nextX;
    layer.shapeY = nextY;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Move shape', layer.name, 'layer'));
    return true;
  }

  setTextContent(id: string, content: string): boolean {
    const layer: LayerModel | undefined = this.getTextLayer(id);
    if (layer === undefined || layer.textContent === content) {
      return false;
    }
    this.commitBeforeChange();
    layer.textContent = content;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Edit text', content, 'edit'));
    return true;
  }

  setTextSize(id: string, value: number): boolean {
    const layer: LayerModel | undefined = this.getTextLayer(id);
    const size: number = Number.isNaN(value) ? 32 : Math.max(8, Math.min(120, Math.round(value)));
    if (layer === undefined || layer.textSize === size) {
      return false;
    }
    this.commitBeforeChange();
    layer.textSize = size;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Text size', layer.name + ' = ' + size.toString() + ' px', 'edit'));
    return true;
  }

  setTextColor(id: string, value: string): boolean {
    const layer: LayerModel | undefined = this.getTextLayer(id);
    const color: string = normalizeHexColor(value);
    if (layer === undefined || color.length === 0 || layer.textColor === color) {
      return false;
    }
    this.commitBeforeChange();
    layer.textColor = color;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Text color', layer.name + ' = ' + color, 'edit'));
    return true;
  }

  setTextPosition(id: string, x: number, y: number): boolean {
    const layer: LayerModel | undefined = this.getTextLayer(id);
    const nextX: number = Number.isNaN(x) ? 0 :
      Math.max(0, Math.min(Math.max(0, this.document.sourceWidth - 1), Math.round(x)));
    const nextY: number = Number.isNaN(y) ? 0 :
      Math.max(0, Math.min(Math.max(0, this.document.sourceHeight - 1), Math.round(y)));
    if (layer === undefined || (layer.textX === nextX && layer.textY === nextY)) {
      return false;
    }
    this.commitBeforeChange();
    layer.textX = nextX;
    layer.textY = nextY;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Move text', layer.name, 'edit'));
    return true;
  }

  addLayer(): void {
    let suffix: number = 1;
    let id: string = 'layer-adjustment-new';
    while (this.getLayer(id) !== undefined) {
      suffix += 1;
      id = 'layer-adjustment-new-' + suffix.toString();
    }
    const layer: LayerModel = {
      id: id,
      name: 'New adjustment',
      kind: 'adjustment',
      visible: true,
      locked: false,
      opacity: 100,
      blendMode: 'Normal',
      textContent: '',
      textSize: 32,
      textColor: DEFAULT_FOREGROUND_COLOR,
      textX: 24,
      textY: 24,
      shapeType: ShapeType.RECTANGLE,
      shapeX: 0,
      shapeY: 0,
      shapeWidth: 0,
      shapeHeight: 0,
      shapeFill: DEFAULT_FOREGROUND_COLOR,
      shapeStroke: DEFAULT_BACKGROUND_COLOR,
      shapeStrokeWidth: 2,
      paintPoints: [],
      paintColor: DEFAULT_FOREGROUND_COLOR,
      paintWidth: DEFAULT_PAINT_WIDTH,
      paintMode: PaintMode.BRUSH,
      paintTargetId: '',
      paintSecondaryColor: DEFAULT_BACKGROUND_COLOR,
      paintGradientStyle: PaintGradientStyle.LINEAR,
      paintGradientReverse: false,
      paintClip: fullSelectionRect(this.document.sourceWidth, this.document.sourceHeight),
      paintClipMask: [],
      paintClipMaskWidth: 0,
      paintFillTolerance: DEFAULT_FILL_TOLERANCE,
      paintFillContiguous: true,
      paintFillAntialias: true,
      paintCloneSource: { x: 0, y: 0 },
      paintRetouchStrength: DEFAULT_RETOUCH_STRENGTH,
      paintSpongeMode: 1,
      paintRetouchRange: DEFAULT_RETOUCH_RANGE
    };
    this.commitBeforeChange();
    const selectedIndex: number = this.findLayerIndex(this.selectedLayerId);
    this.document.layers.splice(selectedIndex + 1, 0, layer);
    this.selectedLayerId = id;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Add layer', layer.name, 'layer'));
  }

  duplicateLayer(id: string): void {
    const source: LayerModel | undefined = this.getLayer(id);
    if (source === undefined) {
      return;
    }
    let suffix: number = 1;
    let copyId: string = source.id + '-copy';
    while (this.getLayer(copyId) !== undefined) {
      suffix += 1;
      copyId = source.id + '-copy-' + suffix.toString();
    }
    const copy: LayerModel = cloneLayer(source);
    copy.id = copyId;
    copy.name = source.name + ' copy' + (suffix > 1 ? ' ' + suffix.toString() : '');
    this.commitBeforeChange();
    const sourceIndex: number = this.findLayerIndex(source.id);
    this.document.layers.splice(sourceIndex + 1, 0, copy);
    this.selectedLayerId = copy.id;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Duplicate layer', copy.name, 'layer'));
  }

  deleteLayer(id: string): void {
    const index: number = this.findLayerIndex(id);
    if (index < 0 || this.document.layers.length <= 1) {
      return;
    }
    const layer: LayerModel = this.document.layers[index];
    this.commitBeforeChange();
    this.document.layers.splice(index, 1);
    const nextIndex: number = Math.min(index, this.document.layers.length - 1);
    this.selectedLayerId = this.document.layers[nextIndex].id;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Delete layer', layer.name, 'layer'));
  }

  moveLayer(id: string, offset: number): void {
    const index: number = this.findLayerIndex(id);
    const target: number = index + (offset < 0 ? -1 : 1);
    if (index < 0 || target < 0 || target >= this.document.layers.length || target === index) {
      return;
    }
    this.commitBeforeChange();
    const layer: LayerModel = this.document.layers[index];
    this.document.layers.splice(index, 1);
    this.document.layers.splice(target, 0, layer);
    this.selectedLayerId = id;
    this.document.dirty = true;
    this.pushHistory(historyEntry('Reorder layer', layer.name, 'layer'));
  }

  setExposure(value: number): void {
    this.updateExposure(value);
  }

  setContrast(value: number): void {
    this.updateContrast(value);
  }

  setSaturation(value: number): void {
    this.updateSaturation(value);
  }

  setTemperature(value: number): void {
    this.updateTemperature(value);
  }

  setBlur(value: number): void {
    this.updateBlur(value);
  }

  resetAdjustments(): void {
    if (this.neutralAdjustments) {
      return;
    }
    this.commitBeforeChange();
    this.document.adjustments = {
      exposure: 0,
      contrast: 0,
      saturation: 0,
      temperature: 0,
      blur: 0
    };
    this.document.dirty = true;
    this.pushHistory(historyEntry('Reset adjustments', 'All values returned to neutral', 'edit'));
  }

  updateExposure(value: number): void {
    this.applyAdjustment('exposure', value);
  }

  updateContrast(value: number): void {
    this.applyAdjustment('contrast', value);
  }

  updateSaturation(value: number): void {
    this.applyAdjustment('saturation', value);
  }

  updateTemperature(value: number): void {
    this.applyAdjustment('temperature', value);
  }

  updateBlur(value: number): void {
    this.applyAdjustment('blur', value);
  }

  updateAdjustment(key: string, value: number): void {
    if (key === 'exposure') {
      this.updateExposure(value);
    } else if (key === 'contrast') {
      this.updateContrast(value);
    } else if (key === 'saturation') {
      this.updateSaturation(value);
    } else if (key === 'temperature') {
      this.updateTemperature(value);
    } else if (key === 'blur') {
      this.updateBlur(value);
    }
  }

  private applyAdjustment(key: string, value: number): void {
    const clamped: number = clampAdjustment(key, value);
    this.commitBeforeChange();
    if (key === 'exposure') {
      this.document.adjustments.exposure = clamped;
    } else if (key === 'contrast') {
      this.document.adjustments.contrast = clamped;
    } else if (key === 'saturation') {
      this.document.adjustments.saturation = clamped;
    } else if (key === 'temperature') {
      this.document.adjustments.temperature = clamped;
    } else if (key === 'blur') {
      this.document.adjustments.blur = clamped;
    }
    this.document.dirty = true;
    this.pushHistory(historyEntry('Adjust ' + key, key + ' = ' + clamped, 'edit'));
  }

  undo(): void {
    if (this.undoStack.length === 0) {
      return;
    }
    this.redoStack.push(this.captureSnapshot());
    const snapshot: DocumentSnapshot = this.undoStack.pop()!;
    this.restoreSnapshot(snapshot);
    this.pushHistory(historyEntry('Undo', 'Restored previous state', 'edit'), true);
    this.canUndo = this.undoStack.length > 0;
    this.canRedo = this.redoStack.length > 0;
  }

  redo(): void {
    if (!this.canRedo || this.redoStack.length === 0) {
      return;
    }
    const snapshot: DocumentSnapshot = this.redoStack.pop()!;
    this.restoreSnapshot(snapshot);
    this.pushHistory(historyEntry('Redo', 'Reapplied state', 'edit'), true);
    this.canRedo = this.redoStack.length > 0;
    this.canUndo = this.undoStack.length > 0;
  }

  async open(context: common.UIAbilityContext): Promise<void> {
    this.busy = true;
    this.message = 'Opening image…';
    try {
      const opened: OpenDocument = await pickAndDecodeImage(context);
      if (opened.source === '' || opened.uri === '') {
        this.message = 'No image selected';
        return;
      }
      await this.releaseDocumentSource();
      this.document.name = opened.name;
      this.document.uri = opened.uri;
      this.document.sourceWidth = opened.width;
      this.document.sourceHeight = opened.height;
      this.document.width = opened.width;
      this.document.height = opened.height;
      this.document.source = opened.source;
      this.document.layers = defaultLayers(opened.name, this.document.sourceWidth,
        this.document.sourceHeight);
      this.selectedLayerId = 'layer-image';
      this.document.adjustments = {
        exposure: 0,
        contrast: 0,
        saturation: 0,
        temperature: 0,
        blur: 0
      };
      this.document.filter = {
        preset: 'none',
        intensity: 100
      };
      this.document.transform = {
        rotation: 0,
        flipHorizontal: false,
        flipVertical: false
      };
      this.document.crop = {
        rect: fullCropRect(this.document.sourceWidth, this.document.sourceHeight)
      };
      this.document.selection = {
        active: false,
        mode: 'rectangle',
        rect: fullSelectionRect(this.document.width, this.document.height),
        points: rectangleSelectionPoints(fullSelectionRect(this.document.width, this.document.height))
      };
      this.document.history = [historyEntry('Open document', opened.name, 'open')];
      this.document.dirty = false;
      this.redoStack = [];
      this.undoStack = [];
      this.zoom = 1;
      this.panX = 0;
      this.panY = 0;
      this.canUndo = false;
      this.canRedo = false;
      this.message = opened.name + ' opened';
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'open failed: %{public}d %{public}s', businessError.code,
        businessError.message);
      this.message = 'Could not open image';
    } finally {
      this.busy = false;
    }
  }

  async export(context: common.UIAbilityContext, format: ExportFormat = ExportFormat.JPEG): Promise<void> {
    this.busy = true;
    this.message = 'Preparing export…';
    let exportSource: image.PixelMap | undefined = undefined;
    let ownsSource: boolean = false;
    try {
      if (typeof this.document.source === 'string') {
        exportSource = await decodeBundledSample(context);
        ownsSource = true;
      } else {
        exportSource = this.document.source;
      }
      const exportedUri: string = await exportPixelMap(context, exportSource, this.document.name,
        format, 92, this.document.adjustments, this.document.filter,
        this.document.layers, this.document.transform, this.document.crop.rect);
      if (exportedUri.length === 0) {
        this.message = 'Export canceled';
        return;
      }
      const label: string = format === ExportFormat.PNG ? 'PNG' : 'JPEG · quality 92';
      this.pushHistory(historyEntry('Export', label, 'export'));
      this.message = 'Export complete';
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'export failed: %{public}d %{public}s', businessError.code,
        businessError.message);
      this.message = 'Could not export image';
    } finally {
      if (ownsSource && exportSource !== undefined) {
        try {
          await exportSource.release();
        } catch (error) {
          hilog.warn(DOMAIN, TAG, 'bundled export PixelMap release failed');
        }
      }
      this.busy = false;
    }
  }

  private commitBeforeChange(): void {
    this.undoStack.push(this.captureSnapshot());
    if (this.undoStack.length > HISTORY_LIMIT) {
      this.undoStack.shift();
    }
  }

  private captureSnapshot(): DocumentSnapshot {
    const points: TransformPoint[] = [];
    for (const point of this.document.selection.points) {
      const copy: TransformPoint = { x: point.x, y: point.y };
      points.push(copy);
    }
    return {
      layers: this.document.layers.map((layer: LayerModel) => cloneLayer(layer)),
      adjustments: cloneAdjustments(this.document.adjustments),
      filter: {
        preset: this.document.filter.preset,
        intensity: this.document.filter.intensity
      },
      transform: cloneTransform(this.document.transform),
      crop: {
        rect: this.getCropRect()
      },
      selectionClipMask: this.selectionClipMask.slice(),
      selection: {
        active: this.document.selection.active,
        mode: this.document.selection.mode,
        rect: this.getSelectionRect(),
        points: points
      },
      colors: cloneColors(this.colors),
      selectedLayerId: this.selectedLayerId,
      dirty: this.document.dirty
    };
  }

  private restoreSnapshot(snapshot: DocumentSnapshot): void {
    const points: TransformPoint[] = [];
    for (const point of snapshot.selection.points) {
      const copy: TransformPoint = { x: point.x, y: point.y };
      points.push(copy);
    }
    this.document.layers = snapshot.layers.map((layer: LayerModel) => cloneLayer(layer));
    this.document.adjustments = cloneAdjustments(snapshot.adjustments);
    this.document.filter = {
      preset: snapshot.filter.preset,
      intensity: snapshot.filter.intensity
    };
    this.document.transform = cloneTransform(snapshot.transform);
    this.document.crop = {
      rect: {
        x: snapshot.crop.rect.x,
        y: snapshot.crop.rect.y,
        width: snapshot.crop.rect.width,
        height: snapshot.crop.rect.height
      }
    };
    this.selectionClipMask = snapshot.selectionClipMask.slice();
    this.document.selection = {
      active: snapshot.selection.active,
      mode: snapshot.selection.mode,
      rect: {
        x: snapshot.selection.rect.x,
        y: snapshot.selection.rect.y,
        width: snapshot.selection.rect.width,
        height: snapshot.selection.rect.height
      },
      points: points
    };
    this.updateDocumentSize();
    this.colors = cloneColors(snapshot.colors);
    this.selectedLayerId = this.getLayer(snapshot.selectedLayerId) !== undefined ?
      snapshot.selectedLayerId : this.document.layers[0].id;
    this.document.dirty = snapshot.dirty;
  }

  private findLayerIndex(id: string): number {
    for (let index: number = 0; index < this.document.layers.length; index++) {
      if (this.document.layers[index].id === id) {
        return index;
      }
    }
    return -1;
  }

  private getTextLayer(id: string): LayerModel | undefined {
    const layer: LayerModel | undefined = this.getLayer(id);
    return layer !== undefined && layer.kind === 'text' ? layer : undefined;
  }

  private updateDocumentSize(): void {
    const size = transformedSize(this.document.crop.rect.width, this.document.crop.rect.height,
      this.document.transform);
    this.document.width = size.width;
    this.document.height = size.height;
  }

  private clearSelectionState(): void {
    this.selectionClipMask = [];
    this.document.selection = {
      active: false,
      mode: 'rectangle',
      rect: fullSelectionRect(this.document.width, this.document.height),
      points: rectangleSelectionPoints(fullSelectionRect(this.document.width, this.document.height))
    };
  }

  private pushHistory(entry: HistoryEntry, preserveRedo: boolean = false): void {
    this.document.history.push(entry);
    if (this.document.history.length > HISTORY_LIMIT) {
      this.document.history.shift();
    }
    this.canUndo = this.undoStack.length > 0;
    if (!preserveRedo) {
      this.canRedo = false;
      this.redoStack = [];
    }
  }

  private async releaseDocumentSource(): Promise<void> {
    if (typeof this.document.source === 'string') {
      return;
    }
    try {
      await this.document.source.release();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'old PixelMap release failed');
    }
  }
}
