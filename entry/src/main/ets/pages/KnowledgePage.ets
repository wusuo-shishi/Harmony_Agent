import { KeyboardAvoidMode } from '@kit.ArkUI';
import { KnowledgeView } from '../common/KnowledgeView';
import { UiTheme } from '../common/UiTheme';

@Entry
@Component
struct KnowledgePage {
  aboutToAppear(): void {
    try {
      // 禁止系统整体上抬避让,避免顶部返回栏被顶出屏幕
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    } catch (err) {
    }
  }

  aboutToDisappear(): void {
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    } catch (err) {
    }
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(30)
          .fontColor('#FFFFFF')
          .width(34)
          .height(30)
          .textAlign(TextAlign.Center)
          .offset({ y: -2 })
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        Text('知识库')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .padding({ left: 10, right: 12, top: 14, bottom: 14 })
      .linearGradient({ angle: 135, colors: [[UiTheme.HdrA, 0.0], [UiTheme.HdrB, 1.0]] })
      .alignItems(VerticalAlign.Center)

      KnowledgeView({ embedded: false })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(UiTheme.Bg)
  }
}
