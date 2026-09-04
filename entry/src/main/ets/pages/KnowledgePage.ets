import { KeyboardAvoidMode } from '@kit.ArkUI';
import { KnowledgeView } from '../common/KnowledgeView';

@Entry
@Component
struct KnowledgePage {
  aboutToAppear(): void {
    try {
      // 键盘弹出时压缩内容区,避免顶部标题栏被顶出屏幕
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } catch (err) {
    }
  }

  aboutToDisappear(): void {
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);
    } catch (err) {
    }
  }

  build() {
    Column() {
      Row() {
        Text('‹ 返回')
          .fontSize(15)
          .fontColor('#FFFFFF')
          .padding({ top: 6, bottom: 6, right: 10 })
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
      .padding({ left: 12, right: 12, top: 14, bottom: 14 })
      .backgroundColor('#0A59F7')
      .alignItems(VerticalAlign.Center)

      KnowledgeView({ embedded: false })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
  }
}
