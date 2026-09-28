import { UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { queueOpenUri } from '../open/PendingFiles';

const DOMAIN: number = 0x0A25;
const TAG: string = 'PhotoSuiteAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'PhotoSuite EntryAbility created.');
    queueOpenUri(want?.uri);
  }

  onNewWant(want: Want): void {
    hilog.info(DOMAIN, TAG, 'New want, uri=%{public}s', want?.uri ?? '');
    queueOpenUri(want?.uri);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Window stage created.');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, TAG, 'Failed to load Index: %{public}s', JSON.stringify(err));
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Window stage destroyed.');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Moved to foreground.');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Moved to background.');
  }
}
