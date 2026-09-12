import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const TAG = 'PerfLaunch';

export default class EntryAbility extends UIAbility {
  private launchStart: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.launchStart = Date.now();
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    // 接续恢复:冷启动且携带接续数据时,交由 UI 层恢复
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      this.pullContinuationPayload(want);
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 单实例热启动接续:同样写入 AppStorage,由 UI 层(Index)消费
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      this.pullContinuationPayload(want);
    }
  }

  private pullContinuationPayload(want: Want): void {
    try {
      const params: Record<string, Object> | undefined = want.parameters;
      const session: Object | undefined = params?.['agentSession'];
      if (session !== undefined) {
        AppStorage.setOrCreate<string>('restoredSession', `${session}`);
        // 通知已运行的 UI(单实例热启动)刷新会话
        this.context.eventHub.emit('continuationRestore');
        hilog.info(DOMAIN, TAG, 'Continuation payload received, %{public}d chars', `${session}`.length);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Restore continuation payload failed: %{public}s', JSON.stringify(err));
    }
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    try {
      const snapshot: string | undefined = AppStorage.get<string>('sessionSnapshot');
      const maxTransferChars: number = 30000;
      if (snapshot === undefined || snapshot.length === 0) {
        // 无可迁移会话也同意迁移(至少界面会带过去)
        hilog.info(DOMAIN, TAG, '%{public}s', 'onContinue: no session snapshot');
      } else if (snapshot.length > maxTransferChars) {
        // 超长会话不写入 want 参数,避免超出参数体积上限导致对端启动异常
        hilog.warn(DOMAIN, TAG, 'onContinue: snapshot too large(%{public}d), skip payload', snapshot.length);
      } else {
        wantParam['agentSession'] = snapshot;
        hilog.info(DOMAIN, TAG, 'onContinue: payload=%{public}d chars', snapshot.length);
      }
      return AbilityConstant.OnContinueResult.AGREE;
    } catch (err) {
      return AbilityConstant.OnContinueResult.REJECT;
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageCreate at %{public}d ms', Date.now() - this.launchStart);

    try {
      // 发布软键盘高度(px),供页面手动避让,避免系统"整体上抬"把顶栏顶出屏幕
      const win = windowStage.getMainWindowSync();
      win.on('keyboardHeightChange', (height: number) => {
        AppStorage.setOrCreate<number>('kbHeightPx', height);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'register keyboardHeightChange failed: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Index content loaded at %{public}d ms', Date.now() - this.launchStart);
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
