import { common } from '@kit.AbilityKit';
import { LengthMetrics, matrix4 } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { EditorController } from '../model/EditorController';
import {
  ColorTarget,
  CropAspect,
  CropRect,
  DEFAULT_BACKGROUND_COLOR,
  DEFAULT_FILL_TOLERANCE,
  DEFAULT_FOREGROUND_COLOR,
  DEFAULT_PAINT_WIDTH,
  DEFAULT_RETOUCH_RANGE,
  DEFAULT_RETOUCH_STRENGTH,
  EditorTool,
  ExportFormat,
  FILTER_PRESET_KEYS,
  FILTER_PRESET_NAMES,
  HistoryEntry,
  LayerModel,
  LAYER_BLEND_MODES,
  PaintGradientStyle,
  PaintMode,
  SelectionRect,
  ShapeType,
  SidebarTab,
  TransformPoint
} from '../model/EditorTypes';
import {
  clonePaintPoint,
  documentFilterMatrix,
  centeredCropRect,
  cropAspectForRect,
  filterPresetLabelFromKey,
  formatAdjustment,
  fullCropRect,
  getFilterPresetMatrix,
  inverseTransformPoint,
  normalizeCropRect,
  sourcePointToCropSpace,
  transformedSize,
  transformPoint
} from '../model/EditorMath';
import { drawing } from '@kit.ArkGraphics2D';

const CONTROL_HEIGHT: number = 38;
const TOOL_RAIL_WIDTH: number = 100;
const SIDEBAR_WIDTH: number = 336;
const MOBILE_BREAKPOINT: number = 900;
const COMPACT_BREAKPOINT: number = 760;
const ACCENT: string = '#2BB8A7';
const ACCENT_WARM: string = '#F1B85B';
const CANVAS_BG: string = '#15181A';
const PANEL_BG: string = '#1D2225';
const PANEL_RAISED: string = '#252B2E';
const PANEL_HOVER: string = '#30383B';
const BORDER: string = '#364044';
const TEXT: string = '#F2F5F3';
const TEXT_MUTED: string = '#9CA9A7';
const TEXT_FAINT: string = '#687477';

function colorWithAlpha(color: string, alpha: number): string {
  const hex: string = color.length === 7 ? color.substring(1) : color;
  const red: number = parseInt(hex.substring(0, 2), 16);
  const green: number = parseInt(hex.substring(2, 4), 16);
  const blue: number = parseInt(hex.substring(4, 6), 16);
  return 'rgba(' + red.toString() + ',' + green.toString() + ',' + blue.toString() + ',' + alpha.toString() + ')';
}

function cloneLayerForView(layer: LayerModel): LayerModel {
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

function toolResource(tool: EditorTool): Resource {
  switch (tool) {
    case EditorTool.MOVE:
      return $rawfile('move.svg');
    case EditorTool.RECT_SELECT:
      return $rawfile('rselect.svg');
    case EditorTool.LASSO:
      return $rawfile('lasso.svg');
    case EditorTool.MAGIC_WAND:
      return $rawfile('mwand.svg');
    case EditorTool.CROP:
      return $rawfile('rcrop.svg');
    case EditorTool.EYEDROPPER:
      return $rawfile('eyedropper.svg');
    case EditorTool.RULER:
      return $rawfile('ruler.svg');
    case EditorTool.SPOT_HEAL:
      return $rawfile('patch.svg');
    case EditorTool.BRUSH:
      return $rawfile('brush.svg');
    case EditorTool.PEN:
      return $rawfile('pencil.svg');
    case EditorTool.PAINT_BUCKET:
      return $rawfile('pbucket.svg');
    case EditorTool.CLONE:
      return $rawfile('clone.svg');
    case EditorTool.ERASER:
      return $rawfile('eraser.svg');
    case EditorTool.GRADIENT:
      return $rawfile('gradient.svg');
    case EditorTool.BLUR:
      return $rawfile('blur.svg');
    case EditorTool.SHARPEN:
      return $rawfile('sharpen.svg');
    case EditorTool.SMUDGE:
      return $rawfile('smudge.svg');
    case EditorTool.SPONGE:
      return $rawfile('sponge.svg');
    case EditorTool.RED_EYE:
      return $rawfile('redeye.svg');
    case EditorTool.DODGE:
      return $rawfile('dodge.svg');
    case EditorTool.BURN:
      return $rawfile('burn.svg');
    case EditorTool.TYPE:
      return $rawfile('htype.svg');
    case EditorTool.PATH_SELECT:
      return $rawfile('pselect.svg');
    case EditorTool.RECT_SHAPE:
      return $rawfile('rect.svg');
    case EditorTool.ELLIPSE_SHAPE:
      return $rawfile('ellipse.svg');
    case EditorTool.HAND:
      return $rawfile('hand.svg');
    case EditorTool.ZOOM:
      return $rawfile('zoom.svg');
    default:
      return $rawfile('move.svg');
  }
}

@Entry
@Component
struct Index {
  private controller: EditorController = new EditorController();
  @State private ready: boolean = false;
  @State private viewportWidth: number = 1280;
  @State private viewportHeight: number = 800;
  @State private activeTool: EditorTool = EditorTool.MOVE;
  @State private sidebarTab: SidebarTab = SidebarTab.PROPERTIES;
  @State private zoom: number = 1;
  @State private panX: number = 0;
  @State private panY: number = 0;
  @State private busy: boolean = false;
  @State private status: string = 'Ready';
  @State private exposure: number = 0;
  @State private contrastValue: number = 0;
  @State private saturation: number = 0;
  @State private temperature: number = 0;
  @State private blurValue: number = 0;
  @State private activeFilterPreset: string = 'none';
  @State private filterIntensity: number = 100;
  @State private documentRotation: number = 0;
  @State private documentFlipHorizontal: boolean = false;
  @State private documentFlipVertical: boolean = false;
  @State private cropDraftRect: CropRect = { x: 0, y: 0, width: 150, height: 105 };
  @State private cropDraftAspect: CropAspect = 'free';
  @State private documentName: string = 'Beach Study';
  @State private documentWidth: number = 150;
  @State private documentHeight: number = 105;
  @State private documentDirty: boolean = false;
  @State private canUndo: boolean = false;
  @State private canRedo: boolean = false;
  @State private sourceCanvasWidth: number = 150;
  @State private sourceCanvasHeight: number = 105;
  @State private artboardScale: number = 1;
  @State private sourceArtboardWidth: number = 150;
  @State private sourceArtboardHeight: number = 105;
  @State private outputArtboardWidth: number = 150;
  @State private outputArtboardHeight: number = 105;
  @State private previewArtboardWidth: number = 150;
  @State private previewArtboardHeight: number = 105;
  @State private documentMatrix: object | undefined = undefined;
  @State private layerVisible: boolean = true;
  @State private layerLocked: boolean = false;
  @State private historyVersion: number = 0;
  @State private documentVersion: number = 0;
  @State private sidebarOpen: boolean = true;
  @State private filterMatrixValue: drawing.ColorFilter | undefined = undefined;
  @State private previewRevision: number = 0;
  @State private layerRows: LayerModel[] = [];
  @State private activeLayerId: string = 'layer-image';
  @State private activeLayerOpacity: number = 100;
  @State private activeLayerBlendMode: string = 'Normal';
  @State private textDraft: string = '';
  @State private textSizeValue: number = 32;
  @State private textColorValue: string = DEFAULT_FOREGROUND_COLOR;
  @State private textXValue: number = 24;
  @State private textYValue: number = 24;
  @State private foregroundColorValue: string = DEFAULT_FOREGROUND_COLOR;
  @State private backgroundColorValue: string = DEFAULT_BACKGROUND_COLOR;
  @State private colorInput: string = DEFAULT_FOREGROUND_COLOR;
  @State private colorTarget: ColorTarget = ColorTarget.FOREGROUND;
  @State private swatchColors: string[] = [];
  @State private selectionActive: boolean = false;
  @State private selectionRect: SelectionRect = { x: 0, y: 0, width: 150, height: 105 };
  @State private selectionDragging: boolean = false;
  @State private selectionDragStartX: number = 0;
  @State private selectionDragStartY: number = 0;
  @State private selectionDragX: number = 0;
  @State private selectionDragY: number = 0;
  @State private lassoPoints: TransformPoint[] = [];
  @State private lassoDragging: boolean = false;
  @State private magicWandTolerance: number = DEFAULT_FILL_TOLERANCE;
  @State private magicWandContiguous: boolean = true;
  @State private magicWandBusy: boolean = false;
  @State private selectionModifyAmount: number = 8;
  @State private shapeDragging: boolean = false;
  @State private shapeDraftRect: SelectionRect = { x: 0, y: 0, width: 1, height: 1 };
  @State private shapeDragStartX: number = 0;
  @State private shapeDragStartY: number = 0;
  @State private shapeDragX: number = 0;
  @State private shapeDragY: number = 0;
  @State private shapeXValue: number = 0;
  @State private shapeYValue: number = 0;
  @State private shapeWidthValue: number = 1;
  @State private shapeHeightValue: number = 1;
  @State private shapeFillValue: string = DEFAULT_FOREGROUND_COLOR;
  @State private shapeStrokeValue: string = DEFAULT_BACKGROUND_COLOR;
  @State private shapeStrokeWidthValue: number = 2;
  @State private brushWidthValue: number = DEFAULT_PAINT_WIDTH;
  @State private retouchStrengthValue: number = DEFAULT_RETOUCH_STRENGTH;
  @State private spongeModeValue: number = 1;
  @State private retouchRangeValue: number = DEFAULT_RETOUCH_RANGE;
  @State private brushDragging: boolean = false;
  @State private brushPoints: TransformPoint[] = [];
  @State private gradientDragging: boolean = false;
  @State private gradientStartPoint: TransformPoint | undefined = undefined;
  @State private gradientEndPoint: TransformPoint | undefined = undefined;
  @State private gradientPrimaryInput: string = DEFAULT_FOREGROUND_COLOR;
  @State private gradientSecondaryInput: string = DEFAULT_BACKGROUND_COLOR;
  @State private gradientReverse: boolean = false;
  @State private fillToleranceValue: number = DEFAULT_FILL_TOLERANCE;
  @State private fillContiguousValue: boolean = true;
  @State private fillAntialiasValue: boolean = true;
  @State private fillSeedPoint: TransformPoint | undefined = undefined;
  @State private cloneSourcePoint: TransformPoint | undefined = undefined;
  @State private cloneTargetPoints: TransformPoint[] = [];
  @State private cloneDragging: boolean = false;
  @State private moveDragging: boolean = false;
  @State private moveStartX: number = 0;
  @State private moveStartY: number = 0;
  @State private moveCurrentX: number = 0;
  @State private moveCurrentY: number = 0;
  @State private previewPixelMap: image.PixelMap | undefined = undefined;
  private previewRequestToken: number = 0;

  aboutToAppear(): void {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.controller.attachContext(context);
    this.syncState();
  }

  private isCompact(): boolean {
    return this.viewportWidth < COMPACT_BREAKPOINT;
  }

  private isNarrow(): boolean {
    return this.viewportWidth < MOBILE_BREAKPOINT;
  }

  private syncState(): void {
    const store = this.controller.store;
    this.activeTool = store.activeTool;
    this.sidebarTab = store.sidebarTab;
    this.zoom = store.zoom;
    this.panX = store.panX;
    this.panY = store.panY;
    this.busy = store.isBusy;
    this.status = store.statusMessage.length > 0 ? store.statusMessage : 'Ready';
    this.exposure = store.document.adjustments.exposure;
    this.contrastValue = store.document.adjustments.contrast;
    this.saturation = store.document.adjustments.saturation;
    this.temperature = store.document.adjustments.temperature;
    this.blurValue = store.document.adjustments.blur;
    this.activeFilterPreset = store.document.filter.preset;
    this.filterIntensity = store.document.filter.intensity;
    this.documentName = store.document.name;
    this.documentWidth = store.document.width;
    this.documentHeight = store.document.height;
    this.documentDirty = store.document.dirty;
    this.canUndo = store.canUndo;
    this.canRedo = store.canRedo;
    this.documentRotation = store.document.transform.rotation;
    this.documentFlipHorizontal = store.document.transform.flipHorizontal;
    this.documentFlipVertical = store.document.transform.flipVertical;
    this.cropDraftRect = {
      x: store.document.crop.rect.x,
      y: store.document.crop.rect.y,
      width: store.document.crop.rect.width,
      height: store.document.crop.rect.height
    };
    this.cropDraftAspect = cropAspectForRect(this.cropDraftRect);
    this.sourceCanvasWidth = store.document.sourceWidth;
    this.sourceCanvasHeight = store.document.sourceHeight;
    this.layerRows = store.document.layers.map((layer: LayerModel) => cloneLayerForView(layer));
    this.activeLayerId = store.selectedLayerId;
    this.activeLayerOpacity = store.selectedLayer?.opacity ?? 100;
    this.activeLayerBlendMode = store.selectedLayer?.blendMode ?? 'Normal';
    const selectedText: LayerModel | undefined = store.selectedLayer?.kind === 'text' ?
      store.selectedLayer : undefined;
    this.textDraft = selectedText?.textContent ?? '';
    this.textSizeValue = selectedText?.textSize ?? 32;
    this.textColorValue = selectedText?.textColor ?? DEFAULT_FOREGROUND_COLOR;
    this.textXValue = selectedText?.textX ?? 24;
    this.textYValue = selectedText?.textY ?? 24;
    this.foregroundColorValue = store.colors.foreground;
    this.backgroundColorValue = store.colors.background;
    const selectedShape: LayerModel | undefined = store.selectedLayer?.kind === 'shape' ?
      store.selectedLayer : undefined;
    this.shapeXValue = selectedShape?.shapeX ?? 0;
    this.shapeYValue = selectedShape?.shapeY ?? 0;
    this.shapeWidthValue = selectedShape?.shapeWidth ?? 1;
    this.shapeHeightValue = selectedShape?.shapeHeight ?? 1;
    this.shapeFillValue = selectedShape?.shapeFill ?? this.foregroundColorValue;
    this.shapeStrokeValue = selectedShape?.shapeStroke ?? this.backgroundColorValue;
    this.shapeStrokeWidthValue = selectedShape?.shapeStrokeWidth ?? 2;
    const selectedPaint: LayerModel | undefined = store.selectedLayer?.kind === 'paint' ?
      store.selectedLayer : undefined;
    this.brushWidthValue = selectedPaint?.paintWidth ?? DEFAULT_PAINT_WIDTH;
    this.retouchStrengthValue = selectedPaint !== undefined &&
      (selectedPaint.paintMode === PaintMode.BLUR ||
        selectedPaint.paintMode === PaintMode.SHARPEN ||
        selectedPaint.paintMode === PaintMode.SMUDGE ||
        selectedPaint.paintMode === PaintMode.SPONGE ||
        selectedPaint.paintMode === PaintMode.DODGE ||
        selectedPaint.paintMode === PaintMode.BURN ||
        selectedPaint.paintMode === PaintMode.RED_EYE ||
        selectedPaint.paintMode === PaintMode.SPOT_HEAL) ?
      selectedPaint.paintRetouchStrength : DEFAULT_RETOUCH_STRENGTH;
    this.spongeModeValue = selectedPaint?.paintMode === PaintMode.SPONGE ?
      selectedPaint.paintSpongeMode : 1;
    this.retouchRangeValue = selectedPaint?.paintMode === PaintMode.DODGE ||
      selectedPaint?.paintMode === PaintMode.BURN ? selectedPaint.paintRetouchRange :
      DEFAULT_RETOUCH_RANGE;
    this.gradientPrimaryInput = selectedPaint?.paintMode === PaintMode.GRADIENT ?
      selectedPaint.paintColor : store.colors.foreground;
    this.gradientSecondaryInput = selectedPaint?.paintMode === PaintMode.GRADIENT ?
      selectedPaint.paintSecondaryColor : store.colors.background;
    this.gradientReverse = selectedPaint?.paintMode === PaintMode.GRADIENT ?
      selectedPaint.paintGradientReverse : false;
    this.fillToleranceValue = selectedPaint?.paintMode === PaintMode.FILL ?
      selectedPaint.paintFillTolerance : DEFAULT_FILL_TOLERANCE;
    this.fillContiguousValue = selectedPaint?.paintMode === PaintMode.FILL ?
      selectedPaint.paintFillContiguous : true;
    this.fillAntialiasValue = selectedPaint?.paintMode === PaintMode.FILL ?
      selectedPaint.paintFillAntialias : true;
    let selectedCloneSource: TransformPoint | undefined = undefined;
    let selectedCloneTargets: TransformPoint[] = [];
    if (selectedPaint?.paintMode === PaintMode.CLONE) {
      selectedCloneSource = {
        x: selectedPaint.paintCloneSource.x,
        y: selectedPaint.paintCloneSource.y
      };
      for (const point of selectedPaint.paintPoints) {
        const copy: TransformPoint = { x: point.x, y: point.y };
        selectedCloneTargets.push(copy);
      }
    }
    this.cloneSourcePoint = selectedCloneSource;
    this.cloneTargetPoints = selectedCloneTargets;
    this.swatchColors = store.colors.swatches.map((color: string) => color);
    this.selectionActive = store.document.selection.active;
    this.selectionRect = store.getSelectionRect();
    const selectionPoints: TransformPoint[] = [];
    for (const point of store.document.selection.points) {
      const copy: TransformPoint = { x: point.x, y: point.y };
      selectionPoints.push(copy);
    }
    this.lassoPoints = selectionPoints;
    if (!this.selectionDragging) {
      this.selectionDragStartX = this.selectionRect.x;
      this.selectionDragStartY = this.selectionRect.y;
      this.selectionDragX = this.selectionRect.x + this.selectionRect.width;
      this.selectionDragY = this.selectionRect.y + this.selectionRect.height;
    }
    this.historyVersion += 1;
    this.documentVersion += 1;
    this.updatePreviewGeometry();
    const matrix: number[] = documentFilterMatrix(store.document.adjustments,
      store.document.filter.preset, store.document.filter.intensity);
    try {
      this.filterMatrixValue = drawing.ColorFilter.createMatrixColorFilter(matrix);
    } catch (error) {
      this.filterMatrixValue = undefined;
    }
    this.refreshPreviewPixelMap(this.hasRenderedPaintLayer());
  }

  private hasRenderedPaintLayer(): boolean {
    for (const layer of this.layerRows) {
      if (layer.kind === 'paint' && layer.visible &&
        (layer.paintMode === PaintMode.ERASER || layer.paintMode === PaintMode.GRADIENT ||
          layer.paintMode === PaintMode.FILL || layer.paintMode === PaintMode.CLONE ||
          layer.paintMode === PaintMode.BLUR || layer.paintMode === PaintMode.SHARPEN ||
          layer.paintMode === PaintMode.SMUDGE || layer.paintMode === PaintMode.SPONGE ||
          layer.paintMode === PaintMode.DODGE || layer.paintMode === PaintMode.BURN ||
          layer.paintMode === PaintMode.PENCIL || layer.paintMode === PaintMode.RED_EYE ||
          layer.paintMode === PaintMode.SPOT_HEAL)) {
        return true;
      }
    }
    return false;
  }

  private async refreshPreviewPixelMap(enabled: boolean): Promise<void> {
    const requestToken: number = ++this.previewRequestToken;
    if (!enabled) {
      const oldPreview: image.PixelMap | undefined = this.previewPixelMap;
      this.previewPixelMap = undefined;
      if (oldPreview !== undefined) {
        this.previewRevision += 1;
        try {
          await oldPreview.release();
        } catch (error) {
        }
      }
      return;
    }
    try {
      const nextPreview: image.PixelMap | undefined = await this.controller.createPreviewPixelMap();
      if (requestToken !== this.previewRequestToken) {
        if (nextPreview !== undefined) {
          await nextPreview.release();
        }
        return;
      }
      const oldPreview: image.PixelMap | undefined = this.previewPixelMap;
      this.previewPixelMap = nextPreview;
      this.previewRevision += 1;
      if (oldPreview !== undefined) {
        try {
          await oldPreview.release();
        } catch (error) {
        }
      }
    } catch (error) {
      this.status = 'Eraser preview unavailable';
    }
  }

  private selectTool(tool: EditorTool): void {
    this.controller.selectTool(tool);
    if (tool === EditorTool.CROP && this.controller.store.sidebarTab !== SidebarTab.PROPERTIES) {
      this.controller.store.setSidebarTab(SidebarTab.PROPERTIES);
    }
    if ((tool === EditorTool.BRUSH || tool === EditorTool.ERASER || tool === EditorTool.GRADIENT ||
      tool === EditorTool.PAINT_BUCKET || tool === EditorTool.CLONE || tool === EditorTool.BLUR ||
      tool === EditorTool.SHARPEN || tool === EditorTool.SMUDGE || tool === EditorTool.SPONGE ||
      tool === EditorTool.DODGE || tool === EditorTool.BURN || tool === EditorTool.PEN ||
      tool === EditorTool.RED_EYE || tool === EditorTool.SPOT_HEAL || tool === EditorTool.LASSO) &&
      this.controller.store.sidebarTab !== SidebarTab.PROPERTIES) {
      this.controller.store.setSidebarTab(SidebarTab.PROPERTIES);
    }
    if (tool === EditorTool.TYPE && this.controller.store.selectedLayer?.kind !== 'text') {
      this.controller.store.addTextLayer('New text');
    }
    this.syncState();
  }

  private isShapeTool(): boolean {
    return this.activeTool === EditorTool.RECT_SHAPE || this.activeTool === EditorTool.ELLIPSE_SHAPE;
  }

  private isSelectionTool(): boolean {
    return this.activeTool === EditorTool.RECT_SELECT;
  }

  private isLassoTool(): boolean {
    return this.activeTool === EditorTool.LASSO;
  }

  private isMagicWandTool(): boolean {
    return this.activeTool === EditorTool.MAGIC_WAND;
  }

  private isMoveTool(): boolean {
    return this.activeTool === EditorTool.MOVE;
  }

  private isBrushTool(): boolean {
    return this.activeTool === EditorTool.BRUSH;
  }

  private isPencilTool(): boolean {
    return this.activeTool === EditorTool.PEN;
  }

  private isEraserTool(): boolean {
    return this.activeTool === EditorTool.ERASER;
  }

  private isGradientTool(): boolean {
    return this.activeTool === EditorTool.GRADIENT;
  }

  private isFillTool(): boolean {
    return this.activeTool === EditorTool.PAINT_BUCKET;
  }

  private isCloneTool(): boolean {
    return this.activeTool === EditorTool.CLONE;
  }

  private isBlurTool(): boolean {
    return this.activeTool === EditorTool.BLUR;
  }

  private isSharpenTool(): boolean {
    return this.activeTool === EditorTool.SHARPEN;
  }

  private isSmudgeTool(): boolean {
    return this.activeTool === EditorTool.SMUDGE;
  }

  private isSpongeTool(): boolean {
    return this.activeTool === EditorTool.SPONGE;
  }

  private isRedEyeTool(): boolean {
    return this.activeTool === EditorTool.RED_EYE;
  }

  private isSpotHealTool(): boolean {
    return this.activeTool === EditorTool.SPOT_HEAL;
  }

  private isDodgeTool(): boolean {
    return this.activeTool === EditorTool.DODGE;
  }

  private isBurnTool(): boolean {
    return this.activeTool === EditorTool.BURN;
  }

  private isDodgeBurnTool(): boolean {
    return this.isDodgeTool() || this.isBurnTool();
  }

  private isPaintTool(): boolean {
    return this.isBrushTool() || this.isPencilTool() || this.isEraserTool() || this.isGradientTool() ||
      this.isFillTool() || this.isCloneTool() || this.isBlurTool() || this.isSharpenTool() ||
      this.isSmudgeTool() || this.isSpongeTool() || this.isDodgeBurnTool() ||
      this.isRedEyeTool() || this.isSpotHealTool();
  }

  private activePaintMode(): PaintMode {
    if (this.isPencilTool()) {
      return PaintMode.PENCIL;
    }
    if (this.isEraserTool()) {
      return PaintMode.ERASER;
    }
    if (this.isFillTool()) {
      return PaintMode.FILL;
    }
    if (this.isCloneTool()) {
      return PaintMode.CLONE;
    }
    if (this.isBlurTool()) {
      return PaintMode.BLUR;
    }
    if (this.isSharpenTool()) {
      return PaintMode.SHARPEN;
    }
    if (this.isSmudgeTool()) {
      return PaintMode.SMUDGE;
    }
    if (this.isSpongeTool()) {
      return PaintMode.SPONGE;
    }
    if (this.isRedEyeTool()) {
      return PaintMode.RED_EYE;
    }
    if (this.isSpotHealTool()) {
      return PaintMode.SPOT_HEAL;
    }
    if (this.isDodgeTool()) {
      return PaintMode.DODGE;
    }
    if (this.isBurnTool()) {
      return PaintMode.BURN;
    }
    return this.isGradientTool() ? PaintMode.GRADIENT : PaintMode.BRUSH;
  }

  private shapeToolType(): ShapeType {
    return this.activeTool === EditorTool.ELLIPSE_SHAPE ? ShapeType.ELLIPSE : ShapeType.RECTANGLE;
  }

  private selectTab(tab: SidebarTab): void {
    this.controller.selectTab(tab);
    this.syncState();
  }

  private updateAdjustment(key: string, value: number): void {
    this.controller.store.updateAdjustment(key, value);
    this.syncState();
  }

  private applyFilterPreset(preset: string): void {
    this.controller.store.setFilterPreset(preset);
    this.syncState();
  }

  private updateFilterIntensity(value: number): void {
    this.controller.store.setFilterIntensity(value);
    this.syncState();
  }

  private resetFilter(): void {
    this.controller.store.resetFilter();
    this.syncState();
  }

  private rotateDocument(): void {
    this.controller.store.rotateClockwise();
    this.syncState();
  }

  private flipDocumentHorizontal(): void {
    this.controller.store.flipHorizontal();
    this.syncState();
  }

  private flipDocumentVertical(): void {
    this.controller.store.flipVertical();
    this.syncState();
  }

  private resetDocumentTransform(): void {
    this.controller.store.resetTransform();
    this.syncState();
  }

  private selectionPreviewWidth(): number {
    return Math.max(1, this.selectionToPreviewX(this.selectionRect.x + this.selectionRect.width) -
      this.selectionToPreviewX(this.selectionRect.x));
  }

  private selectionPreviewHeight(): number {
    return Math.max(1, this.selectionToPreviewY(this.selectionRect.y + this.selectionRect.height) -
      this.selectionToPreviewY(this.selectionRect.y));
  }

  private setCropAspect(aspect: CropAspect): void {
    this.cropDraftAspect = aspect;
    this.cropDraftRect = normalizeCropRect(
      centeredCropRect(this.sourceCanvasWidth, this.sourceCanvasHeight, aspect),
      this.sourceCanvasWidth,
      this.sourceCanvasHeight
    );
    this.updatePreviewGeometry();
  }

  private updateCropDraft(x: number, y: number, width: number, height: number): void {
    this.cropDraftRect = normalizeCropRect({ x: x, y: y, width: width, height: height },
      this.sourceCanvasWidth, this.sourceCanvasHeight);
    this.cropDraftAspect = cropAspectForRect(this.cropDraftRect);
    this.updatePreviewGeometry();
  }

  private applyCropDraft(): void {
    this.controller.store.applyCrop(this.cropDraftRect);
    this.syncState();
  }

  private resetCropDraft(): void {
    this.cropDraftRect = fullCropRect(this.sourceCanvasWidth, this.sourceCanvasHeight);
    this.cropDraftAspect = 'free';
    this.controller.store.resetCrop();
    this.syncState();
  }

  private selectionToPreviewX(value: number): number {
    const safeDocumentWidth: number = Math.max(1, this.documentWidth);
    return Math.max(0, Math.min(this.outputArtboardWidth, value * this.outputArtboardWidth / safeDocumentWidth));
  }

  private selectionToPreviewY(value: number): number {
    const safeDocumentHeight: number = Math.max(1, this.documentHeight);
    return Math.max(0, Math.min(this.outputArtboardHeight,
      value * this.outputArtboardHeight / safeDocumentHeight));
  }

  private previewToSelectionX(value: number): number {
    const safeOutputWidth: number = Math.max(1, this.outputArtboardWidth);
    return Math.max(0, Math.min(this.documentWidth, value * this.documentWidth / safeOutputWidth));
  }

  private previewToSelectionY(value: number): number {
    const safeOutputHeight: number = Math.max(1, this.outputArtboardHeight);
    return Math.max(0, Math.min(this.documentHeight, value * this.documentHeight / safeOutputHeight));
  }

  private selectionDragRect(): SelectionRect {
    const left: number = Math.min(this.selectionDragStartX, this.selectionDragX);
    const top: number = Math.min(this.selectionDragStartY, this.selectionDragY);
    const right: number = Math.max(this.selectionDragStartX, this.selectionDragX);
    const bottom: number = Math.max(this.selectionDragStartY, this.selectionDragY);
    return {
      x: left,
      y: top,
      width: Math.max(1, right - left),
      height: Math.max(1, bottom - top)
    };
  }

  private lassoPreviewPoints(points: TransformPoint[]): number[][] {
    const result: number[][] = [];
    for (const point of points) {
      result.push([
        this.selectionToPreviewX(point.x),
        this.selectionToPreviewY(point.y)
      ]);
    }
    if (result.length > 2) {
      result.push(result[0]);
    }
    return result;
  }

  private shapeDragRect(): SelectionRect {
    const left: number = Math.min(this.shapeDragStartX, this.shapeDragX);
    const top: number = Math.min(this.shapeDragStartY, this.shapeDragY);
    const right: number = Math.max(this.shapeDragStartX, this.shapeDragX);
    const bottom: number = Math.max(this.shapeDragStartY, this.shapeDragY);
    return {
      x: left,
      y: top,
      width: Math.max(1, right - left),
      height: Math.max(1, bottom - top)
    };
  }

  private outputToSourcePoint(localX: number, localY: number): TransformPoint {
    const outputX: number = this.previewToSelectionX(localX);
    const outputY: number = this.previewToSelectionY(localY);
    const crop: CropRect = this.controller.store.getCropRect();
    const sourcePoint: TransformPoint = inverseTransformPoint(outputX, outputY,
      crop.width, crop.height, this.controller.store.document.transform);
    return {
      x: Math.max(0, Math.min(this.sourceCanvasWidth - 1, crop.x + sourcePoint.x)),
      y: Math.max(0, Math.min(this.sourceCanvasHeight - 1, crop.y + sourcePoint.y))
    };
  }

  private moveOverlayRect(): SelectionRect {
    const layer: LayerModel | undefined = this.activeShapeLayer() ??
      (this.controller.store.selectedLayer?.kind === 'text' ?
        this.controller.store.selectedLayer : undefined);
    if (layer === undefined) {
      return { x: this.moveStartX, y: this.moveStartY, width: 1, height: 1 };
    }
    const baseX: number = layer.kind === 'shape' ? layer.shapeX : layer.textX;
    const baseY: number = layer.kind === 'shape' ? layer.shapeY : layer.textY;
    const width: number = layer.kind === 'shape' ? layer.shapeWidth : 24;
    const height: number = layer.kind === 'shape' ? layer.shapeHeight : 24;
    return {
      x: baseX + this.moveCurrentX - this.moveStartX,
      y: baseY + this.moveCurrentY - this.moveStartY,
      width: width,
      height: height
    };
  }

  private sourceRectToPreviewRect(rect: SelectionRect): SelectionRect {
    const transform = this.controller.store.document.transform;
    const crop: CropRect = this.controller.store.getCropRect();
    const origin: TransformPoint = transformPoint(crop.x, crop.y, this.sourceCanvasWidth,
      this.sourceCanvasHeight, transform);
    const topLeft: TransformPoint = transformPoint(rect.x, rect.y, this.sourceCanvasWidth,
      this.sourceCanvasHeight, transform);
    const bottomRight: TransformPoint = transformPoint(rect.x + rect.width, rect.y + rect.height,
      this.sourceCanvasWidth, this.sourceCanvasHeight, transform);
    const left: number = Math.min(topLeft.x, bottomRight.x) - origin.x;
    const top: number = Math.min(topLeft.y, bottomRight.y) - origin.y;
    const right: number = Math.max(topLeft.x, bottomRight.x) - origin.x;
    const bottom: number = Math.max(topLeft.y, bottomRight.y) - origin.y;
    return {
      x: left * this.artboardScale,
      y: top * this.artboardScale,
      width: Math.max(1, (right - left) * this.artboardScale),
      height: Math.max(1, (bottom - top) * this.artboardScale)
    };
  }

  private isMovingShape(): boolean {
    return this.controller.store.selectedLayer?.kind === 'shape';
  }

  private isMovingEllipse(): boolean {
    return this.isMovingShape() && this.controller.store.selectedLayer?.shapeType === ShapeType.ELLIPSE;
  }

  private isMovingText(): boolean {
    return this.controller.store.selectedLayer?.kind === 'text';
  }

  private movePreviewRect(): SelectionRect {
    return this.sourceRectToPreviewRect(this.moveOverlayRect());
  }

  private beginSelectionDrag(event: GestureEvent): void {
    if ((!this.isSelectionTool() && !this.isLassoTool() && !this.isShapeTool() &&
      !this.isMoveTool()) || event.fingerList.length === 0) {
      return;
    }
    const finger = event.fingerList[0];
    if (this.isMoveTool()) {
      const start: TransformPoint = this.outputToSourcePoint(finger.localX, finger.localY);
      this.moveStartX = start.x;
      this.moveStartY = start.y;
      this.moveCurrentX = start.x;
      this.moveCurrentY = start.y;
      this.moveDragging = true;
    } else if (this.isLassoTool()) {
      const start: TransformPoint = {
        x: this.previewToSelectionX(finger.localX),
        y: this.previewToSelectionY(finger.localY)
      };
      this.lassoPoints = [start];
      this.lassoDragging = true;
    } else if (this.isSelectionTool()) {
      const startX: number = this.previewToSelectionX(finger.localX);
      const startY: number = this.previewToSelectionY(finger.localY);
      this.selectionDragStartX = startX;
      this.selectionDragStartY = startY;
      this.selectionDragX = startX;
      this.selectionDragY = startY;
      this.selectionDragging = true;
      this.selectionRect = {
        x: startX,
        y: startY,
        width: 1,
        height: 1
      };
    } else {
      const start: TransformPoint = this.outputToSourcePoint(finger.localX, finger.localY);
      this.shapeDragStartX = start.x;
      this.shapeDragStartY = start.y;
      this.shapeDragX = start.x;
      this.shapeDragY = start.y;
      this.shapeDragging = true;
      this.shapeDraftRect = {
        x: start.x,
        y: start.y,
        width: 1,
        height: 1
      };
    }
  }

  private updateSelectionDrag(event: GestureEvent): void {
    if ((!this.selectionDragging && !this.lassoDragging && !this.shapeDragging &&
      !this.moveDragging) || event.fingerList.length === 0) {
      return;
    }
    const finger = event.fingerList[0];
    if (this.lassoDragging) {
      const point: TransformPoint = {
        x: this.previewToSelectionX(finger.localX),
        y: this.previewToSelectionY(finger.localY)
      };
      const points: TransformPoint[] = this.lassoPoints.slice();
      points.push(point);
      this.lassoPoints = points;
    } else if (this.moveDragging) {
      const end: TransformPoint = this.outputToSourcePoint(finger.localX, finger.localY);
      this.moveCurrentX = end.x;
      this.moveCurrentY = end.y;
    } else if (this.selectionDragging) {
      this.selectionDragX = this.previewToSelectionX(finger.localX);
      this.selectionDragY = this.previewToSelectionY(finger.localY);
      this.selectionRect = this.selectionDragRect();
    } else {
      const end: TransformPoint = this.outputToSourcePoint(finger.localX, finger.localY);
      this.shapeDragX = end.x;
      this.shapeDragY = end.y;
      this.shapeDraftRect = this.shapeDragRect();
    }
  }

  private finishSelectionDrag(): void {
    if (this.lassoDragging) {
      const points: TransformPoint[] = this.lassoPoints.slice();
      this.lassoDragging = false;
      this.lassoPoints = [];
      if (points.length >= 3 && this.controller.store.setLassoSelection(points)) {
        this.syncState();
      }
      return;
    }
    if (this.moveDragging) {
      const layer: LayerModel | undefined = this.activeShapeLayer() ??
        (this.controller.store.selectedLayer?.kind === 'text' ?
          this.controller.store.selectedLayer : undefined);
      const dx: number = this.moveCurrentX - this.moveStartX;
      const dy: number = this.moveCurrentY - this.moveStartY;
      this.moveDragging = false;
      if (layer !== undefined) {
        this.controller.store.moveLayerByDelta(layer.id, dx, dy);
        this.syncState();
      }
      return;
    }
    if (this.selectionDragging) {
      const next: SelectionRect = this.selectionDragRect();
      this.selectionDragging = false;
      this.controller.store.setSelection(next);
      this.syncState();
      return;
    }
    if (!this.shapeDragging) {
      return;
    }
    const next: SelectionRect = this.shapeDragRect();
    this.shapeDragging = false;
    this.controller.store.addShapeLayer(this.shapeToolType(), next);
    this.syncState();
  }

  private cancelSelectionDrag(): void {
    this.selectionDragging = false;
    this.lassoDragging = false;
    this.shapeDragging = false;
    this.moveDragging = false;
    this.selectionRect = this.controller.store.getSelectionRect();
    const selectionPoints: TransformPoint[] = [];
    for (const point of this.controller.store.document.selection.points) {
      const copy: TransformPoint = { x: point.x, y: point.y };
      selectionPoints.push(copy);
    }
    this.lassoPoints = selectionPoints;
  }

  private selectAll(): void {
    this.controller.store.selectAll();
    this.syncState();
  }

  private deselect(): void {
    this.controller.store.deselect();
    this.syncState();
  }

  private cropToSelection(): void {
    this.controller.store.cropToSelection();
    this.syncState();
  }

  private expandSelection(): void {
    this.controller.store.expandSelection(this.selectionModifyAmount);
    this.syncState();
  }

  private contractSelection(): void {
    this.controller.store.contractSelection(this.selectionModifyAmount);
    this.syncState();
  }

  private activeShapeLayer(): LayerModel | undefined {
    const selected: LayerModel | undefined = this.controller.store.selectedLayer;
    return selected !== undefined && selected.kind === 'shape' ? selected : undefined;
  }

  private activePaintLayer(): LayerModel | undefined {
    const selected: LayerModel | undefined = this.controller.store.selectedLayer;
    return selected !== undefined && selected.kind === 'paint' ? selected : undefined;
  }

  private isEraserLayer(layer: LayerModel): boolean {
    return layer.paintMode === PaintMode.ERASER;
  }

  private activeGradientLayer(): LayerModel | undefined {
    const selected: LayerModel | undefined = this.controller.store.selectedLayer;
    return selected !== undefined && selected.kind === 'paint' &&
      selected.paintMode === PaintMode.GRADIENT ? selected : undefined;
  }

  private activeFillLayer(): LayerModel | undefined {
    const selected: LayerModel | undefined = this.controller.store.selectedLayer;
    return selected !== undefined && selected.kind === 'paint' &&
      selected.paintMode === PaintMode.FILL ? selected : undefined;
  }

  private activeCloneLayer(): LayerModel | undefined {
    const selected: LayerModel | undefined = this.controller.store.selectedLayer;
    return selected !== undefined && selected.kind === 'paint' &&
      selected.paintMode === PaintMode.CLONE ? selected : undefined;
  }

  private activeBlurLayer(): LayerModel | undefined {
    const selected: LayerModel | undefined = this.controller.store.selectedLayer;
    return selected !== undefined && selected.kind === 'paint' &&
      selected.paintMode === PaintMode.BLUR ? selected : undefined;
  }

  private activeSharpenLayer(): LayerModel | undefined {
    const selected: LayerModel | undefined = this.controller.store.selectedLayer;
    return selected !== undefined && selected.kind === 'paint' &&
      selected.paintMode === PaintMode.SHARPEN ? selected : undefined;
  }

  private activeSmudgeLayer(): LayerModel | undefined {
    const selected: LayerModel | undefined = this.controller.store.selectedLayer;
    return selected !== undefined && selected.kind === 'paint' &&
      selected.paintMode === PaintMode.SMUDGE ? selected : undefined;
  }

  private activeSpongeLayer(): LayerModel | undefined {
    const selected: LayerModel | undefined = this.controller.store.selectedLayer;
    return selected !== undefined && selected.kind === 'paint' &&
      selected.paintMode === PaintMode.SPONGE ? selected : undefined;
  }

  private activeRedEyeLayer(): LayerModel | undefined {
    const selected: LayerModel | undefined = this.controller.store.selectedLayer;
    return selected !== undefined && selected.kind === 'paint' &&
      selected.paintMode === PaintMode.RED_EYE ? selected : undefined;
  }

  private activeSpotHealLayer(): LayerModel | undefined {
    const selected: LayerModel | undefined = this.controller.store.selectedLayer;
    return selected !== undefined && selected.kind === 'paint' &&
      selected.paintMode === PaintMode.SPOT_HEAL ? selected : undefined;
  }

  private activeDodgeBurnLayer(): LayerModel | undefined {
    const selected: LayerModel | undefined = this.controller.store.selectedLayer;
    return selected !== undefined && selected.kind === 'paint' &&
      (selected.paintMode === PaintMode.DODGE || selected.paintMode === PaintMode.BURN) ?
      selected : undefined;
  }

  private activeDodgeBurnMode(): PaintMode {
    const layer: LayerModel | undefined = this.activeDodgeBurnLayer();
    if (layer !== undefined) {
      return layer.paintMode;
    }
    return this.isDodgeTool() ? PaintMode.DODGE : PaintMode.BURN;
  }

  private paintSourcePreviewPoints(points: TransformPoint[]): number[][] {
    const result: number[][] = [];
    for (const point of points) {
      const pair: number[] = [
        point.x * this.artboardScale,
        point.y * this.artboardScale
      ];
      result.push(pair);
    }
    return result;
  }

  private paintSourcePreviewPoint(point: TransformPoint): TransformPoint {
    return {
      x: point.x * this.artboardScale,
      y: point.y * this.artboardScale
    };
  }

  private paintSourcePointForLayer(layer: LayerModel): TransformPoint {
    return this.paintSourcePreviewPoint(layer.paintPoints[0]);
  }

  private paintDraftPreviewPoints(points: TransformPoint[]): number[][] {
    const result: number[][] = [];
    const crop: CropRect = this.controller.store.getCropRect();
    for (const point of points) {
      const previewPoint: TransformPoint = sourcePointToCropSpace(point, crop,
        this.sourceCanvasWidth, this.sourceCanvasHeight, this.controller.store.document.transform);
      result.push([
        previewPoint.x * this.artboardScale,
        previewPoint.y * this.artboardScale
      ]);
    }
    return result;
  }

  private paintDraftPreviewPoint(point: TransformPoint): TransformPoint {
    const crop: CropRect = this.controller.store.getCropRect();
    const previewPoint: TransformPoint = sourcePointToCropSpace(point, crop,
      this.sourceCanvasWidth, this.sourceCanvasHeight, this.controller.store.document.transform);
    return {
      x: previewPoint.x * this.artboardScale,
      y: previewPoint.y * this.artboardScale
    };
  }

  private beginBrushTouch(event: TouchEvent): void {
    if (!this.isPaintTool() || event.changedTouches.length === 0) {
      return;
    }
    const touch = event.changedTouches[0];
    const start: TransformPoint = this.outputToSourcePoint(touch.x, touch.y);
    const points: TransformPoint[] = [start];
    this.brushPoints = points;
    this.brushDragging = true;
  }

  private updateBrushTouch(event: TouchEvent): void {
    if (!this.brushDragging || event.changedTouches.length === 0) {
      return;
    }
    const touch = event.changedTouches[0];
    const next: TransformPoint = this.outputToSourcePoint(touch.x, touch.y);
    const previous: TransformPoint | undefined = this.brushPoints.length > 0 ?
      this.brushPoints[this.brushPoints.length - 1] : undefined;
    if (previous !== undefined && Math.abs(previous.x - next.x) < 1 &&
      Math.abs(previous.y - next.y) < 1) {
      return;
    }
    const points: TransformPoint[] = this.brushPoints.slice();
    points.push(next);
    this.brushPoints = points;
  }

  private finishBrushTouch(event: TouchEvent): void {
    if (!this.brushDragging) {
      return;
    }
    if (event.type === TouchType.Move || event.type === TouchType.Up) {
      this.updateBrushTouch(event);
    }
    const points: TransformPoint[] = this.brushPoints.slice();
    this.brushDragging = false;
    this.brushPoints = [];
    if (points.length > 0) {
      if (this.isBlurTool()) {
        this.controller.store.addBlurLayer(points, this.brushWidthValue, this.retouchStrengthValue);
      } else if (this.isSharpenTool()) {
        this.controller.store.addSharpenLayer(points, this.brushWidthValue, this.retouchStrengthValue);
      } else if (this.isSmudgeTool()) {
        this.controller.store.addSmudgeLayer(points, this.brushWidthValue, this.retouchStrengthValue);
      } else if (this.isSpongeTool()) {
        this.controller.store.addSpongeLayer(points, this.brushWidthValue,
          this.retouchStrengthValue, this.spongeModeValue);
      } else if (this.isRedEyeTool()) {
        this.controller.store.addRedEyeLayer(points, this.brushWidthValue, this.retouchStrengthValue);
      } else if (this.isSpotHealTool()) {
        this.controller.store.addSpotHealLayer(points, this.brushWidthValue, this.retouchStrengthValue);
      } else if (this.isDodgeTool()) {
        this.controller.store.addDodgeLayer(points, this.brushWidthValue,
          this.retouchStrengthValue, this.retouchRangeValue);
      } else if (this.isBurnTool()) {
        this.controller.store.addBurnLayer(points, this.brushWidthValue,
          this.retouchStrengthValue, this.retouchRangeValue);
      } else {
        this.controller.store.addPaintLayer(points, this.foregroundColorValue, this.brushWidthValue,
          this.activePaintMode());
      }
      this.syncState();
    }
  }

  private cancelBrushTouch(): void {
    this.brushDragging = false;
    this.brushPoints = [];
  }

  private beginGradientTouch(event: TouchEvent): void {
    if (!this.isGradientTool() || event.changedTouches.length === 0) {
      return;
    }
    const touch = event.changedTouches[0];
    const start: TransformPoint = this.outputToSourcePoint(touch.x, touch.y);
    this.gradientStartPoint = start;
    this.gradientEndPoint = start;
    this.gradientDragging = true;
  }

  private updateGradientTouch(event: TouchEvent): void {
    if (!this.gradientDragging || event.changedTouches.length === 0) {
      return;
    }
    const touch = event.changedTouches[0];
    this.gradientEndPoint = this.outputToSourcePoint(touch.x, touch.y);
  }

  private finishGradientTouch(event: TouchEvent): void {
    if (!this.gradientDragging) {
      return;
    }
    if (event.type === TouchType.Move || event.type === TouchType.Up) {
      this.updateGradientTouch(event);
    }
    const start: TransformPoint | undefined = this.gradientStartPoint;
    const end: TransformPoint | undefined = this.gradientEndPoint;
    this.gradientDragging = false;
    this.gradientStartPoint = undefined;
    this.gradientEndPoint = undefined;
    if (start !== undefined && end !== undefined &&
      (Math.abs(start.x - end.x) > 2 || Math.abs(start.y - end.y) > 2)) {
      this.controller.store.addGradientLayer(start, end, this.gradientPrimaryInput,
        this.gradientSecondaryInput, this.gradientReverse);
    }
    this.syncState();
  }

  private cancelGradientTouch(): void {
    this.gradientDragging = false;
    this.gradientStartPoint = undefined;
    this.gradientEndPoint = undefined;
  }

  private applyBrushWidth(value: number): void {
    const paint: LayerModel | undefined = this.activePaintLayer();
    this.brushWidthValue = Math.max(1, Math.min(96, Math.round(value)));
    if (paint !== undefined) {
      this.controller.store.setPaintWidth(paint.id, this.brushWidthValue);
      this.syncState();
    }
  }

  private applyRetouchStrength(value: number): void {
    const minimum: number = this.isDodgeBurnTool() || this.activeDodgeBurnLayer() !== undefined ? 0 : 1;
    this.retouchStrengthValue = Math.max(minimum, Math.min(100, Math.round(value)));
    const retouch: LayerModel | undefined = this.activeBlurLayer() ?? this.activeSharpenLayer() ??
      this.activeSmudgeLayer() ?? this.activeSpongeLayer() ?? this.activeDodgeBurnLayer() ??
      this.activeRedEyeLayer() ?? this.activeSpotHealLayer();
    if (retouch !== undefined) {
      this.controller.store.setPaintRetouchStrength(retouch.id, this.retouchStrengthValue);
      this.syncState();
    }
  }

  private applySpongeMode(mode: number): void {
    this.spongeModeValue = mode === 0 ? 0 : 1;
    const sponge: LayerModel | undefined = this.activeSpongeLayer();
    if (sponge !== undefined) {
      this.controller.store.setPaintSpongeMode(sponge.id, this.spongeModeValue);
      this.syncState();
    }
  }

  private applyRetouchRange(range: number): void {
    this.retouchRangeValue = Math.max(0, Math.min(2, Math.round(range)));
    const retouch: LayerModel | undefined = this.activeDodgeBurnLayer();
    if (retouch !== undefined) {
      this.controller.store.setPaintRetouchRange(retouch.id, this.retouchRangeValue);
      this.syncState();
    }
  }

  private async tapMagicWand(localX: number, localY: number): Promise<void> {
    if (!this.isMagicWandTool() || this.magicWandBusy) {
      return;
    }
    this.magicWandBusy = true;
    const point: TransformPoint = {
      x: this.previewToSelectionX(localX),
      y: this.previewToSelectionY(localY)
    };
    try {
      const selected: boolean = await this.controller.selectMagicWand(point.x, point.y,
        this.magicWandTolerance, this.magicWandContiguous);
      if (selected) {
        this.syncState();
      } else {
        this.status = 'Magic wand found no matching region';
      }
    } catch (error) {
      this.status = 'Magic wand selection unavailable';
    } finally {
      this.magicWandBusy = false;
    }
  }

  private updateMagicWandTolerance(value: number): void {
    this.magicWandTolerance = Math.max(0, Math.min(255, Math.round(value)));
  }

  private applyGradientSecondaryColor(): void {
    const gradient: LayerModel | undefined = this.activeGradientLayer();
    if (gradient !== undefined) {
      this.controller.store.setPaintSecondaryColor(gradient.id, this.gradientSecondaryInput);
      this.syncState();
    }
  }

  private applyGradientForegroundColor(): void {
    const gradient: LayerModel | undefined = this.activeGradientLayer();
    if (gradient !== undefined) {
      this.controller.store.setPaintColor(gradient.id, this.gradientPrimaryInput);
      this.syncState();
    }
  }

  private toggleGradientReverse(): void {
    const gradient: LayerModel | undefined = this.activeGradientLayer();
    if (gradient !== undefined) {
      this.controller.store.setPaintGradientReverse(gradient.id, !this.gradientReverse);
      this.syncState();
    }
  }

  private beginFillTouch(event: TouchEvent): void {
    if (!this.isFillTool() || event.changedTouches.length === 0) {
      return;
    }
    const touch = event.changedTouches[0];
    this.fillSeedPoint = this.outputToSourcePoint(touch.x, touch.y);
  }

  private finishFillTouch(event: TouchEvent): void {
    if (!this.isFillTool() || event.changedTouches.length === 0) {
      return;
    }
    if (event.type === TouchType.Move || event.type === TouchType.Up) {
      const touch = event.changedTouches[0];
      this.fillSeedPoint = this.outputToSourcePoint(touch.x, touch.y);
    }
    const seed: TransformPoint | undefined = this.fillSeedPoint;
    this.fillSeedPoint = undefined;
    if (seed !== undefined) {
      this.controller.store.addFillLayer(seed, this.foregroundColorValue,
        this.fillToleranceValue, this.fillContiguousValue, this.fillAntialiasValue);
      this.syncState();
    }
  }

  private updateFillTolerance(value: number): void {
    this.fillToleranceValue = Math.max(0, Math.min(255, Math.round(value)));
    const fill: LayerModel | undefined = this.activeFillLayer();
    if (fill !== undefined) {
      this.controller.store.setPaintFillTolerance(fill.id, this.fillToleranceValue);
      this.syncState();
    }
  }

  private toggleFillContiguous(): void {
    this.fillContiguousValue = !this.fillContiguousValue;
    const fill: LayerModel | undefined = this.activeFillLayer();
    if (fill !== undefined) {
      this.controller.store.setPaintFillContiguous(fill.id, this.fillContiguousValue);
      this.syncState();
    }
  }

  private toggleFillAntialias(): void {
    this.fillAntialiasValue = !this.fillAntialiasValue;
    const fill: LayerModel | undefined = this.activeFillLayer();
    if (fill !== undefined) {
      this.controller.store.setPaintFillAntialias(fill.id, this.fillAntialiasValue);
      this.syncState();
    }
  }

  private beginCloneTouch(event: TouchEvent): void {
    if (!this.isCloneTool() || event.changedTouches.length === 0) {
      return;
    }
    const touch = event.changedTouches[0];
    const point: TransformPoint = this.outputToSourcePoint(touch.x, touch.y);
    if (this.cloneSourcePoint === undefined) {
      this.cloneSourcePoint = point;
      this.cloneTargetPoints = [];
      this.status = 'Clone source set';
      return;
    }
    this.cloneTargetPoints = [point];
    this.cloneDragging = true;
  }

  private updateCloneTouch(event: TouchEvent): void {
    if (!this.cloneDragging || event.changedTouches.length === 0) {
      return;
    }
    const touch = event.changedTouches[0];
    const point: TransformPoint = this.outputToSourcePoint(touch.x, touch.y);
    const points: TransformPoint[] = this.cloneTargetPoints.slice();
    const previous: TransformPoint | undefined = points.length > 0 ? points[points.length - 1] : undefined;
    if (previous === undefined || Math.abs(previous.x - point.x) >= 1 ||
      Math.abs(previous.y - point.y) >= 1) {
      points.push(point);
      this.cloneTargetPoints = points;
    }
  }

  private finishCloneTouch(event: TouchEvent): void {
    if (!this.isCloneTool() || event.changedTouches.length === 0) {
      return;
    }
    if (event.type === TouchType.Move || event.type === TouchType.Up) {
      this.updateCloneTouch(event);
    }
    const source: TransformPoint | undefined = this.cloneSourcePoint;
    const points: TransformPoint[] = this.cloneTargetPoints.slice();
    this.cloneDragging = false;
    if (source !== undefined && points.length > 0) {
      this.controller.store.addCloneLayer(source, points, this.brushWidthValue);
      this.cloneSourcePoint = undefined;
      this.cloneTargetPoints = [];
      this.syncState();
    }
  }

  private cancelCloneTouch(): void {
    this.cloneDragging = false;
    this.cloneTargetPoints = [];
  }

  private shapeValue(key: string): number {
    if (key === 'x') {
      return this.shapeXValue;
    }
    if (key === 'y') {
      return this.shapeYValue;
    }
    if (key === 'width') {
      return this.shapeWidthValue;
    }
    return this.shapeHeightValue;
  }

  private shapeMinimum(key: string): number {
    return key === 'width' || key === 'height' ? 1 : 0;
  }

  private shapeMaximum(key: string): number {
    if (key === 'x') {
      return Math.max(0, this.sourceCanvasWidth - 1);
    }
    if (key === 'y') {
      return Math.max(0, this.sourceCanvasHeight - 1);
    }
    return key === 'width' ? Math.max(1, this.sourceCanvasWidth) : Math.max(1, this.sourceCanvasHeight);
  }

  private updateShapeDimension(key: string, value: number): void {
    const layer: LayerModel | undefined = this.activeShapeLayer();
    if (layer === undefined) {
      return;
    }
    const x: number = key === 'x' ? value : this.shapeXValue;
    const y: number = key === 'y' ? value : this.shapeYValue;
    const width: number = key === 'width' ? value : this.shapeWidthValue;
    const height: number = key === 'height' ? value : this.shapeHeightValue;
    this.controller.store.setShapeBounds(layer.id, x, y, width, height);
    this.syncState();
  }

  private applyShapeFill(): void {
    const layer: LayerModel | undefined = this.activeShapeLayer();
    if (layer !== undefined) {
      this.controller.store.setShapeFill(layer.id, this.shapeFillValue);
      this.syncState();
    }
  }

  private applyShapeStroke(): void {
    const layer: LayerModel | undefined = this.activeShapeLayer();
    if (layer !== undefined) {
      this.controller.store.setShapeStroke(layer.id, this.shapeStrokeValue);
      this.syncState();
    }
  }

  private updateShapeStrokeWidth(value: number): void {
    const layer: LayerModel | undefined = this.activeShapeLayer();
    if (layer !== undefined) {
      this.controller.store.setShapeStrokeWidth(layer.id, value);
      this.syncState();
    }
  }

  @Builder
  shapeDimensionSlider(label: string, key: string) {
    Column({ space: 4 }) {
      Row() {
        Text(label)
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Blank()
        Text(Math.round(this.shapeValue(key)).toString())
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT)
      }
      .width('100%')
      Slider({
        value: this.shapeValue(key),
        min: this.shapeMinimum(key),
        max: this.shapeMaximum(key),
        step: 1
      })
        .width('100%')
        .selectedColor(ACCENT)
        .trackColor(PANEL_RAISED)
        .blockColor(ACCENT_WARM)
        .onChange((value: number) => {
          this.updateShapeDimension(key, value);
        })
        .id('shape-' + key + '-slider')
    }
    .width('100%')
  }

  @Builder
  private cropAspectButton(aspect: CropAspect, label: string) {
    Button(this.cropDraftAspect === aspect ? label + ' ✓' : label)
      .height(32)
      .fontSize(10)
      .fontColor(this.cropDraftAspect === aspect ? ACCENT : TEXT_MUTED)
      .backgroundColor(PANEL_RAISED)
      .border({ width: 1, color: this.cropDraftAspect === aspect ? ACCENT : BORDER, radius: 5 })
      .id('crop-aspect-' + aspect)
      .accessibilityText('Set crop aspect ratio to ' + label)
      .onClick(() => {
        this.setCropAspect(aspect);
      })
  }

  private cropValue(key: string): number {
    if (key === 'x') {
      return this.cropDraftRect.x;
    }
    if (key === 'y') {
      return this.cropDraftRect.y;
    }
    if (key === 'width') {
      return this.cropDraftRect.width;
    }
    return this.cropDraftRect.height;
  }

  private cropMinimum(key: string): number {
    return key === 'width' || key === 'height' ? 1 : 0;
  }

  private cropMaximum(key: string): number {
    if (key === 'x') {
      return Math.max(0, this.sourceCanvasWidth - 1);
    }
    if (key === 'y') {
      return Math.max(0, this.sourceCanvasHeight - 1);
    }
    return key === 'width' ? Math.max(1, this.sourceCanvasWidth) : Math.max(1, this.sourceCanvasHeight);
  }

  private updateCropDimension(key: string, value: number): void {
    if (key === 'x') {
      this.updateCropDraft(value, this.cropDraftRect.y, this.cropDraftRect.width, this.cropDraftRect.height);
    } else if (key === 'y') {
      this.updateCropDraft(this.cropDraftRect.x, value, this.cropDraftRect.width, this.cropDraftRect.height);
    } else if (key === 'width') {
      this.updateCropDraft(this.cropDraftRect.x, this.cropDraftRect.y, value, this.cropDraftRect.height);
    } else {
      this.updateCropDraft(this.cropDraftRect.x, this.cropDraftRect.y, this.cropDraftRect.width, value);
    }
  }

  @Builder
  private cropDimensionSlider(label: string, key: string) {
    Column({ space: 4 }) {
      Row() {
        Text(label)
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Blank()
        Text(Math.round(this.cropValue(key)).toString())
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT)
      }
      .width('100%')
      Slider({
        value: this.cropValue(key),
        min: this.cropMinimum(key),
        max: this.cropMaximum(key),
        step: 1
      })
        .width('100%')
        .selectedColor(ACCENT)
        .trackColor(PANEL_RAISED)
        .blockColor(ACCENT_WARM)
        .onChange((nextValue: number) => {
          this.updateCropDimension(key, nextValue);
        })
    }
    .width('100%')
  }

  private updatePreviewGeometry(): void {
    const availableWidth: number = Math.max(180, this.viewportWidth - TOOL_RAIL_WIDTH -
      (this.sidebarOpen ? SIDEBAR_WIDTH : 0) - 64);
    const availableHeight: number = Math.max(160, this.viewportHeight - 58 - 42 - 28 - 64);
    const draftSize = transformedSize(this.cropDraftRect.width, this.cropDraftRect.height, {
      rotation: this.documentRotation,
      flipHorizontal: this.documentFlipHorizontal,
      flipVertical: this.documentFlipVertical
    });
    const outputWidth: number = Math.max(1, draftSize.width);
    const outputHeight: number = Math.max(1, draftSize.height);
    const fit: number = Math.min(availableWidth / outputWidth, availableHeight / outputHeight);
    this.artboardScale = Math.max(0.1, fit);
    this.sourceArtboardWidth = Math.max(1, this.sourceCanvasWidth * this.artboardScale);
    this.sourceArtboardHeight = Math.max(1, this.sourceCanvasHeight * this.artboardScale);
    this.outputArtboardWidth = Math.max(1, outputWidth * this.artboardScale);
    this.outputArtboardHeight = Math.max(1, outputHeight * this.artboardScale);
    this.previewArtboardWidth = this.outputArtboardWidth;
    this.previewArtboardHeight = this.outputArtboardHeight;
    const sourceWidth: number = Math.max(1, this.sourceArtboardWidth);
    const sourceHeight: number = Math.max(1, this.sourceArtboardHeight);
    const cropLeft: number = this.cropDraftRect.x * this.artboardScale;
    const cropTop: number = this.cropDraftRect.y * this.artboardScale;
    const cropOriginX: number = transformPoint(cropLeft, cropTop, sourceWidth, sourceHeight, {
      rotation: this.documentRotation,
      flipHorizontal: this.documentFlipHorizontal,
      flipVertical: this.documentFlipVertical
    }).x;
    const cropOriginY: number = transformPoint(cropLeft, cropTop, sourceWidth, sourceHeight, {
      rotation: this.documentRotation,
      flipHorizontal: this.documentFlipHorizontal,
      flipVertical: this.documentFlipVertical
    }).y;
    this.documentMatrix = matrix4.identity()
      .scale({ x: 1, y: 1, centerX: 0, centerY: 0 })
      .setPolyToPoly({
        src: [
          { x: 0, y: 0 },
          { x: sourceWidth, y: 0 },
          { x: 0, y: sourceHeight },
          { x: sourceWidth, y: sourceHeight }
        ],
        dst: [
          { x: transformPoint(0, 0, sourceWidth, sourceHeight, {
            rotation: this.documentRotation,
            flipHorizontal: this.documentFlipHorizontal,
            flipVertical: this.documentFlipVertical
          }).x - cropOriginX, y: transformPoint(0, 0, sourceWidth, sourceHeight, {
            rotation: this.documentRotation,
            flipHorizontal: this.documentFlipHorizontal,
            flipVertical: this.documentFlipVertical
          }).y - cropOriginY },
          { x: transformPoint(sourceWidth, 0, sourceWidth, sourceHeight, {
            rotation: this.documentRotation,
            flipHorizontal: this.documentFlipHorizontal,
            flipVertical: this.documentFlipVertical
          }).x - cropOriginX, y: transformPoint(sourceWidth, 0, sourceWidth, sourceHeight, {
            rotation: this.documentRotation,
            flipHorizontal: this.documentFlipHorizontal,
            flipVertical: this.documentFlipVertical
          }).y - cropOriginY },
          { x: transformPoint(0, sourceHeight, sourceWidth, sourceHeight, {
            rotation: this.documentRotation,
            flipHorizontal: this.documentFlipHorizontal,
            flipVertical: this.documentFlipVertical
          }).x - cropOriginX, y: transformPoint(0, sourceHeight, sourceWidth, sourceHeight, {
            rotation: this.documentRotation,
            flipHorizontal: this.documentFlipHorizontal,
            flipVertical: this.documentFlipVertical
          }).y - cropOriginY },
          { x: transformPoint(sourceWidth, sourceHeight, sourceWidth, sourceHeight, {
            rotation: this.documentRotation,
            flipHorizontal: this.documentFlipHorizontal,
            flipVertical: this.documentFlipVertical
          }).x - cropOriginX, y: transformPoint(sourceWidth, sourceHeight, sourceWidth, sourceHeight, {
            rotation: this.documentRotation,
            flipHorizontal: this.documentFlipHorizontal,
            flipVertical: this.documentFlipVertical
          }).y - cropOriginY }
        ],
        pointCount: 4
      });
  }

  private presetColorFilter(preset: string): drawing.ColorFilter | undefined {
    try {
      return drawing.ColorFilter.createMatrixColorFilter(getFilterPresetMatrix(preset, 100));
    } catch (error) {
      return undefined;
    }
  }

  private presetAccent(preset: string): string {
    if (preset === 'warm') {
      return '#F1B85B';
    }
    if (preset === 'cool') {
      return '#63A8FF';
    }
    if (preset === 'vivid') {
      return '#E56B9F';
    }
    if (preset === 'vintage') {
      return '#C9955A';
    }
    if (preset === 'mono') {
      return '#B9C1C0';
    }
    if (preset === 'softLight') {
      return '#8DB7A8';
    }
    return ACCENT;
  }

  private selectLayer(id: string): void {
    this.controller.store.selectLayer(id);
    this.syncState();
  }

  private toggleLayerVisibility(id: string): void {
    this.controller.store.toggleLayerVisibility(id);
    this.syncState();
  }

  private toggleLayerLocked(id: string): void {
    this.controller.store.toggleLayerLocked(id);
    this.syncState();
  }

  private updateLayerOpacity(value: number): void {
    const selected: LayerModel | undefined = this.controller.store.selectedLayer;
    if (selected !== undefined) {
      this.controller.store.setLayerOpacity(selected.id, value);
      this.syncState();
    }
  }

  private updateLayerBlendMode(mode: string): void {
    const selected: LayerModel | undefined = this.controller.store.selectedLayer;
    if (selected !== undefined) {
      this.controller.store.setLayerBlendMode(selected.id, mode);
      this.syncState();
    }
  }

  private selectColorTarget(target: ColorTarget): void {
    this.colorTarget = target;
    this.colorInput = this.controller.store.getColor(target);
  }

  private colorValueForTarget(target: ColorTarget): string {
    return target === ColorTarget.FOREGROUND ? this.foregroundColorValue : this.backgroundColorValue;
  }

  private activeTextLayer(): LayerModel | undefined {
    for (const layer of this.layerRows) {
      if (layer.id === this.activeLayerId && layer.kind === 'text') {
        return layer;
      }
    }
    return undefined;
  }

  private selectColor(color: string): void {
    this.controller.store.setColor(this.colorTarget, color);
    this.colorInput = this.controller.store.getColor(this.colorTarget);
    this.syncState();
  }

  private updateColorInput(value: string): void {
    this.colorInput = value;
  }

  private applyColorInput(): void {
    this.selectColor(this.colorInput);
  }

  private addCurrentSwatch(): void {
    this.controller.store.addSwatch(this.colorInput);
    this.syncState();
  }

  private swapColors(): void {
    this.controller.store.swapColors();
    this.colorInput = this.controller.store.getColor(this.colorTarget);
    this.syncState();
  }

  private resetColors(): void {
    this.controller.store.resetColors();
    this.colorInput = this.controller.store.getColor(this.colorTarget);
    this.syncState();
  }

  private addLayer(): void {
    this.controller.store.addLayer();
    this.syncState();
  }

  private addTextLayer(): void {
    this.controller.store.addTextLayer('New text');
    this.syncState();
  }

  private applyTextContent(): void {
    if (this.controller.store.selectedLayer?.kind === 'text') {
      this.controller.store.setTextContent(this.controller.store.selectedLayerId, this.textDraft);
      this.syncState();
    }
  }

  private updateTextSize(value: number): void {
    if (this.controller.store.selectedLayer?.kind === 'text') {
      this.controller.store.setTextSize(this.controller.store.selectedLayerId, value);
      this.syncState();
    }
  }

  private applyTextColor(): void {
    if (this.controller.store.selectedLayer?.kind === 'text') {
      this.controller.store.setTextColor(this.controller.store.selectedLayerId, this.textColorValue);
      this.syncState();
    }
  }

  private updateTextX(value: number): void {
    if (this.controller.store.selectedLayer?.kind === 'text') {
      this.controller.store.setTextPosition(this.controller.store.selectedLayerId, value, this.textYValue);
      this.syncState();
    }
  }

  private updateTextY(value: number): void {
    if (this.controller.store.selectedLayer?.kind === 'text') {
      this.controller.store.setTextPosition(this.controller.store.selectedLayerId, this.textXValue, value);
      this.syncState();
    }
  }

  private duplicateLayer(id: string): void {
    this.controller.store.duplicateLayer(id);
    this.syncState();
  }

  private deleteLayer(id: string): void {
    this.controller.store.deleteLayer(id);
    this.syncState();
  }

  private moveLayer(id: string, offset: number): void {
    this.controller.store.moveLayer(id, offset);
    this.syncState();
  }

  private async openImage(): Promise<void> {
    await this.controller.openImage();
    this.syncState();
  }

  private async exportImage(format: ExportFormat = ExportFormat.JPEG): Promise<void> {
    await this.controller.exportImage(format);
    this.syncState();
  }

  private undo(): void {
    this.controller.store.undo();
    this.syncState();
  }

  private redo(): void {
    this.controller.store.redo();
    this.syncState();
  }

  @Builder
  topBar() {
    Row({ space: 12 }) {
      Row({ space: 8 }) {
        Text('P')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#102321')
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .backgroundColor(ACCENT)
          .borderRadius(7)
        Column({ space: 1 }) {
          Text('PhotoSuite')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT)
          Text('Native editor workspace')
            .fontSize(10)
            .fontColor(TEXT_FAINT)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)

      Button('Open')
        .height(CONTROL_HEIGHT)
        .fontSize(13)
        .fontColor(TEXT)
        .backgroundColor(PANEL_RAISED)
        .border({ width: 1, color: BORDER, radius: 6 })
        .onClick(() => {
          this.openImage();
        })
        .id('open-image-button')
        .accessibilityText('Open image')
      Button('Export')
        .height(CONTROL_HEIGHT)
        .fontSize(13)
        .fontColor('#102321')
        .backgroundColor(ACCENT)
        .borderRadius(6)
        .onClick(() => {
          this.exportImage();
        })
        .id('export-image-button')
        .accessibilityText('Export image')
      Button('↶')
        .width(CONTROL_HEIGHT)
        .height(CONTROL_HEIGHT)
        .fontSize(21)
        .fontColor(TEXT)
        .backgroundColor(PANEL_RAISED)
        .border({ width: 1, color: BORDER, radius: 6 })
        .enabled(this.canUndo)
        .id('undo-button')
        .accessibilityText('Undo')
        .onClick(() => {
          this.undo();
        })
      Button('↷')
        .width(CONTROL_HEIGHT)
        .height(CONTROL_HEIGHT)
        .fontSize(21)
        .fontColor(TEXT)
        .backgroundColor(PANEL_RAISED)
        .border({ width: 1, color: BORDER, radius: 6 })
        .enabled(this.canRedo)
        .id('redo-button')
        .accessibilityText('Redo')
        .onClick(() => {
          this.redo();
        })
      Button('⋯')
        .width(CONTROL_HEIGHT)
        .height(CONTROL_HEIGHT)
        .fontSize(20)
        .fontColor(TEXT_MUTED)
        .backgroundColor(Color.Transparent)
        .accessibilityText('More commands')
        .bindMenu(this.moreMenu())
    }
    .width('100%')
    .height(58)
    .padding({ left: 18, right: 18 })
    .backgroundColor(PANEL_BG)
    .border({ width: { bottom: 1 }, color: BORDER })
  }

  @Builder
  moreMenu() {
    Menu() {
      MenuItem({ content: 'Fit canvas' })
        .onClick(() => {
          this.controller.store.setZoom(1);
          this.controller.store.setPan(0, 0);
          this.syncState();
        })
      MenuItem({ content: 'Reset adjustments' })
        .onClick(() => {
          this.controller.store.resetAdjustments();
          this.syncState();
        })
      MenuItem({ content: 'Filter Gallery' })
        .onClick(() => {
          this.selectTab(SidebarTab.FILTERS);
        })
      MenuItem({ content: 'Export JPEG' })
        .onClick(() => {
          this.exportImage(ExportFormat.JPEG);
        })
      MenuItem({ content: 'Export PNG' })
        .onClick(() => {
          this.exportImage(ExportFormat.PNG);
        })
      MenuItem({ content: 'Keyboard shortcuts' })
        .onClick(() => {
          this.status = 'Shortcuts: V move · M marquee · B brush · E eraser · Z zoom';
        })
    }
  }

  @Builder
  toolButton(tool: EditorTool, label: string, shortcut: string, resource: Resource) {
    Column({ space: 2 }) {
      Image(resource)
        .width(21)
        .height(21)
        .fillColor(this.activeTool === tool ? ACCENT_WARM : TEXT_MUTED)
      Text(shortcut)
        .fontSize(9)
        .fontColor(this.activeTool === tool ? ACCENT_WARM : TEXT_FAINT)
    }
    .width(42)
    .height(42)
    .justifyContent(FlexAlign.Center)
    .borderRadius(6)
    .backgroundColor(this.activeTool === tool ? colorWithAlpha(ACCENT_WARM, 0.14) : Color.Transparent)
    .hoverEffect(HoverEffect.Highlight)
    .id('tool-' + shortcut.toLowerCase())
    .onClick(() => {
      this.selectTool(tool);
    })
    .accessibilityText(label + ' tool, shortcut ' + shortcut)
  }

  @Builder
  toolRail() {
    Scroll() {
      Flex({
        wrap: FlexWrap.Wrap,
        space: {
          main: LengthMetrics.vp(4),
          cross: LengthMetrics.vp(4)
        }
      }) {
          this.toolButton(EditorTool.MOVE, 'Move', 'V', toolResource(EditorTool.MOVE))
          this.toolButton(EditorTool.RECT_SELECT, 'Rectangular selection', 'M', toolResource(EditorTool.RECT_SELECT))
          this.toolButton(EditorTool.LASSO, 'Lasso', 'L', toolResource(EditorTool.LASSO))
          this.toolButton(EditorTool.MAGIC_WAND, 'Magic Wand', 'W', toolResource(EditorTool.MAGIC_WAND))
          this.toolButton(EditorTool.CROP, 'Crop', 'C', toolResource(EditorTool.CROP))
          this.toolButton(EditorTool.BRUSH, 'Brush', 'B', toolResource(EditorTool.BRUSH))
          this.toolButton(EditorTool.PAINT_BUCKET, 'Paint Bucket', 'F', toolResource(EditorTool.PAINT_BUCKET))
          this.toolButton(EditorTool.CLONE, 'Clone Stamp', 'S', toolResource(EditorTool.CLONE))
          this.toolButton(EditorTool.ERASER, 'Eraser', 'E', toolResource(EditorTool.ERASER))
          this.toolButton(EditorTool.GRADIENT, 'Gradient', 'G', toolResource(EditorTool.GRADIENT))
          this.toolButton(EditorTool.BLUR, 'Blur', 'R', toolResource(EditorTool.BLUR))
          this.toolButton(EditorTool.SHARPEN, 'Sharpen', 'N', toolResource(EditorTool.SHARPEN))
          this.toolButton(EditorTool.SMUDGE, 'Smudge', 'X', toolResource(EditorTool.SMUDGE))
          this.toolButton(EditorTool.SPONGE, 'Sponge', 'Q', toolResource(EditorTool.SPONGE))
          this.toolButton(EditorTool.RED_EYE, 'Red Eye', 'K', toolResource(EditorTool.RED_EYE))
          this.toolButton(EditorTool.SPOT_HEAL, 'Spot Healing', 'J', toolResource(EditorTool.SPOT_HEAL))
          this.toolButton(EditorTool.DODGE, 'Dodge', 'O', toolResource(EditorTool.DODGE))
          this.toolButton(EditorTool.BURN, 'Burn', 'I', toolResource(EditorTool.BURN))
          this.toolButton(EditorTool.TYPE, 'Type', 'T', toolResource(EditorTool.TYPE))
          this.toolButton(EditorTool.PEN, 'Pencil', 'P', toolResource(EditorTool.PEN))
          this.toolButton(EditorTool.PATH_SELECT, 'Path Selection', 'A', toolResource(EditorTool.PATH_SELECT))
          this.toolButton(EditorTool.RECT_SHAPE, 'Rectangle', 'U', toolResource(EditorTool.RECT_SHAPE))
          this.toolButton(EditorTool.ELLIPSE_SHAPE, 'Ellipse', 'Y', toolResource(EditorTool.ELLIPSE_SHAPE))
          this.toolButton(EditorTool.HAND, 'Hand', 'H', toolResource(EditorTool.HAND))
          this.toolButton(EditorTool.ZOOM, 'Zoom', 'Z', toolResource(EditorTool.ZOOM))
      }
      .width(TOOL_RAIL_WIDTH)
      .padding({ top: 8, bottom: 8, left: 6, right: 6 })
    }
    .width(TOOL_RAIL_WIDTH)
    .height('100%')
    .scrollBar(BarState.Auto)
    .backgroundColor(PANEL_BG)
    .border({ width: { right: 1 }, color: BORDER })
  }

  @Builder
  canvasHeader() {
    Row({ space: 10 }) {
      Text(this.documentName)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('·')
        .fontSize(14)
        .fontColor(TEXT_FAINT)
      Text(this.documentWidth.toString() + ' × ' + this.documentHeight.toString())
        .fontSize(11)
        .fontColor(TEXT_MUTED)
      Blank()
        Text(this.isPencilTool() ? 'Pencil' : this.activeTool)
        .fontSize(11)
        .fontColor(ACCENT_WARM)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(colorWithAlpha(ACCENT_WARM, 0.12))
        .borderRadius(4)
        .id('active-tool-label')
      Button('Fit')
        .height(30)
        .fontSize(11)
        .fontColor(TEXT_MUTED)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.controller.store.setZoom(1);
          this.controller.store.setPan(0, 0);
          this.syncState();
        })
    }
    .width('100%')
    .height(42)
    .padding({ left: 18, right: 18 })
    .backgroundColor(PANEL_BG)
    .border({ width: { bottom: 1 }, color: BORDER })
  }

  @Builder
  selectionOverlay() {
    if (this.isSelectionTool() || this.isLassoTool() || this.isMagicWandTool() || this.isShapeTool() ||
      this.isMoveTool() ||
      this.selectionActive || this.shapeDragging || this.moveDragging || this.lassoDragging) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.moveDragging) {
          if (this.isMovingEllipse()) {
            Ellipse({
              width: this.movePreviewRect().width,
              height: this.movePreviewRect().height
            })
              .position({ x: this.movePreviewRect().x, y: this.movePreviewRect().y })
              .stroke(ACCENT_WARM)
              .strokeWidth(Math.max(1, 2 * this.artboardScale))
              .hitTestBehavior(HitTestMode.None)
              .id('move-overlay-ellipse')
          } else if (this.isMovingShape()) {
            Rect({
              width: this.movePreviewRect().width,
              height: this.movePreviewRect().height
            })
              .position({ x: this.movePreviewRect().x, y: this.movePreviewRect().y })
              .stroke(ACCENT_WARM)
              .strokeWidth(Math.max(1, 2 * this.artboardScale))
              .hitTestBehavior(HitTestMode.None)
              .id('move-overlay-rectangle')
          } else if (this.isMovingText()) {
            Stack()
              .width(Math.max(1, this.movePreviewRect().width))
              .height(Math.max(1, this.movePreviewRect().height))
              .position({ x: this.movePreviewRect().x, y: this.movePreviewRect().y })
              .border({ width: 1, color: ACCENT_WARM })
              .hitTestBehavior(HitTestMode.None)
              .id('move-overlay-text')
          }
        }
        if ((this.selectionActive || this.selectionDragging) && this.lassoPoints.length < 3 &&
          !this.isLassoTool()) {
          Stack()
            .width(this.selectionPreviewWidth())
            .height(this.selectionPreviewHeight())
            .position({
              x: this.selectionToPreviewX(this.selectionRect.x),
              y: this.selectionToPreviewY(this.selectionRect.y)
            })
            .border({ width: 1, color: this.selectionDragging ? ACCENT_WARM : ACCENT })
            .backgroundColor(this.selectionDragging ? colorWithAlpha(ACCENT_WARM, 0.08) : Color.Transparent)
            .id('selection-rectangle')
        }
        if (this.lassoDragging || (this.selectionActive &&
          (this.controller.store.document.selection.mode === 'lasso' ||
            this.controller.store.document.selection.mode === 'magicWand'))) {
          Polyline({
            width: this.outputArtboardWidth,
            height: this.outputArtboardHeight
          })
            .points(this.lassoPreviewPoints(this.lassoPoints))
            .fillOpacity(0)
            .stroke(this.lassoDragging ? ACCENT_WARM : ACCENT)
            .strokeWidth(Math.max(1, 2 * this.artboardScale))
            .strokeLineCap(LineCapStyle.Round)
            .strokeLineJoin(LineJoinStyle.Round)
            .hitTestBehavior(HitTestMode.None)
            .id('lasso-selection-outline')
        }
        if (this.selectionActive || this.selectionDragging) {
          Text(this.selectionRect.width.toString() + ' × ' + this.selectionRect.height.toString())
            .fontSize(9)
            .fontFamily('monospace')
            .fontColor(TEXT)
            .padding({ left: 5, right: 5, top: 3, bottom: 3 })
            .backgroundColor(colorWithAlpha(ACCENT_WARM, 0.9))
            .position({
              x: Math.max(0, this.selectionToPreviewX(this.selectionRect.x)),
              y: Math.max(0, this.selectionToPreviewY(this.selectionRect.y) - 20)
            })
        }
      }
      .width(this.outputArtboardWidth)
      .height(this.outputArtboardHeight)
      .hitTestBehavior(this.isSelectionTool() || this.isLassoTool() || this.isMagicWandTool() ||
        this.isShapeTool() || this.isMoveTool() ?
        HitTestMode.Block : HitTestMode.None)
      .id('selection-overlay')
      .onTouch((event: TouchEvent) => {
        if (!this.isMagicWandTool()) {
          return;
        }
        if (event.type === TouchType.Up && event.changedTouches.length > 0) {
          const touch = event.changedTouches[0];
          this.tapMagicWand(touch.x, touch.y);
        }
      })
      .gesture(
        PanGesture({ distance: 2 })
          .onActionStart((event: GestureEvent) => {
            this.beginSelectionDrag(event);
          })
          .onActionUpdate((event: GestureEvent) => {
            this.updateSelectionDrag(event);
          })
          .onActionEnd(() => {
            this.finishSelectionDrag();
          })
          .onActionCancel(() => {
            this.cancelSelectionDrag();
          })
      )
    }
  }

  @Builder
  brushOverlay() {
    if (this.isBrushTool() || this.isPencilTool() || this.isEraserTool() || this.isBlurTool() ||
      this.isSharpenTool() || this.isSmudgeTool() || this.isSpongeTool() ||
      this.isDodgeBurnTool() || this.isRedEyeTool() || this.isSpotHealTool() || this.brushDragging) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.brushPoints.length > 0) {
          if (this.brushPoints.length === 1) {
            Circle({
              width: this.brushWidthValue * this.artboardScale,
              height: this.brushWidthValue * this.artboardScale
            })
              .position({
                x: this.paintDraftPreviewPoint(this.brushPoints[0]).x -
                  this.brushWidthValue * this.artboardScale / 2,
                y: this.paintDraftPreviewPoint(this.brushPoints[0]).y -
                  this.brushWidthValue * this.artboardScale / 2
              })
              .fill(this.isEraserTool() || this.isBlurTool() || this.isSharpenTool() ||
                this.isSmudgeTool() || this.isSpongeTool() || this.isDodgeBurnTool() ? Color.Transparent :
                this.foregroundColorValue)
              .stroke(this.isEraserTool() || this.isBlurTool() || this.isSharpenTool() ||
                this.isSmudgeTool() || this.isSpongeTool() || this.isDodgeBurnTool() ? ACCENT_WARM :
                Color.Transparent)
              .strokeWidth(Math.max(2, 2 * this.artboardScale))
              .hitTestBehavior(HitTestMode.None)
              .id('brush-draft-dot')
          } else {
            Polyline({
              width: this.outputArtboardWidth,
              height: this.outputArtboardHeight
            })
              .points(this.paintDraftPreviewPoints(this.brushPoints))
              .fillOpacity(0)
              .stroke(this.isEraserTool() || this.isBlurTool() || this.isSharpenTool() ||
                this.isSmudgeTool() || this.isSpongeTool() || this.isDodgeBurnTool() ? ACCENT_WARM :
                this.foregroundColorValue)
              .strokeDashArray(this.isEraserTool() || this.isBlurTool() || this.isSharpenTool() ||
                this.isSmudgeTool() || this.isSpongeTool() || this.isDodgeBurnTool() ? [6, 4] : [])
              .strokeWidth(this.brushWidthValue * this.artboardScale)
              .strokeLineCap(LineCapStyle.Round)
              .strokeLineJoin(LineJoinStyle.Round)
              .hitTestBehavior(HitTestMode.None)
              .id('brush-draft-stroke')
          }
        }
      }
      .width(this.outputArtboardWidth)
      .height(this.outputArtboardHeight)
      .hitTestBehavior(HitTestMode.Block)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.beginBrushTouch(event);
        } else if (event.type === TouchType.Move) {
          this.updateBrushTouch(event);
        } else if (event.type === TouchType.Up) {
          this.finishBrushTouch(event);
        } else if (event.type === TouchType.Cancel) {
          this.cancelBrushTouch();
        }
      })
      .id('brush-overlay')
    }
  }

  @Builder
  gradientOverlay() {
    if (this.isGradientTool() || this.gradientDragging) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.gradientStartPoint !== undefined && this.gradientEndPoint !== undefined) {
          Polyline({
            width: this.outputArtboardWidth,
            height: this.outputArtboardHeight
          })
            .points([
              [
                this.paintDraftPreviewPoint(this.gradientStartPoint).x,
                this.paintDraftPreviewPoint(this.gradientStartPoint).y
              ],
              [
                this.paintDraftPreviewPoint(this.gradientEndPoint).x,
                this.paintDraftPreviewPoint(this.gradientEndPoint).y
              ]
            ])
            .fillOpacity(0)
            .stroke(ACCENT_WARM)
            .strokeWidth(Math.max(2, 2 * this.artboardScale))
            .strokeLineCap(LineCapStyle.Round)
            .strokeLineJoin(LineJoinStyle.Round)
            .hitTestBehavior(HitTestMode.None)
            .id('gradient-draft-line')
          Circle({
            width: Math.max(10, 10 * this.artboardScale),
            height: Math.max(10, 10 * this.artboardScale)
          })
            .position({
              x: this.paintDraftPreviewPoint(this.gradientStartPoint).x -
                Math.max(5, 5 * this.artboardScale),
              y: this.paintDraftPreviewPoint(this.gradientStartPoint).y -
                Math.max(5, 5 * this.artboardScale)
            })
            .fill(this.gradientPrimaryInput)
            .stroke(Color.White)
            .strokeWidth(Math.max(1, this.artboardScale))
            .hitTestBehavior(HitTestMode.None)
            .id('gradient-start-handle')
          Circle({
            width: Math.max(10, 10 * this.artboardScale),
            height: Math.max(10, 10 * this.artboardScale)
          })
            .position({
              x: this.paintDraftPreviewPoint(this.gradientEndPoint).x -
                Math.max(5, 5 * this.artboardScale),
              y: this.paintDraftPreviewPoint(this.gradientEndPoint).y -
                Math.max(5, 5 * this.artboardScale)
            })
            .fill(this.gradientSecondaryInput)
            .stroke(Color.White)
            .strokeWidth(Math.max(1, this.artboardScale))
            .hitTestBehavior(HitTestMode.None)
            .id('gradient-end-handle')
        }
      }
      .width(this.outputArtboardWidth)
      .height(this.outputArtboardHeight)
      .hitTestBehavior(HitTestMode.Block)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.beginGradientTouch(event);
        } else if (event.type === TouchType.Move) {
          this.updateGradientTouch(event);
        } else if (event.type === TouchType.Up) {
          this.finishGradientTouch(event);
        } else if (event.type === TouchType.Cancel) {
          this.cancelGradientTouch();
        }
      })
      .id('gradient-overlay')
    }
  }

  @Builder
  fillOverlay() {
    if (this.isFillTool() || this.fillSeedPoint !== undefined) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.fillSeedPoint !== undefined) {
          Circle({
            width: Math.max(14, 14 * this.artboardScale),
            height: Math.max(14, 14 * this.artboardScale)
          })
            .position({
              x: this.paintDraftPreviewPoint(this.fillSeedPoint).x - Math.max(7, 7 * this.artboardScale),
              y: this.paintDraftPreviewPoint(this.fillSeedPoint).y - Math.max(7, 7 * this.artboardScale)
            })
            .fill(Color.Transparent)
            .stroke(ACCENT_WARM)
            .strokeWidth(Math.max(2, 2 * this.artboardScale))
            .hitTestBehavior(HitTestMode.None)
            .id('fill-seed-marker')
        }
      }
      .width(this.outputArtboardWidth)
      .height(this.outputArtboardHeight)
      .hitTestBehavior(HitTestMode.Block)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.beginFillTouch(event);
        } else if (event.type === TouchType.Move) {
          this.fillSeedPoint = this.outputToSourcePoint(event.touches[0].x, event.touches[0].y);
        } else if (event.type === TouchType.Up) {
          this.finishFillTouch(event);
        } else if (event.type === TouchType.Cancel) {
          this.fillSeedPoint = undefined;
        }
      })
      .id('fill-overlay')
    }
  }

  @Builder
  cloneOverlay() {
    if (this.isCloneTool() || this.cloneSourcePoint !== undefined || this.cloneTargetPoints.length > 0) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.cloneSourcePoint !== undefined && this.cloneTargetPoints.length > 0) {
          Polyline({
            width: this.outputArtboardWidth,
            height: this.outputArtboardHeight
          })
            .points([
              [
                this.paintDraftPreviewPoint(this.cloneSourcePoint).x,
                this.paintDraftPreviewPoint(this.cloneSourcePoint).y
              ],
              [
                this.paintDraftPreviewPoint(this.cloneTargetPoints[this.cloneTargetPoints.length - 1]).x,
                this.paintDraftPreviewPoint(this.cloneTargetPoints[this.cloneTargetPoints.length - 1]).y
              ]
            ])
            .fillOpacity(0)
            .stroke(ACCENT_WARM)
            .strokeWidth(Math.max(2, 2 * this.artboardScale))
            .strokeDashArray([8, 6])
            .hitTestBehavior(HitTestMode.None)
            .id('clone-source-guide')
        }
        if (this.cloneSourcePoint !== undefined) {
          Stack()
            .width(Math.max(18, 18 * this.artboardScale))
            .height(Math.max(18, 18 * this.artboardScale))
            .position({
              x: this.paintDraftPreviewPoint(this.cloneSourcePoint).x - Math.max(9, 9 * this.artboardScale),
              y: this.paintDraftPreviewPoint(this.cloneSourcePoint).y - Math.max(9, 9 * this.artboardScale)
            })
            .border({ width: 2, color: ACCENT_WARM })
            .backgroundColor(Color.Transparent)
            .hitTestBehavior(HitTestMode.None)
            .id('clone-source-marker')
        }
      }
      .width(this.outputArtboardWidth)
      .height(this.outputArtboardHeight)
      .hitTestBehavior(HitTestMode.Block)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.beginCloneTouch(event);
        } else if (event.type === TouchType.Move) {
          this.updateCloneTouch(event);
        } else if (event.type === TouchType.Up) {
          this.finishCloneTouch(event);
        } else if (event.type === TouchType.Cancel) {
          this.cancelCloneTouch();
        }
      })
      .id('clone-overlay')
    }
  }

  @Builder
  imagePreview() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 14 }) {
        Text('PHOTOSUITE')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(ACCENT)
          .letterSpacing(2)
        Text('Edit with intention.')
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT)
        Text('Open a local image to begin a native, non-destructive edit.')
          .fontSize(13)
          .fontColor(TEXT_MUTED)
          .textAlign(TextAlign.Center)
          .maxLines(2)
        Button('Open image')
          .height(38)
          .fontSize(13)
          .fontColor('#102321')
          .backgroundColor(ACCENT)
          .borderRadius(6)
          .onClick(() => {
            this.openImage();
          })
      }
      .width(300)
      .alignItems(HorizontalAlign.Center)
      Stack({ alignContent: Alignment.Center }) {
        Stack({ alignContent: Alignment.TopStart }) {
          Stack({ alignContent: Alignment.TopStart }) {
            if (this.previewPixelMap !== undefined && !this.brushDragging) {
              Image(this.previewPixelMap)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Fill)
                .hitTestBehavior(HitTestMode.None)
                .id('native-preview-pixelmap')
            } else if (typeof this.controller.store.document.source === 'string') {
              Image($rawfile('sample_beach.jpg'))
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Fill)
                .colorFilter(this.filterMatrixValue)
                .blur(this.blurValue)
                .onError(() => {
                  this.status = 'Built-in preview unavailable';
                })
            } else {
              Image(this.controller.store.document.source)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Fill)
                .colorFilter(this.filterMatrixValue)
                .blur(this.blurValue)
                .onError(() => {
                  this.status = 'Preview render failed';
                })
            }
            if (this.previewPixelMap === undefined) {
              ForEach(this.layerRows, (layer: LayerModel) => {
              if (layer.kind === 'text' && layer.visible && layer.textContent.length > 0) {
                Text(layer.textContent)
                  .fontSize(layer.textSize * this.artboardScale)
                  .fontColor(layer.textColor)
                  .fontWeight(FontWeight.Medium)
                  .position({ x: layer.textX * this.artboardScale, y: layer.textY * this.artboardScale })
                  .id('text-layer-' + layer.id)
              }
            }, (layer: LayerModel) => layer.id + ':' + layer.textContent + ':' + layer.textSize.toString() +
              ':' + layer.textColor + ':' + layer.textX.toString() + ':' + layer.textY.toString())
              ForEach(this.layerRows, (layer: LayerModel) => {
              if (layer.kind === 'paint' && (layer.paintMode === PaintMode.BRUSH ||
                layer.paintMode === PaintMode.PENCIL) && layer.visible &&
                layer.paintPoints.length > 0) {
                if (layer.paintPoints.length === 1) {
                  Circle({
                    width: layer.paintWidth * this.artboardScale,
                    height: layer.paintWidth * this.artboardScale
                  })
                    .position({
                      x: this.paintSourcePointForLayer(layer).x -
                        layer.paintWidth * this.artboardScale / 2,
                      y: this.paintSourcePointForLayer(layer).y -
                        layer.paintWidth * this.artboardScale / 2
                    })
                    .fill(layer.paintColor)
                    .opacity(layer.opacity / 100)
                    .hitTestBehavior(HitTestMode.None)
                    .id('paint-layer-' + layer.id)
                } else {
                  Polyline({
                    width: this.sourceArtboardWidth,
                    height: this.sourceArtboardHeight
                  })
                    .points(this.paintSourcePreviewPoints(layer.paintPoints))
                    .fillOpacity(0)
                    .stroke(layer.paintColor)
                    .strokeOpacity(layer.opacity / 100)
                    .strokeWidth(layer.paintWidth * this.artboardScale)
                    .strokeLineCap(LineCapStyle.Round)
                    .strokeLineJoin(LineJoinStyle.Round)
                    .hitTestBehavior(HitTestMode.None)
                    .id('paint-layer-' + layer.id)
                }
              }
            }, (layer: LayerModel) => layer.id + ':' + layer.paintColor + ':' +
              layer.paintWidth.toString() + ':' + layer.opacity.toString() + ':' +
              layer.paintPoints.length.toString())
              ForEach(this.layerRows, (layer: LayerModel) => {
              if (layer.kind === 'shape' && layer.visible && layer.shapeWidth > 0 && layer.shapeHeight > 0) {
                if (layer.shapeType === ShapeType.ELLIPSE) {
                  Ellipse({
                    width: layer.shapeWidth * this.artboardScale,
                    height: layer.shapeHeight * this.artboardScale
                  })
                    .position({ x: layer.shapeX * this.artboardScale, y: layer.shapeY * this.artboardScale })
                    .fill(layer.shapeFill)
                    .fillOpacity(layer.opacity / 100)
                    .stroke(layer.shapeStroke)
                    .strokeWidth(layer.shapeStrokeWidth * this.artboardScale)
                    .hitTestBehavior(HitTestMode.None)
                    .id('shape-layer-' + layer.id)
                } else {
                  Rect({
                    width: layer.shapeWidth * this.artboardScale,
                    height: layer.shapeHeight * this.artboardScale
                  })
                    .position({ x: layer.shapeX * this.artboardScale, y: layer.shapeY * this.artboardScale })
                    .fill(layer.shapeFill)
                    .fillOpacity(layer.opacity / 100)
                    .stroke(layer.shapeStroke)
                    .strokeWidth(layer.shapeStrokeWidth * this.artboardScale)
                    .hitTestBehavior(HitTestMode.None)
                    .id('shape-layer-' + layer.id)
                }
              }
            }, (layer: LayerModel) => layer.id + ':' + layer.shapeType + ':' + layer.shapeX.toString() +
              ':' + layer.shapeY.toString() + ':' + layer.shapeWidth.toString() + ':' + layer.shapeHeight.toString() +
              ':' + layer.shapeFill + ':' + layer.shapeStroke + ':' + layer.shapeStrokeWidth.toString())
              if (this.shapeDragging) {
              if (this.shapeToolType() === ShapeType.ELLIPSE) {
                Ellipse({
                  width: this.shapeDraftRect.width * this.artboardScale,
                  height: this.shapeDraftRect.height * this.artboardScale
                })
                  .position({
                    x: this.shapeDraftRect.x * this.artboardScale,
                    y: this.shapeDraftRect.y * this.artboardScale
                  })
                  .fill(colorWithAlpha(this.foregroundColorValue, 0.5))
                  .stroke(ACCENT_WARM)
                  .strokeWidth(Math.max(1, this.shapeDraftRect.width * this.artboardScale * 0.03))
                  .hitTestBehavior(HitTestMode.None)
                  .id('shape-draft-ellipse')
              } else {
                Rect({
                  width: this.shapeDraftRect.width * this.artboardScale,
                  height: this.shapeDraftRect.height * this.artboardScale
                })
                  .position({
                    x: this.shapeDraftRect.x * this.artboardScale,
                    y: this.shapeDraftRect.y * this.artboardScale
                  })
                  .fill(colorWithAlpha(this.foregroundColorValue, 0.5))
                  .stroke(ACCENT_WARM)
                  .strokeWidth(Math.max(1, this.shapeDraftRect.width * this.artboardScale * 0.03))
                  .hitTestBehavior(HitTestMode.None)
                  .id('shape-draft-rectangle')
              }
              }
            }
          }
          .width(this.sourceArtboardWidth)
          .height(this.sourceArtboardHeight)
          .transform(this.documentMatrix)
            }
            this.selectionOverlay()
            this.brushOverlay()
            this.gradientOverlay()
            this.fillOverlay()
            this.cloneOverlay()
          }
      .width(this.outputArtboardWidth)
      .height(this.outputArtboardHeight)
      .clip(true)
        .borderRadius(3)
        .shadow({ radius: 18, color: '#55000000', offsetY: 8 })
      .scale({ x: this.zoom, y: this.zoom })
      .translate({ x: this.panX, y: this.panY })
      .id('document-artboard')
      Row({ space: 8 }) {
        Text('RGB / 8')
          .fontSize(10)
          .fontColor(TEXT_FAINT)
        Text('·')
          .fontSize(10)
          .fontColor(TEXT_FAINT)
        Text('100%')
          .fontSize(10)
          .fontColor(TEXT_FAINT)
      }
      .position({ x: 14, y: 12 })
    }
    .layoutWeight(1)
    .width('100%')
    .height('100%')
    .backgroundColor(CANVAS_BG)
    .clip(true)
  }

  @Builder
  adjustmentSlider(label: string, key: string, value: number, minimum: number, maximum: number,
    step: number, suffix: string) {
    Column({ space: 6 }) {
      Row() {
        Text(label)
          .fontSize(12)
          .fontColor(TEXT_MUTED)
        Blank()
        Text(formatAdjustment(key, value) + suffix)
          .fontSize(11)
          .fontColor(TEXT)
          .fontFamily('monospace')
      }
      .width('100%')
      Slider({ value: value, min: minimum, max: maximum, step: step })
        .selectedColor(ACCENT)
        .trackColor(PANEL_RAISED)
        .blockColor(ACCENT_WARM)
        .width('100%')
        .onChange((nextValue: number) => {
          this.updateAdjustment(key, nextValue);
        })
        .id('adjustment-' + key)
    }
    .width('100%')
  }

  @Builder
  shapePropertiesPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('SHAPE LAYER')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        Blank()
        Text(this.activeShapeLayer()?.shapeType === ShapeType.ELLIPSE ? 'Ellipse' : 'Rectangle')
          .fontSize(11)
          .fontColor(ACCENT)
      }
      .width('100%')
      this.shapeDimensionSlider('X', 'x')
      this.shapeDimensionSlider('Y', 'y')
      this.shapeDimensionSlider('Width', 'width')
      this.shapeDimensionSlider('Height', 'height')
      Row({ space: 8 }) {
        TextInput({ text: this.shapeFillValue, placeholder: '#RRGGBB' })
          .height(32)
          .layoutWeight(1)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT)
          .placeholderColor(TEXT_FAINT)
          .backgroundColor(PANEL_BG)
          .border({ width: 1, color: BORDER })
          .borderRadius(4)
          .maxLength(7)
          .id('shape-fill-input')
          .onChange((value: string) => {
            this.shapeFillValue = value;
          })
        Button('Fill')
          .width(58)
          .height(32)
          .fontSize(10)
          .fontColor(ACCENT)
          .backgroundColor(PANEL_BG)
          .borderRadius(4)
          .id('apply-shape-fill-button')
          .accessibilityText('Apply shape fill')
          .onClick(() => {
            this.applyShapeFill();
          })
      }
      .width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.shapeStrokeValue, placeholder: '#RRGGBB' })
          .height(32)
          .layoutWeight(1)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT)
          .placeholderColor(TEXT_FAINT)
          .backgroundColor(PANEL_BG)
          .border({ width: 1, color: BORDER })
          .borderRadius(4)
          .maxLength(7)
          .id('shape-stroke-input')
          .onChange((value: string) => {
            this.shapeStrokeValue = value;
          })
        Button('Stroke')
          .width(68)
          .height(32)
          .fontSize(10)
          .fontColor(ACCENT)
          .backgroundColor(PANEL_BG)
          .borderRadius(4)
          .id('apply-shape-stroke-button')
          .accessibilityText('Apply shape stroke')
          .onClick(() => {
            this.applyShapeStroke();
          })
      }
      .width('100%')
      Row() {
        Text('Stroke width')
          .fontSize(10)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.shapeStrokeWidthValue, min: 0, max: 24, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('shape-stroke-width-slider')
          .onChange((value: number) => {
            this.shapeStrokeWidthValue = value;
          })
        Text(this.shapeStrokeWidthValue.toString() + ' px')
          .width(42)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Button('Apply stroke width')
        .width('100%')
        .height(30)
        .fontSize(10)
        .fontColor(ACCENT)
        .backgroundColor(PANEL_BG)
        .borderRadius(4)
        .id('apply-shape-stroke-width-button')
        .onClick(() => {
          this.updateShapeStrokeWidth(this.shapeStrokeWidthValue);
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PANEL_RAISED)
    .borderRadius(7)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  brushPropertiesPanel() {
    Column({ space: 10 }) {
      Row() {
        Text(this.isEraserTool() ? 'ERASER' : this.isPencilTool() ? 'PENCIL' : 'BRUSH')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        Blank()
        Text(this.activePaintLayer() === undefined ? 'New strokes' : 'Selected stroke')
          .fontSize(11)
          .fontColor(ACCENT)
      }
      .width('100%')
      Row() {
        Text('Size')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.brushWidthValue, min: 1, max: 96, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('brush-size-slider')
          .onChange((value: number) => {
            this.applyBrushWidth(value);
          })
        Text(this.brushWidthValue.toString() + ' px')
          .width(48)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Color')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Blank()
        Circle({ width: 14, height: 14 })
          .fill(this.foregroundColorValue)
          .hitTestBehavior(HitTestMode.None)
        Text(this.foregroundColorValue)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT)
      }
      .width('100%')
      Text(this.isEraserTool() ?
        'Drag over the image to erase. A tap leaves a round eraser dab.' :
        this.isPencilTool() ?
          'Drag for a pixel-snapped pencil stroke. A tap leaves a round dab.' :
          'Drag on the artboard to paint. A tap leaves a round dab.')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
        .lineHeight(15)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PANEL_RAISED)
    .borderRadius(7)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  gradientPropertiesPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('GRADIENT')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        Blank()
        Text('Linear')
          .fontSize(11)
          .fontColor(ACCENT)
      }
      .width('100%')
      Row() {
        Text('Start')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Blank()
        Circle({ width: 14, height: 14 })
          .fill(this.gradientPrimaryInput)
          .hitTestBehavior(HitTestMode.None)
        Text(this.gradientPrimaryInput)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT)
      }
      .width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.gradientPrimaryInput, placeholder: '#RRGGBB' })
          .height(32)
          .layoutWeight(1)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT)
          .placeholderColor(TEXT_FAINT)
          .backgroundColor(PANEL_BG)
          .border({ width: 1, color: BORDER })
          .borderRadius(4)
          .maxLength(7)
          .id('gradient-start-color-input')
          .onChange((value: string) => {
            this.gradientPrimaryInput = value;
          })
        Button('Apply start')
          .width(86)
          .height(32)
          .fontSize(10)
          .fontColor(ACCENT)
          .backgroundColor(PANEL_BG)
          .borderRadius(4)
          .id('apply-gradient-start-color-button')
          .onClick(() => {
            this.applyGradientForegroundColor();
          })
      }
      .width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.gradientSecondaryInput, placeholder: '#RRGGBB' })
          .height(32)
          .layoutWeight(1)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT)
          .placeholderColor(TEXT_FAINT)
          .backgroundColor(PANEL_BG)
          .border({ width: 1, color: BORDER })
          .borderRadius(4)
          .maxLength(7)
          .id('gradient-end-color-input')
          .onChange((value: string) => {
            this.gradientSecondaryInput = value;
          })
        Button('Apply end')
          .width(86)
          .height(32)
          .fontSize(10)
          .fontColor(ACCENT)
          .backgroundColor(PANEL_BG)
          .borderRadius(4)
          .id('apply-gradient-end-color-button')
          .onClick(() => {
            this.applyGradientSecondaryColor();
          })
      }
      .width('100%')
      Row() {
        Text('Opacity')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.activeLayerOpacity, min: 0, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('gradient-opacity-slider')
          .onChange((value: number) => {
            this.updateLayerOpacity(value);
          })
        Text(this.activeLayerOpacity.toString() + '%')
          .width(38)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row({ space: 8 }) {
        Button(this.gradientReverse ? 'Reverse ✓' : 'Reverse')
          .layoutWeight(1)
          .height(32)
          .fontSize(10)
          .fontColor(this.gradientReverse ? ACCENT : TEXT_MUTED)
          .backgroundColor(PANEL_BG)
          .border({ width: 1, color: this.gradientReverse ? ACCENT : BORDER, radius: 4 })
          .id('reverse-gradient-button')
          .onClick(() => {
            this.toggleGradientReverse();
          })
        Button('Use background')
          .layoutWeight(1)
          .height(32)
          .fontSize(10)
          .fontColor(ACCENT)
          .backgroundColor(PANEL_BG)
          .border({ width: 1, color: BORDER, radius: 4 })
          .id('use-background-gradient-button')
          .onClick(() => {
            this.gradientSecondaryInput = this.backgroundColorValue;
            this.applyGradientSecondaryColor();
          })
      }
      .width('100%')
      Text(this.selectionActive ? 'Clipped to the active selection' : 'Fills the current crop')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
        .lineHeight(15)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PANEL_RAISED)
    .borderRadius(7)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  magicWandPropertiesPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('MAGIC WAND')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        Blank()
        Text(this.magicWandBusy ? 'Sampling…' : 'Color range')
          .fontSize(11)
          .fontColor(ACCENT)
      }
      .width('100%')
      Row() {
        Text('Tolerance')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.magicWandTolerance, min: 0, max: 128, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('magic-wand-tolerance-slider')
          .onChange((value: number) => {
            this.updateMagicWandTolerance(value);
          })
        Text(this.magicWandTolerance.toString())
          .width(34)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row({ space: 8 }) {
        Button(this.magicWandContiguous ? 'Contiguous ✓' : 'Contiguous')
          .layoutWeight(1)
          .height(32)
          .fontSize(10)
          .fontColor(this.magicWandContiguous ? ACCENT : TEXT_MUTED)
          .backgroundColor(PANEL_BG)
          .border({ width: 1, color: this.magicWandContiguous ? ACCENT : BORDER, radius: 4 })
          .id('magic-wand-contiguous-button')
          .onClick(() => {
            this.magicWandContiguous = !this.magicWandContiguous;
          })
      }
      .width('100%')
      Text('Tap the image to select a contiguous region of similar color.')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
        .lineHeight(15)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PANEL_RAISED)
    .borderRadius(7)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  fillPropertiesPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('PAINT BUCKET')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        Blank()
        Text('Flood fill')
          .fontSize(11)
          .fontColor(ACCENT)
      }
      .width('100%')
      Row() {
        Text('Color')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Blank()
        Circle({ width: 14, height: 14 })
          .fill(this.foregroundColorValue)
          .hitTestBehavior(HitTestMode.None)
        Text(this.foregroundColorValue)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT)
      }
      .width('100%')
      Row() {
        Text('Tolerance')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.fillToleranceValue, min: 0, max: 255, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('fill-tolerance-slider')
          .onChange((value: number) => {
            this.updateFillTolerance(value);
          })
        Text(this.fillToleranceValue.toString())
          .width(34)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row({ space: 8 }) {
        Button(this.fillContiguousValue ? 'Contiguous ✓' : 'Contiguous')
          .layoutWeight(1)
          .height(32)
          .fontSize(10)
          .fontColor(this.fillContiguousValue ? ACCENT : TEXT_MUTED)
          .backgroundColor(PANEL_BG)
          .border({ width: 1, color: this.fillContiguousValue ? ACCENT : BORDER, radius: 4 })
          .id('fill-contiguous-button')
          .onClick(() => {
            this.toggleFillContiguous();
          })
        Button(this.fillAntialiasValue ? 'Anti-alias ✓' : 'Anti-alias')
          .layoutWeight(1)
          .height(32)
          .fontSize(10)
          .fontColor(this.fillAntialiasValue ? ACCENT : TEXT_MUTED)
          .backgroundColor(PANEL_BG)
          .border({ width: 1, color: this.fillAntialiasValue ? ACCENT : BORDER, radius: 4 })
          .id('fill-antialias-button')
          .onClick(() => {
            this.toggleFillAntialias();
          })
      }
      .width('100%')
      Row() {
        Text('Opacity')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.activeLayerOpacity, min: 0, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('fill-opacity-slider')
          .onChange((value: number) => {
            this.updateLayerOpacity(value);
          })
        Text(this.activeLayerOpacity.toString() + '%')
          .width(38)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Text(this.selectionActive ? 'Clipped to the active selection' : 'Tap a region to fill')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
        .lineHeight(15)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PANEL_RAISED)
    .borderRadius(7)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  blurPropertiesPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('BLUR')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        Blank()
        Text('Source retouch')
          .fontSize(11)
          .fontColor(ACCENT)
      }
      .width('100%')
      Row() {
        Text('Size')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.brushWidthValue, min: 1, max: 96, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('blur-size-slider')
          .onChange((value: number) => {
            this.applyBrushWidth(value);
          })
        Text(this.brushWidthValue.toString() + ' px')
          .width(48)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Strength')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.retouchStrengthValue, min: 1, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('blur-strength-slider')
          .onChange((value: number) => {
            this.applyRetouchStrength(value);
          })
        Text(this.retouchStrengthValue.toString() + '%')
          .width(42)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Opacity')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.activeLayerOpacity, min: 0, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('blur-opacity-slider')
          .onChange((value: number) => {
            this.updateLayerOpacity(value);
          })
        Text(this.activeLayerOpacity.toString() + '%')
          .width(38)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Text(this.selectionActive ? 'Clipped to the active selection' :
        'Drag over the image to blur a source-space stroke.')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
        .lineHeight(15)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PANEL_RAISED)
    .borderRadius(7)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  sharpenPropertiesPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('SHARPEN')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        Blank()
        Text('Source retouch')
          .fontSize(11)
          .fontColor(ACCENT)
      }
      .width('100%')
      Row() {
        Text('Size')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.brushWidthValue, min: 1, max: 96, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('sharpen-size-slider')
          .onChange((value: number) => {
            this.applyBrushWidth(value);
          })
        Text(this.brushWidthValue.toString() + ' px')
          .width(48)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Strength')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.retouchStrengthValue, min: 1, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('sharpen-strength-slider')
          .onChange((value: number) => {
            this.applyRetouchStrength(value);
          })
        Text(this.retouchStrengthValue.toString() + '%')
          .width(42)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Opacity')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.activeLayerOpacity, min: 0, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('sharpen-opacity-slider')
          .onChange((value: number) => {
            this.updateLayerOpacity(value);
          })
        Text(this.activeLayerOpacity.toString() + '%')
          .width(38)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Text(this.selectionActive ? 'Clipped to the active selection' :
        'Drag over the image to sharpen a source-space stroke.')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
        .lineHeight(15)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PANEL_RAISED)
    .borderRadius(7)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  smudgePropertiesPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('SMUDGE')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        Blank()
        Text('Source retouch')
          .fontSize(11)
          .fontColor(ACCENT)
      }
      .width('100%')
      Row() {
        Text('Size')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.brushWidthValue, min: 1, max: 96, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('smudge-size-slider')
          .onChange((value: number) => {
            this.applyBrushWidth(value);
          })
        Text(this.brushWidthValue.toString() + ' px')
          .width(48)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Strength')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.retouchStrengthValue, min: 1, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('smudge-strength-slider')
          .onChange((value: number) => {
            this.applyRetouchStrength(value);
          })
        Text(this.retouchStrengthValue.toString() + '%')
          .width(42)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Opacity')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.activeLayerOpacity, min: 0, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('smudge-opacity-slider')
          .onChange((value: number) => {
            this.updateLayerOpacity(value);
          })
        Text(this.activeLayerOpacity.toString() + '%')
          .width(38)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Text(this.selectionActive ? 'Clipped to the active selection' :
        'Drag over the image to smudge a source-space stroke.')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
        .lineHeight(15)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PANEL_RAISED)
    .borderRadius(7)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  spongePropertiesPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('SPONGE')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        Blank()
        Text('Source retouch')
          .fontSize(11)
          .fontColor(ACCENT)
      }
      .width('100%')
      Row({ space: 6 }) {
        Button(this.spongeModeValue === 0 ? 'Desaturate ✓' : 'Desaturate')
          .layoutWeight(1)
          .height(30)
          .fontSize(10)
          .fontColor(this.spongeModeValue === 0 ? ACCENT : TEXT_MUTED)
          .backgroundColor(PANEL_BG)
          .border({ width: 1, color: this.spongeModeValue === 0 ? ACCENT : BORDER, radius: 4 })
          .id('sponge-desaturate-button')
          .onClick(() => {
            this.applySpongeMode(0);
          })
        Button(this.spongeModeValue === 1 ? 'Saturate ✓' : 'Saturate')
          .layoutWeight(1)
          .height(30)
          .fontSize(10)
          .fontColor(this.spongeModeValue === 1 ? ACCENT : TEXT_MUTED)
          .backgroundColor(PANEL_BG)
          .border({ width: 1, color: this.spongeModeValue === 1 ? ACCENT : BORDER, radius: 4 })
          .id('sponge-saturate-button')
          .onClick(() => {
            this.applySpongeMode(1);
          })
      }
      .width('100%')
      Row() {
        Text('Size')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.brushWidthValue, min: 1, max: 96, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('sponge-size-slider')
          .onChange((value: number) => {
            this.applyBrushWidth(value);
          })
        Text(this.brushWidthValue.toString() + ' px')
          .width(48)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Flow')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.retouchStrengthValue, min: 1, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('sponge-flow-slider')
          .onChange((value: number) => {
            this.applyRetouchStrength(value);
          })
        Text(this.retouchStrengthValue.toString() + '%')
          .width(42)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Opacity')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.activeLayerOpacity, min: 0, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('sponge-opacity-slider')
          .onChange((value: number) => {
            this.updateLayerOpacity(value);
          })
        Text(this.activeLayerOpacity.toString() + '%')
          .width(38)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Text(this.selectionActive ? 'Clipped to the active selection' :
        'Drag over the image to saturate or desaturate a source-space stroke.')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
        .lineHeight(15)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PANEL_RAISED)
    .borderRadius(7)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  spotHealPropertiesPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('SPOT HEALING')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        Blank()
        Text('Content aware')
          .fontSize(11)
          .fontColor(ACCENT)
      }
      .width('100%')
      Row() {
        Text('Size')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.brushWidthValue, min: 1, max: 96, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('spot-heal-size-slider')
          .onChange((value: number) => {
            this.applyBrushWidth(value);
          })
        Text(this.brushWidthValue.toString() + ' px')
          .width(48)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Flow')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.retouchStrengthValue, min: 1, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('spot-heal-flow-slider')
          .onChange((value: number) => {
            this.applyRetouchStrength(value);
          })
        Text(this.retouchStrengthValue.toString() + '%')
          .width(42)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Opacity')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.activeLayerOpacity, min: 0, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('spot-heal-opacity-slider')
          .onChange((value: number) => {
            this.updateLayerOpacity(value);
          })
        Text(this.activeLayerOpacity.toString() + '%')
          .width(38)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Text(this.selectionActive ? 'Clipped to the active selection' :
        'Paint over a blemish to replace it with matching texture.')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
        .lineHeight(15)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PANEL_RAISED)
    .borderRadius(7)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  redEyePropertiesPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('RED EYE')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        Blank()
        Text('Source retouch')
          .fontSize(11)
          .fontColor(ACCENT)
      }
      .width('100%')
      Row() {
        Text('Size')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.brushWidthValue, min: 1, max: 96, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('red-eye-size-slider')
          .onChange((value: number) => {
            this.applyBrushWidth(value);
          })
        Text(this.brushWidthValue.toString() + ' px')
          .width(48)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Flow')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.retouchStrengthValue, min: 1, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('red-eye-flow-slider')
          .onChange((value: number) => {
            this.applyRetouchStrength(value);
          })
        Text(this.retouchStrengthValue.toString() + '%')
          .width(42)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Opacity')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.activeLayerOpacity, min: 0, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('red-eye-opacity-slider')
          .onChange((value: number) => {
            this.updateLayerOpacity(value);
          })
        Text(this.activeLayerOpacity.toString() + '%')
          .width(38)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Text(this.selectionActive ? 'Clipped to the active selection' :
        'Paint over an eye to pull the red out toward the sclera tone.')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
        .lineHeight(15)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PANEL_RAISED)
    .borderRadius(7)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  dodgeBurnPropertiesPanel() {
    Column({ space: 10 }) {
      Row() {
        Text(this.activeDodgeBurnMode() === PaintMode.DODGE ? 'DODGE' : 'BURN')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        Blank()
        Text('Tone retouch')
          .fontSize(11)
          .fontColor(ACCENT)
      }
      .width('100%')
      Row({ space: 5 }) {
        Button(this.retouchRangeValue === 0 ? 'Shadows ✓' : 'Shadows')
          .layoutWeight(1)
          .height(30)
          .fontSize(9)
          .fontColor(this.retouchRangeValue === 0 ? ACCENT : TEXT_MUTED)
          .backgroundColor(PANEL_BG)
          .border({ width: 1, color: this.retouchRangeValue === 0 ? ACCENT : BORDER, radius: 4 })
          .id('dodge-burn-shadows-button')
          .onClick(() => {
            this.applyRetouchRange(0);
          })
        Button(this.retouchRangeValue === 1 ? 'Midtones ✓' : 'Midtones')
          .layoutWeight(1)
          .height(30)
          .fontSize(9)
          .fontColor(this.retouchRangeValue === 1 ? ACCENT : TEXT_MUTED)
          .backgroundColor(PANEL_BG)
          .border({ width: 1, color: this.retouchRangeValue === 1 ? ACCENT : BORDER, radius: 4 })
          .id('dodge-burn-midtones-button')
          .onClick(() => {
            this.applyRetouchRange(1);
          })
        Button(this.retouchRangeValue === 2 ? 'Highlights ✓' : 'Highlights')
          .layoutWeight(1)
          .height(30)
          .fontSize(9)
          .fontColor(this.retouchRangeValue === 2 ? ACCENT : TEXT_MUTED)
          .backgroundColor(PANEL_BG)
          .border({ width: 1, color: this.retouchRangeValue === 2 ? ACCENT : BORDER, radius: 4 })
          .id('dodge-burn-highlights-button')
          .onClick(() => {
            this.applyRetouchRange(2);
          })
      }
      .width('100%')
      Row() {
        Text('Exposure')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.retouchStrengthValue, min: 0, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('dodge-burn-exposure-slider')
          .onChange((value: number) => {
            this.applyRetouchStrength(value);
          })
        Text(this.retouchStrengthValue.toString() + '%')
          .width(42)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Size')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.brushWidthValue, min: 1, max: 96, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('dodge-burn-size-slider')
          .onChange((value: number) => {
            this.applyBrushWidth(value);
          })
        Text(this.brushWidthValue.toString() + ' px')
          .width(48)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Opacity')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.activeLayerOpacity, min: 0, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('dodge-burn-opacity-slider')
          .onChange((value: number) => {
            this.updateLayerOpacity(value);
          })
        Text(this.activeLayerOpacity.toString() + '%')
          .width(38)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Text(this.selectionActive ? 'Clipped to the active selection' :
        'Drag over the image to adjust tones in the selected range.')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
        .lineHeight(15)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PANEL_RAISED)
    .borderRadius(7)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  clonePropertiesPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('CLONE STAMP')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        Blank()
        Text(this.cloneSourcePoint === undefined ? 'Set source' : 'Source set')
          .fontSize(11)
          .fontColor(ACCENT)
      }
      .width('100%')
      Text(this.cloneSourcePoint === undefined ?
        'Tap the source point, then tap or drag on the destination.' :
        'Tap or drag the destination to clone from the marked source.')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
        .lineHeight(15)
        .width('100%')
      Row() {
        Text('Size')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.brushWidthValue, min: 1, max: 96, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_BG)
          .blockColor(ACCENT_WARM)
          .id('clone-size-slider')
          .onChange((value: number) => {
            this.applyBrushWidth(value);
          })
        Text(this.brushWidthValue.toString() + ' px')
          .width(48)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Text(this.selectionActive ? 'Clipped to the active selection' : 'Clones the current crop')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
        .lineHeight(15)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PANEL_RAISED)
    .borderRadius(7)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  propertiesPanel() {
    Column({ space: 14 }) {
      Row() {
        Text('Properties')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT)
        Blank()
        Text('Non-destructive')
          .fontSize(10)
      .fontColor(ACCENT)
      }
      .width('100%')

      if (this.isDodgeBurnTool() || this.activeDodgeBurnLayer() !== undefined) {
        this.dodgeBurnPropertiesPanel()
      }
      if (this.isRedEyeTool() || this.activeRedEyeLayer() !== undefined) {
        this.redEyePropertiesPanel()
      }
      if (this.isSpotHealTool() || this.activeSpotHealLayer() !== undefined) {
        this.spotHealPropertiesPanel()
      }

      Column({ space: 12 }) {
        Text('LIGHT & COLOR')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        this.adjustmentSlider('Exposure', 'exposure', this.exposure, -100, 100, 1, '')
        this.adjustmentSlider('Contrast', 'contrast', this.contrastValue, -100, 100, 1, '')
        this.adjustmentSlider('Saturation', 'saturation', this.saturation, -100, 100, 1, '')
        this.adjustmentSlider('Temperature', 'temperature', this.temperature, -100, 100, 1, '')
        this.adjustmentSlider('Blur', 'blur', this.blurValue, 0, 24, 0.5, '')
      }
      .width('100%')
      .padding(12)
      .backgroundColor(PANEL_RAISED)
      .borderRadius(7)
      .border({ width: 1, color: BORDER })

      Button('Reset adjustments')
        .width('100%')
        .height(34)
        .fontSize(12)
        .fontColor(TEXT_MUTED)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: BORDER, radius: 5 })
        .onClick(() => {
          this.controller.store.resetAdjustments();
          this.syncState();
        })

      Column({ space: 10 }) {
        Row() {
          Text('CROP')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_FAINT)
          Blank()
          Text(this.cropDraftRect.width.toString() + ' × ' + this.cropDraftRect.height.toString())
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor(TEXT_MUTED)
        }
        .width('100%')
        Flex({ wrap: FlexWrap.Wrap, space: {
          main: LengthMetrics.vp(6),
          cross: LengthMetrics.vp(6)
        } }) {
          this.cropAspectButton('free', 'Free')
          this.cropAspectButton('square', '1:1')
          this.cropAspectButton('fourThree', '4:3')
          this.cropAspectButton('sixteenNine', '16:9')
        }
        .width('100%')
        this.cropDimensionSlider('X', 'x')
        this.cropDimensionSlider('Y', 'y')
        this.cropDimensionSlider('Width', 'width')
        this.cropDimensionSlider('Height', 'height')
        Row({ space: 8 }) {
          Button('Apply crop')
            .layoutWeight(1)
            .height(34)
            .fontSize(11)
            .fontColor('#102321')
            .backgroundColor(ACCENT)
            .borderRadius(5)
            .id('apply-crop-button')
            .accessibilityText('Apply crop')
            .onClick(() => {
              this.applyCropDraft();
            })
          Button('Reset')
            .width(80)
            .height(34)
            .fontSize(10)
            .fontColor(TEXT_MUTED)
            .backgroundColor(PANEL_RAISED)
            .borderRadius(5)
            .id('reset-crop-button')
            .accessibilityText('Reset crop')
            .onClick(() => {
              this.resetCropDraft();
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(12)
      .backgroundColor(PANEL_RAISED)
      .borderRadius(7)
      .border({ width: 1, color: BORDER })

      Column({ space: 10 }) {
        Row() {
          Text('SELECTION')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_FAINT)
          Blank()
          Text(this.selectionActive ? 'Active' : 'None')
            .fontSize(11)
            .fontColor(this.selectionActive ? ACCENT : TEXT_MUTED)
        }
        .width('100%')
        Row({ space: 8 }) {
          Button('Select all')
            .layoutWeight(1)
            .height(34)
            .fontSize(10)
            .fontColor(ACCENT)
            .backgroundColor(PANEL_RAISED)
            .borderRadius(5)
            .id('select-all-button')
            .accessibilityText('Select all document')
            .onClick(() => {
              this.selectAll();
            })
          Button('Deselect')
            .layoutWeight(1)
            .height(34)
            .fontSize(10)
            .fontColor(TEXT_MUTED)
            .backgroundColor(PANEL_RAISED)
            .borderRadius(5)
            .enabled(this.selectionActive)
            .id('deselect-button')
            .accessibilityText('Deselect all')
            .onClick(() => {
              this.deselect();
            })
        }
        .width('100%')
        Button('Crop to selection')
          .width('100%')
          .height(34)
          .fontSize(11)
          .fontColor('#102321')
          .backgroundColor(this.selectionActive ? ACCENT : PANEL_RAISED)
          .borderRadius(5)
          .enabled(this.selectionActive)
          .id('crop-to-selection-button')
          .accessibilityText('Crop document to current selection')
          .onClick(() => {
            this.cropToSelection();
          })
        if (this.selectionActive) {
          Text(this.selectionRect.x.toString() + ', ' + this.selectionRect.y.toString() + '  ·  ' +
            this.selectionRect.width.toString() + ' × ' + this.selectionRect.height.toString() +
            (this.controller.store.document.selection.mode === 'lasso' ? '  ·  Lasso' : ''))
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor(TEXT_MUTED)
        }
        Row() {
          Text('Modify by')
            .fontSize(10)
            .fontColor(TEXT_MUTED)
          Slider({ value: this.selectionModifyAmount, min: 1, max: 48, step: 1 })
            .layoutWeight(1)
            .selectedColor(ACCENT)
            .trackColor(PANEL_BG)
            .blockColor(ACCENT_WARM)
            .id('selection-modify-amount-slider')
            .onChange((value: number) => {
              this.selectionModifyAmount = value;
            })
          Text(this.selectionModifyAmount.toString() + ' px')
            .width(42)
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor(TEXT_MUTED)
        }
        .width('100%')
        Row({ space: 8 }) {
          Button('Expand')
            .layoutWeight(1)
            .height(32)
            .fontSize(10)
            .fontColor(ACCENT)
            .backgroundColor(PANEL_RAISED)
            .borderRadius(5)
            .enabled(this.selectionActive)
            .id('expand-selection-button')
            .accessibilityText('Expand selection')
            .onClick(() => {
              this.expandSelection();
            })
          Button('Contract')
            .layoutWeight(1)
            .height(32)
            .fontSize(10)
            .fontColor(ACCENT)
            .backgroundColor(PANEL_RAISED)
            .borderRadius(5)
            .enabled(this.selectionActive)
            .id('contract-selection-button')
            .accessibilityText('Contract selection')
            .onClick(() => {
              this.contractSelection();
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(12)
      .backgroundColor(PANEL_RAISED)
      .borderRadius(7)
      .border({ width: 1, color: BORDER })

      Column({ space: 10 }) {
        Row() {
          Text('TRANSFORM')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_FAINT)
          Blank()
          Text(this.documentRotation.toString() + '°')
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor(TEXT_MUTED)
        }
        .width('100%')
        Flex({ wrap: FlexWrap.Wrap, space: {
          main: LengthMetrics.vp(8),
          cross: LengthMetrics.vp(8)
        } }) {
          Button('↻ Rotate 90°')
            .height(34)
            .fontSize(11)
            .fontColor(TEXT)
            .backgroundColor(PANEL_RAISED)
            .border({ width: 1, color: BORDER, radius: 5 })
            .id('rotate-document-button')
            .accessibilityText('Rotate document 90 degrees clockwise')
            .onClick(() => {
              this.rotateDocument();
            })
          Button(this.documentFlipHorizontal ? '↔ Flip horizontal ✓' : '↔ Flip horizontal')
            .height(34)
            .fontSize(11)
            .fontColor(TEXT)
            .backgroundColor(PANEL_RAISED)
            .border({ width: 1, color: this.documentFlipHorizontal ? ACCENT : BORDER, radius: 5 })
            .id('flip-horizontal-button')
            .accessibilityText('Flip document horizontally')
            .onClick(() => {
              this.flipDocumentHorizontal();
            })
          Button(this.documentFlipVertical ? '↕ Flip vertical ✓' : '↕ Flip vertical')
            .height(34)
            .fontSize(11)
            .fontColor(TEXT)
            .backgroundColor(PANEL_RAISED)
            .border({ width: 1, color: this.documentFlipVertical ? ACCENT : BORDER, radius: 5 })
            .id('flip-vertical-button')
            .accessibilityText('Flip document vertically')
            .onClick(() => {
              this.flipDocumentVertical();
            })
          Button('↺ Reset')
            .height(34)
            .fontSize(11)
            .fontColor(TEXT_MUTED)
            .backgroundColor(PANEL_RAISED)
            .border({ width: 1, color: BORDER, radius: 5 })
            .id('reset-transform-button')
            .accessibilityText('Reset document transform')
            .onClick(() => {
              this.resetDocumentTransform();
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(12)
      .backgroundColor(PANEL_RAISED)
      .borderRadius(7)
      .border({ width: 1, color: BORDER })

      if (this.activeTextLayer() !== undefined) {
        this.textPropertiesPanel()
      }
      if (this.activeShapeLayer() !== undefined) {
        this.shapePropertiesPanel()
      }
      if (this.isMagicWandTool()) {
        this.magicWandPropertiesPanel()
      } else if (this.isFillTool() || this.activeFillLayer() !== undefined) {
        this.fillPropertiesPanel()
      } else if (this.isBlurTool() || this.activeBlurLayer() !== undefined) {
        this.blurPropertiesPanel()
      } else if (this.isSharpenTool() || this.activeSharpenLayer() !== undefined) {
        this.sharpenPropertiesPanel()
      } else if (this.isSmudgeTool() || this.activeSmudgeLayer() !== undefined) {
        this.smudgePropertiesPanel()
      } else if (this.isSpongeTool() || this.activeSpongeLayer() !== undefined) {
        this.spongePropertiesPanel()
      } else if (this.isCloneTool() || this.activeCloneLayer() !== undefined) {
        this.clonePropertiesPanel()
      } else if (this.isGradientTool() || this.activeGradientLayer() !== undefined) {
        this.gradientPropertiesPanel()
      } else if (this.isBrushTool() || this.isPencilTool() || this.isEraserTool() ||
        (this.activePaintLayer() !== undefined && !this.isGradientTool() &&
          !this.isDodgeBurnTool() && this.activeDodgeBurnLayer() === undefined)) {
        this.brushPropertiesPanel()
      }

      Column({ space: 9 }) {
        Row() {
          Text('Document')
            .fontSize(12)
            .fontColor(TEXT_MUTED)
          Blank()
          Text(this.documentDirty ? 'Unsaved' : 'Saved')
            .fontSize(11)
            .fontColor(this.documentDirty ? ACCENT_WARM : ACCENT)
        }
        .width('100%')
        Text(this.documentWidth.toString() + ' × ' + this.documentHeight.toString() + ' px')
          .fontSize(11)
          .fontColor(TEXT_FAINT)
        Text('Source remains untouched while edits are non-destructive.')
          .fontSize(11)
          .fontColor(TEXT_FAINT)
          .lineHeight(16)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(PANEL_BG)
      .borderRadius(7)
      .border({ width: 1, color: BORDER })
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  filterPresetButton(preset: string, label: string) {
    Button() {
      Column({ space: 5 }) {
        Image($rawfile('sample_beach.jpg'))
          .width('100%')
          .height(54)
          .objectFit(ImageFit.Cover)
          .borderRadius(4)
          .colorFilter(this.presetColorFilter(preset))
        Text(label)
          .fontSize(10)
          .fontWeight(this.activeFilterPreset === preset ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.activeFilterPreset === preset ? TEXT : TEXT_MUTED)
          .maxLines(1)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width(142)
    .height(88)
    .padding(6)
    .backgroundColor(this.activeFilterPreset === preset ?
      colorWithAlpha(this.presetAccent(preset), 0.12) : PANEL_RAISED)
    .border({ width: this.activeFilterPreset === preset ? 1 : 0,
      color: this.presetAccent(preset) })
    .borderRadius(6)
    .id('filter-preset-' + preset.toLowerCase())
    .accessibilityText('Apply ' + label + ' filter')
    .onClick(() => {
      this.applyFilterPreset(preset);
    })
  }

  @Builder
  filtersPanel() {
    Column({ space: 14 }) {
      Row() {
        Text('Filters')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT)
        Blank()
        Text('Non-destructive')
          .fontSize(10)
          .fontColor(ACCENT)
      }
      .width('100%')

      Row({ space: 10 }) {
        Image($rawfile('sample_beach.jpg'))
          .width(82)
          .height(60)
          .objectFit(ImageFit.Cover)
          .borderRadius(5)
          .colorFilter(this.filterMatrixValue)
          .id('filter-live-preview')
        Column({ space: 3 }) {
          Text(filterPresetLabelFromKey(this.activeFilterPreset))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT)
          Text(this.filterIntensity.toString() + '% intensity')
            .fontSize(10)
            .fontColor(TEXT_FAINT)
          Text('Preview and export match')
            .fontSize(10)
            .fontColor(ACCENT)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(8)
      .backgroundColor(PANEL_RAISED)
      .borderRadius(7)
      .border({ width: 1, color: BORDER })

      Text('PRESETS')
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_FAINT)
      Flex({
        wrap: FlexWrap.Wrap,
        space: {
          main: LengthMetrics.vp(8),
          cross: LengthMetrics.vp(8)
        }
      }) {
        ForEach(FILTER_PRESET_KEYS, (preset: string, index: number) => {
          this.filterPresetButton(preset, FILTER_PRESET_NAMES[index])
        }, (preset: string) => preset)
      }
      .width('100%')

      Row() {
        Text('Intensity')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.filterIntensity, min: 0, max: 100, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_RAISED)
          .blockColor(ACCENT_WARM)
          .id('filter-intensity-slider')
          .onChange((value: number) => {
            this.updateFilterIntensity(value);
          })
        Text(this.filterIntensity.toString() + '%')
          .width(38)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')

      Button('Reset filters')
        .width('100%')
        .height(34)
        .fontSize(12)
        .fontColor(TEXT_MUTED)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: BORDER, radius: 5 })
        .id('reset-filters-button')
        .onClick(() => {
          this.resetFilter();
        })
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  layersPanel() {
    Column({ space: 12 }) {
      Row() {
        Text('Layers')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT)
        Blank()
        Text(this.layerRows.length.toString())
          .fontSize(11)
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      if (this.layerRows.length > 0) {
        Row({ space: 10 }) {
          Text('Mode')
            .fontSize(11)
            .fontColor(TEXT_MUTED)
          Button(this.activeLayerBlendMode)
            .height(30)
            .fontSize(11)
            .fontColor(TEXT)
            .backgroundColor(PANEL_RAISED)
            .border({ width: 1, color: BORDER, radius: 5 })
            .bindMenu(this.layerBlendModeMenu())
            .layoutWeight(1)
        }
        .width('100%')
        Row({ space: 10 }) {
          Text('Opacity')
            .fontSize(11)
            .fontColor(TEXT_MUTED)
          Slider({
            value: this.activeLayerOpacity,
            min: 0,
            max: 100,
            step: 1
          })
            .selectedColor(ACCENT)
            .trackColor(PANEL_RAISED)
            .blockColor(ACCENT_WARM)
            .layoutWeight(1)
            .onChange((value: number) => {
              this.updateLayerOpacity(value);
            })
          Text(Math.round(this.activeLayerOpacity).toString() + '%')
            .width(38)
            .fontSize(10)
            .fontFamily('monospace')
            .fontColor(TEXT_MUTED)
        }
        .width('100%')
      }
      ForEach(this.layerRows, (layer: LayerModel) => {
        Row({ space: 10 }) {
          Image(layer.kind === 'adjustment' ? $rawfile('gradient.svg') : $rawfile('sample_beach.jpg'))
            .width(34)
            .height(34)
            .objectFit(ImageFit.Cover)
            .borderRadius(4)
            .backgroundColor(layer.kind === 'adjustment' ? colorWithAlpha(ACCENT, 0.24) : PANEL_RAISED)
          Column({ space: 2 }) {
            Text(layer.name)
              .fontSize(12)
              .fontColor(TEXT)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(layer.kind === 'adjustment' ? 'Adjustment layer' : layer.kind === 'image' ?
              'Image layer' : layer.kind + ' layer')
              .fontSize(10)
              .fontColor(TEXT_FAINT)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text(layer.visible ? '●' : '○')
            .fontSize(16)
            .fontColor(layer.visible ? ACCENT : TEXT_FAINT)
            .onClick(() => {
              this.toggleLayerVisibility(layer.id);
            })
          Text(layer.locked ? '◆' : '◇')
            .fontSize(14)
            .fontColor(layer.locked ? ACCENT_WARM : TEXT_FAINT)
            .onClick(() => {
              this.toggleLayerLocked(layer.id);
            })
        }
        .width('100%')
        .height(58)
        .padding({ left: 8, right: 8 })
        .backgroundColor(layer.id === this.activeLayerId ?
          colorWithAlpha(ACCENT, 0.12) : PANEL_RAISED)
        .border({ width: layer.id === this.activeLayerId ? 1 : 0, color: ACCENT })
        .borderRadius(6)
        .id('layer-row-' + layer.id)
        .onClick(() => {
          this.selectLayer(layer.id);
        })
      }, (layer: LayerModel) => layer.id)
      Blank().layoutWeight(1)
      Row({ space: 6 }) {
        Button() {
          Stack() {
            Divider()
              .width(14)
              .height(2)
              .color(TEXT)
            Divider()
              .vertical(true)
              .width(2)
              .height(14)
              .color(TEXT)
          }
          .width(34)
          .height(34)
        }
          .width(34)
          .height(34)
          .backgroundColor(PANEL_RAISED)
          .borderRadius(5)
          .id('add-adjustment-layer-button')
          .accessibilityText('Add adjustment layer')
          .onClick(() => {
            this.addLayer();
          })
        Button('Duplicate')
          .layoutWeight(1)
          .height(34)
          .fontSize(10)
          .fontColor(TEXT_MUTED)
          .backgroundColor(PANEL_RAISED)
          .borderRadius(5)
          .onClick(() => {
            this.duplicateLayer(this.controller.store.selectedLayerId);
          })
        Button('Add text')
          .width(76)
          .height(34)
          .fontSize(9)
          .fontColor(ACCENT)
          .backgroundColor(PANEL_RAISED)
          .borderRadius(5)
          .accessibilityText('Add text layer')
          .onClick(() => {
            this.addTextLayer();
          })
        Button('Delete')
          .width(70)
          .height(34)
          .fontSize(9)
          .fontColor(ACCENT_WARM)
          .backgroundColor(PANEL_RAISED)
          .borderRadius(5)
          .onClick(() => {
            this.deleteLayer(this.controller.store.selectedLayerId);
          })
      }
      .width('100%')
      Row({ space: 8 }) {
        Button('Up')
          .layoutWeight(1)
          .height(30)
          .fontSize(10)
          .fontColor(TEXT_MUTED)
          .backgroundColor(PANEL_RAISED)
          .borderRadius(5)
          .onClick(() => {
            this.moveLayer(this.controller.store.selectedLayerId, -1);
          })
        Button('Down')
          .layoutWeight(1)
          .height(30)
          .fontSize(10)
          .fontColor(TEXT_MUTED)
          .backgroundColor(PANEL_RAISED)
          .borderRadius(5)
          .onClick(() => {
            this.moveLayer(this.controller.store.selectedLayerId, 1);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  textPropertiesPanel() {
    Column({ space: 10 }) {
      Row() {
        Text('TEXT LAYER')
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_FAINT)
        Blank()
        Text(this.activeTextLayer()?.name ?? 'Text')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      TextInput({ text: this.textDraft, placeholder: 'Text content' })
        .height(34)
        .fontSize(12)
        .fontColor(TEXT)
        .placeholderColor(TEXT_FAINT)
        .backgroundColor(PANEL_RAISED)
        .border({ width: 1, color: BORDER })
        .borderRadius(4)
        .maxLength(120)
        .id('text-content-input')
        .onChange((value: string) => {
          this.textDraft = value;
        })
        .onSubmit((enterKey: EnterKeyType, event: SubmitEvent) => {
          this.applyTextContent();
          event.keepEditableState();
        })
      Row({ space: 8 }) {
        Button('Apply text')
          .layoutWeight(1)
          .height(32)
          .fontSize(10)
          .fontColor(ACCENT)
          .backgroundColor(PANEL_RAISED)
          .borderRadius(4)
          .onClick(() => {
            this.applyTextContent();
          })
        Button('Apply color')
          .layoutWeight(1)
          .height(32)
          .fontSize(10)
          .fontColor(ACCENT)
          .backgroundColor(PANEL_RAISED)
          .borderRadius(4)
          .onClick(() => {
            this.applyTextColor();
          })
      }
      .width('100%')
      Row() {
        Text('Size')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.textSizeValue, min: 8, max: 120, step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_RAISED)
          .blockColor(ACCENT_WARM)
          .onChange((value: number) => {
            this.updateTextSize(value);
          })
        Text(this.textSizeValue.toString() + ' px')
          .width(42)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('X')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.textXValue, min: 0, max: Math.max(1, this.sourceCanvasWidth - 1), step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_RAISED)
          .blockColor(ACCENT_WARM)
          .onChange((value: number) => {
            this.updateTextX(value);
          })
        Text(this.textXValue.toString())
          .width(34)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row() {
        Text('Y')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
        Slider({ value: this.textYValue, min: 0, max: Math.max(1, this.sourceCanvasHeight - 1), step: 1 })
          .layoutWeight(1)
          .selectedColor(ACCENT)
          .trackColor(PANEL_RAISED)
          .blockColor(ACCENT_WARM)
          .onChange((value: number) => {
            this.updateTextY(value);
          })
        Text(this.textYValue.toString())
          .width(34)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.textColorValue, placeholder: '#RRGGBB' })
          .height(32)
          .layoutWeight(1)
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(TEXT)
          .placeholderColor(TEXT_FAINT)
          .backgroundColor(PANEL_RAISED)
          .border({ width: 1, color: BORDER })
          .borderRadius(4)
          .maxLength(7)
          .id('text-color-input')
          .onChange((value: string) => {
            this.textColorValue = value;
          })
        Button('Apply color')
          .width(88)
          .height(32)
          .fontSize(10)
          .fontColor(ACCENT)
          .backgroundColor(PANEL_RAISED)
          .borderRadius(4)
          .onClick(() => {
            this.applyTextColor();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(PANEL_RAISED)
    .borderRadius(7)
    .border({ width: 1, color: BORDER })
  }

  @Builder
  layerBlendModeMenu() {
    Menu() {
      ForEach(LAYER_BLEND_MODES, (mode: string) => {
        MenuItem({ content: mode })
          .onClick(() => {
            this.updateLayerBlendMode(mode);
          })
      }, (mode: string) => mode)
    }
  }

  @Builder
  historyPanel() {
    Column({ space: 12 }) {
      Row() {
        Text('History')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT)
        Blank()
        Text(this.controller.store.document.history.length.toString() + ' states')
          .fontSize(11)
          .fontColor(TEXT_MUTED)
      }
      .width('100%')
      ForEach(this.controller.store.document.history, (entry: HistoryEntry) => {
        Row({ space: 10 }) {
          Text(entry.kind === 'open' ? '●' : entry.kind === 'export' ? '↗' : '·')
            .fontSize(16)
            .fontColor(entry.kind === 'export' ? ACCENT_WARM : ACCENT)
          Column({ space: 2 }) {
            Text(entry.label)
              .fontSize(12)
              .fontColor(TEXT)
            Text(entry.detail)
              .fontSize(10)
              .fontColor(TEXT_FAINT)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text(entry.time)
            .fontSize(10)
            .fontColor(TEXT_FAINT)
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
        .id('history-entry-' + entry.id)
      }, (entry: HistoryEntry) => entry.id)
      Blank().layoutWeight(1)
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  colorPanel() {
    Column({ space: 12 }) {
      Text('Color')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT)
      Row({ space: 10 }) {
        this.colorSwatchButton(ColorTarget.FOREGROUND)
        this.colorSwatchButton(ColorTarget.BACKGROUND)
        Column({ space: 3 }) {
          Text(this.colorTarget.toString())
            .fontSize(12)
            .fontColor(TEXT)
          Text(this.colorInput)
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor(TEXT_MUTED)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      Text('HEX')
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_FAINT)
      Row({ space: 8 }) {
        TextInput({ text: this.colorInput, placeholder: '#RRGGBB' })
          .height(34)
          .layoutWeight(1)
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(TEXT)
          .placeholderColor(TEXT_FAINT)
          .backgroundColor(PANEL_RAISED)
          .border({ width: 1, color: BORDER })
          .borderRadius(4)
          .maxLength(7)
          .id('color-hex-input')
          .onChange((value: string) => {
            this.updateColorInput(value);
          })
        Button('Apply')
          .width(60)
          .height(34)
          .fontSize(10)
          .fontColor(ACCENT)
          .backgroundColor(PANEL_RAISED)
          .borderRadius(4)
          .accessibilityText('Apply hex color')
          .onClick(() => {
            this.applyColorInput();
          })
      }
      .width('100%')
      Text('SWATCHES')
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_FAINT)
      Flex({ wrap: FlexWrap.Wrap, space: {
        main: LengthMetrics.vp(8),
        cross: LengthMetrics.vp(8)
      } }) {
        ForEach(this.swatchColors, (color: string) => {
          Button() {
            Stack() {
              Text('')
                .width(30)
                .height(30)
                .backgroundColor(color)
                .border({ width: this.colorValueForTarget(this.colorTarget) === color ? 2 : 1,
                  color: this.colorValueForTarget(this.colorTarget) === color ? ACCENT : BORDER })
                .borderRadius(5)
            }
            .width(30)
            .height(30)
          }
          .width(34)
          .height(34)
          .backgroundColor(Color.Transparent)
          .accessibilityText('Select ' + color + ' swatch')
          .onClick(() => {
            this.selectColor(color);
          })
        }, (color: string) => color)
      }
      .width('100%')
      Row({ space: 8 }) {
        Button('Add swatch')
          .layoutWeight(1)
          .height(32)
          .fontSize(10)
          .fontColor(TEXT_MUTED)
          .backgroundColor(PANEL_RAISED)
          .borderRadius(4)
          .onClick(() => {
            this.addCurrentSwatch();
          })
        Button('Swap')
          .width(68)
          .height(32)
          .fontSize(10)
          .fontColor(TEXT_MUTED)
          .backgroundColor(PANEL_RAISED)
          .borderRadius(4)
          .onClick(() => {
            this.swapColors();
          })
        Button('Reset')
          .width(68)
          .height(32)
          .fontSize(10)
          .fontColor(TEXT_MUTED)
          .backgroundColor(PANEL_RAISED)
          .borderRadius(4)
          .onClick(() => {
            this.resetColors();
          })
      }
      .width('100%')
      Text('Foreground and background colors are available to paint and shape tools.')
        .fontSize(11)
        .fontColor(TEXT_FAINT)
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  colorSwatchButton(target: ColorTarget) {
    Button() {
      Stack() {
        Text('')
          .width(42)
          .height(42)
          .backgroundColor(this.colorValueForTarget(target))
          .border({ width: this.colorTarget === target ? 2 : 1,
            color: this.colorTarget === target ? ACCENT : BORDER })
          .borderRadius(6)
      }
      .width(42)
      .height(42)
    }
    .width(46)
    .height(46)
    .backgroundColor(Color.Transparent)
    .accessibilityText(target.toString() + ' color ' + this.colorValueForTarget(target))
    .onClick(() => {
      this.selectColorTarget(target);
    })
  }

  @Builder
  sidebar() {
    Column() {
      Row({ space: 0 }) {
        this.sidebarTabButton(SidebarTab.PROPERTIES, 'Properties')
        this.sidebarTabButton(SidebarTab.LAYERS, 'Layers')
        this.sidebarTabButton(SidebarTab.HISTORY, 'History')
        this.sidebarTabButton(SidebarTab.COLOR, 'Color')
        this.sidebarTabButton(SidebarTab.FILTERS, 'Filters')
      }
      .width('100%')
      .height(43)
      .backgroundColor(PANEL_BG)
      .border({ width: { bottom: 1 }, color: BORDER })
      .id('sidebar-tabs')
      Scroll() {
        if (this.sidebarTab === SidebarTab.PROPERTIES) {
          this.propertiesPanel()
        } else if (this.sidebarTab === SidebarTab.LAYERS) {
          this.layersPanel()
        } else if (this.sidebarTab === SidebarTab.HISTORY) {
          this.historyPanel()
        } else if (this.sidebarTab === SidebarTab.COLOR) {
          this.colorPanel()
        } else {
          this.filtersPanel()
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width(SIDEBAR_WIDTH)
    .height('100%')
    .backgroundColor(PANEL_BG)
    .border({ width: { left: 1 }, color: BORDER })
    .id('editor-sidebar')
  }

  @Builder
  sidebarTabButton(tab: SidebarTab, label: string) {
    Text(label)
      .fontSize(10)
      .fontColor(this.sidebarTab === tab ? ACCENT : TEXT_MUTED)
      .layoutWeight(1)
      .height(43)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.sidebarTab === tab ? PANEL_RAISED : Color.Transparent)
      .border({ width: { top: this.sidebarTab === tab ? 2 : 0 }, color: ACCENT })
      .id('sidebar-tab-' + tab.toString().toLowerCase())
      .onClick(() => {
        this.selectTab(tab);
      })
  }

  @Builder
  bottomStatus() {
    Row({ space: 12 }) {
      Text(this.status)
        .fontSize(10)
        .fontColor(TEXT_MUTED)
      Blank()
      Text('CPU')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
      Text('0%')
        .fontSize(10)
        .fontColor(TEXT_MUTED)
      Text('GPU')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
      Text('0%')
        .fontSize(10)
        .fontColor(TEXT_MUTED)
      Text('Doc')
        .fontSize(10)
        .fontColor(TEXT_FAINT)
      Text((this.zoom * 100).toFixed(0) + '%')
        .fontSize(10)
        .fontColor(TEXT_MUTED)
    }
    .width('100%')
    .height(28)
    .padding({ left: 16, right: 16 })
    .backgroundColor(PANEL_BG)
    .border({ width: { top: 1 }, color: BORDER })
  }

  @Builder
  mainCanvas() {
    Column() {
      this.canvasHeader()
      Row() {
        this.imagePreview()
        if (this.sidebarOpen) {
          this.sidebar()
        }
      }
      .layoutWeight(1)
      .width('100%')
      this.bottomStatus()
    }
    .layoutWeight(1)
    .height('100%')
  }

  @Builder
  compactOverlay() {
    Row({ space: 8 }) {
      Button('Layers')
        .height(34)
        .fontSize(11)
        .fontColor(TEXT)
        .backgroundColor(PANEL_RAISED)
        .borderRadius(5)
        .onClick(() => {
          this.sidebarOpen = !this.sidebarOpen;
          this.updatePreviewGeometry();
        })
      Text(this.sidebarOpen ? 'Hide panels' : 'Show panels')
        .fontSize(11)
        .fontColor(TEXT_MUTED)
    }
    .position({ x: this.viewportWidth - 170, y: 50 })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.topBar()
        Row() {
          this.toolRail()
          this.mainCanvas()
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(CANVAS_BG)
      if (this.isCompact() && this.sidebarOpen) {
        this.compactOverlay()
      }
      if (this.busy) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(ACCENT)
          Text(this.status)
            .fontSize(12)
            .fontColor(TEXT)
        }
        .width(190)
        .padding(20)
        .backgroundColor(PANEL_RAISED)
        .borderRadius(8)
        .shadow({ radius: 20, color: '#66000000' })
        .position({ x: this.viewportWidth / 2 - 95, y: this.viewportHeight / 2 - 55 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CANVAS_BG)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.viewportWidth = Number(newArea.width);
      this.viewportHeight = Number(newArea.height);
      this.updatePreviewGeometry();
    })
  }
}
