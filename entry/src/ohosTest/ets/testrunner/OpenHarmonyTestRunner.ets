import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import { hilog } from '@kit.PerformanceAnalysisKit';
import testsuite from '../test/List.test';

const DOMAIN: number = 0x0A28;
const TAG: string = 'OpenPhotoSuiteTestRunner';

export default class OpenPhotoSuiteTestRunner implements TestRunner {
  onPrepare(): void {
    hilog.info(DOMAIN, TAG, 'test runner prepared');
  }

  onRun(): void {
    const abilityDelegator: abilityDelegatorRegistry.AbilityDelegator =
      abilityDelegatorRegistry.getAbilityDelegator();
    const abilityDelegatorArguments: abilityDelegatorRegistry.AbilityDelegatorArgs =
      abilityDelegatorRegistry.getArguments();
    hilog.info(DOMAIN, TAG, 'running PhotoSuite editor tests');
    Hypium.hypiumTest(abilityDelegator, abilityDelegatorArguments, testsuite);
  }
}
