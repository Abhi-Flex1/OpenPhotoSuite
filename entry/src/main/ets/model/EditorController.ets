import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { EditorStore } from './EditorStore';
import { EditorTool, ExportFormat, SidebarTab } from './EditorTypes';
import { decodeBundledSample, renderPreviewPixelMap } from '../platform/ImageFileService';

export class EditorController {
  readonly store: EditorStore;
  private context: common.UIAbilityContext | undefined = undefined;

  constructor() {
    this.store = new EditorStore();
  }

  attachContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  async openImage(): Promise<void> {
    if (this.context === undefined) {
      return;
    }
    await this.store.open(this.context);
  }

  async exportImage(format: ExportFormat = ExportFormat.JPEG): Promise<void> {
    if (this.context === undefined) {
      return;
    }
    await this.store.export(this.context, format);
  }

  async createPreviewPixelMap(): Promise<image.PixelMap | undefined> {
    if (this.context === undefined) {
      return undefined;
    }
    let source: image.PixelMap | undefined = undefined;
    let ownsSource: boolean = false;
    try {
      if (typeof this.store.document.source === 'string') {
        source = await decodeBundledSample(this.context);
        ownsSource = true;
      } else {
        source = this.store.document.source;
      }
      return await renderPreviewPixelMap(source, this.store.document.adjustments,
        this.store.document.filter, this.store.document.layers);
    } finally {
      if (ownsSource && source !== undefined) {
        try {
          await source.release();
        } catch (error) {
        }
      }
    }
  }

  async selectMagicWand(x: number, y: number, tolerance: number,
    contiguous: boolean): Promise<boolean> {
    if (this.context === undefined) {
      return false;
    }
    let source: image.PixelMap | undefined = undefined;
    let ownsSource: boolean = false;
    try {
      if (typeof this.store.document.source === 'string') {
        source = await decodeBundledSample(this.context);
        ownsSource = true;
      } else {
        source = this.store.document.source;
      }
      return await this.store.selectMagicWand(source, x, y, tolerance, contiguous);
    } finally {
      if (ownsSource && source !== undefined) {
        try {
          await source.release();
        } catch (error) {
        }
      }
    }
  }

  selectTool(tool: EditorTool): void {
    this.store.setTool(tool);
  }

  selectTab(tab: SidebarTab): void {
    this.store.setSidebarTab(tab);
  }
}
