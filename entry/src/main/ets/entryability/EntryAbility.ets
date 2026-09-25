import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { EditorController } from '../model/EditorController';

const DOMAIN: number = 0x0A26;
const TAG: string = 'OpenPhotoSuiteAbility';

export default class EntryAbility extends UIAbility {
  controller: EditorController = new EditorController();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.controller.attachContext(this.context);
    hilog.info(DOMAIN, TAG, 'onCreate ability=%{public}s reason=%{public}d', want.abilityName ?? '',
      launchParam.launchReason);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed code=%{public}d message=%{public}s',
          error.code, error.message);
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }
}
