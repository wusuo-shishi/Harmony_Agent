import { VisionProvider } from './VisionProvider';

export class SampleVisionProvider implements VisionProvider {
  readonly providerName: string = 'OCR 模拟(内置文本样例)';

  private static readonly sampleText: string =
    '本周三下午 3 点在 A3-210 召开课程项目评审会,各小组汇报进展。' +
    '会议要求:1) 演示鸿蒙多模态个人助理的语音输入与知识库检索;2) 说明端侧 RAG 的引用溯源机制;' +
    '3) 提交下阶段任务分工与时间节点。请提前准备 5 分钟演示稿与真机。';

  available(): boolean {
    return false;
  }

  async recognizeImageUri(imageUri: string): Promise<string> {
    void imageUri;
    // 模拟器无 CoreVision OCR:返回内置示例文本以打通"选图→OCR→总结"全流程
    return SampleVisionProvider.sampleText;
  }
}
