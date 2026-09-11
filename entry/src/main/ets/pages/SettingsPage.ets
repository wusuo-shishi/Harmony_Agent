import { UserSettings } from '../core/UserSettings';
import { ProviderHub } from '../provider/ProviderHub';
import { CapabilityManager } from '../core/CapabilityManager';
import { UiTheme } from '../common/UiTheme';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct SettingsPage {
  @State agenticEnabled: boolean = false;
  @State retrievalTopK: number = 3;

  aboutToAppear(): void {
    UserSettings.load(getContext(this) as common.UIAbilityContext).then((): void => {
      this.agenticEnabled = UserSettings.agenticEnabled;
      this.retrievalTopK = UserSettings.retrievalTopK;
    }).catch((): void => {
    });
  }

  @Builder
  SettingTitle(title: string, detail: string) {
    Column() {
      Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(UiTheme.TextPrimary)
      Text(detail).fontSize(11).fontColor(UiTheme.TextSubtle).margin({ top: 3 })
    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
  }

  build() {
    Column() {
      Row() {
        Text('‹').fontSize(30).fontColor('#FFFFFF').width(40).onClick(() => {
          this.getUIContext().getRouter().back();
        })
        Text('设置').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').layoutWeight(1)
      }
      .width('100%').padding({ left: 12, right: 16, top: 16, bottom: 15 })
      .linearGradient({ angle: 135, colors: [[UiTheme.HdrA, 0.0], [UiTheme.HdrB, 1.0]] })

      Scroll() {
        Column({ space: 12 }) {
          Column() {
            Text('当前服务').fontSize(13).fontColor(UiTheme.TextSubtle).width('100%')
            Text(ProviderHub.llmProvider().providerName).fontSize(17).fontWeight(FontWeight.Bold)
              .fontColor(UiTheme.TextPrimary).width('100%').margin({ top: 6 })
            Text('服务凭证由安全配置模块管理，本页不会显示密钥。').fontSize(11)
              .fontColor(UiTheme.TextSubtle).width('100%').margin({ top: 4 })
          }.width('100%').padding(14).backgroundColor(UiTheme.Card).borderRadius(14)

          Row() {
            this.SettingTitle('智能体自主编排', '允许模型根据任务选择知识检索、图片识别和日程工具')
            Toggle({ type: ToggleType.Switch, isOn: this.agenticEnabled }).onChange((value: boolean) => {
              this.agenticEnabled = value;
              UserSettings.setAgentic(value);
            })
          }.width('100%').padding(14).backgroundColor(UiTheme.Card).borderRadius(14)

          Column() {
            Row() {
              this.SettingTitle('知识库召回数量', '数量越多，参考资料更丰富，但回答速度可能略慢')
              Text(`${this.retrievalTopK}`).fontSize(16).fontColor(UiTheme.Accent)
            }.width('100%')
            Slider({ value: this.retrievalTopK, min: 1, max: 5, step: 1 })
              .selectedColor(UiTheme.Accent).onChange((value: number) => {
                this.retrievalTopK = Math.round(value);
                UserSettings.setRetrievalTopK(this.retrievalTopK);
              })
          }.width('100%').padding(14).backgroundColor(UiTheme.Card).borderRadius(14)

          Column() {
            Text('设备能力').fontSize(15).fontWeight(FontWeight.Medium).fontColor(UiTheme.TextPrimary).width('100%')
            Text(`设备类型：${CapabilityManager.deviceType()}`).fontSize(12).fontColor(UiTheme.TextSubtle)
              .width('100%').margin({ top: 8 })
            Text(`语音识别：${CapabilityManager.supportsRealtimeAsr() ? '可尝试使用' : '不可用'}`)
              .fontSize(12).fontColor(UiTheme.TextSubtle).width('100%').margin({ top: 4 })
            Text(`系统日历：${CapabilityManager.supportsCalendar() ? '可尝试使用' : '使用模拟日程'}`)
              .fontSize(12).fontColor(UiTheme.TextSubtle).width('100%').margin({ top: 4 })
          }.width('100%').padding(14).backgroundColor(UiTheme.Card).borderRadius(14)
        }.width('100%').padding(14)
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(UiTheme.Bg)
  }
}
