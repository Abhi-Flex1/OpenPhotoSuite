import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NativeBridge } from '../bridge/TauriBridge';
import { TAURI_SHIM_JS } from '../bridge/TauriShim';
import { ResourceServer } from '../bridge/ResourceServer';
import { LocalHttpServer } from '../bridge/LocalHttpServer';

const DOMAIN: number = 0x0A25;
const TAG: string = 'PhotoSuiteIndex';

@Entry
@Component
struct Index {
  private context: common.UIAbilityContext =
    this.getUIContext().getHostContext() as common.UIAbilityContext;
  private bridge: NativeBridge = new NativeBridge(this.context);
  private server: ResourceServer = new ResourceServer(this.context);
  private http: LocalHttpServer = new LocalHttpServer(this.context);
  controller: webview.WebviewController = new webview.WebviewController();
  @State private pageUrl: string = '';
  @State private loadError: string = '';

  aboutToAppear(): void {
    this.bridge.setController(this.controller);
    this.http.start().then((port: number) => {
      hilog.info(DOMAIN, TAG, 'Local server on %{public}d', port);
      this.pageUrl = this.http.url();
    }).catch((err: Error) => {
      const message: string = err instanceof Error ? err.message : String(err);
      hilog.error(DOMAIN, TAG, 'Local server failed: %{public}s', message);
      this.loadError = message;
    });
  }

  build(): void {
    Column() {
      if (this.pageUrl.length > 0) {
        Web({
          src: this.pageUrl,
          controller: this.controller
        })
          .javaScriptAccess(true)
          .fileAccess(true)
          .domStorageAccess(true)
          .javaScriptProxy({
            object: this.bridge,
            name: 'nativeBridge',
            methodList: ['postMessage'],
            controller: this.controller
          })
          .onInterceptRequest((event): WebResourceResponse | null => {
            try {
              return this.server.answer(event.request.getRequestUrl());
            } catch (e) {
              hilog.warn(DOMAIN, TAG, 'Intercept failed.');
              return null;
            }
          })
          .onPageBegin((): void => {
            try {
              this.controller.runJavaScript(TAURI_SHIM_JS);
            } catch (e) {
              hilog.warn(DOMAIN, TAG, 'Shim injection failed.');
            }
          })
          .onConsole((event): boolean => {
            hilog.info(DOMAIN, TAG, 'console: %{public}s', event?.message ?? '');
            return false;
          })
          .width('100%')
          .height('100%')
          .backgroundColor('#15181A')
          .focusable(true)
          .defaultFocus(true)
      } else {
        Column() {
          if (this.loadError.length > 0) {
            Text('PhotoSuite failed to start its local server: ' + this.loadError)
              .fontColor('#F2F5F3')
              .padding(24)
          } else {
            Text('Starting PhotoSuite…')
              .fontColor('#9CA9A7')
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#15181A')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#15181A')
  }
}
