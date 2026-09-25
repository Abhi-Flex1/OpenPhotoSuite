import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN: number = 0x0A27;
const TAG: string = 'OpenPhotoSuiteTest';

export default class TestAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate ability=%{public}s', want.abilityName ?? '');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('testability/pages/Index', (error) => {
      if (error.code) {
        hilog.error(DOMAIN, TAG, 'test content load failed code=%{public}d', error.code);
      }
    });
  }
}
