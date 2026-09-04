export enum ChainStepKind {
  Document = 'document',
  Schedule = 'schedule',
  Learning = 'learning'
}

export class ChainPlan {
  steps: ChainStepKind[] = [];
  rationale: string = '';

  static of(steps: ChainStepKind[], rationale: string): ChainPlan {
    const plan = new ChainPlan();
    plan.steps = steps;
    plan.rationale = rationale;
    return plan;
  }
}

export class ChainPlanner {
  private static readonly docKeys: string[] = ['拍照', '拍一下', '识图', '图片', '照片', '扫描', 'ocr', '识别'];
  private static readonly scheduleKeys: string[] = ['日程', '提醒', '安排', '日历', '待办', '组会', '会议', '记一下'];
  private static readonly bridgeWords: string[] = ['然后', '之后', '再', '并', '同时', '顺便', '总结后'];

  static plan(text: string): ChainPlan | undefined {
    const t: string = text.toLowerCase();
    let docHits: number = 0;
    for (let i = 0; i < ChainPlanner.docKeys.length; i++) {
      if (t.indexOf(ChainPlanner.docKeys[i]) >= 0) {
        docHits++;
      }
    }
    let schedHits: number = 0;
    for (let i = 0; i < ChainPlanner.scheduleKeys.length; i++) {
      if (t.indexOf(ChainPlanner.scheduleKeys[i]) >= 0) {
        schedHits++;
      }
    }
    let hasBridge: boolean = false;
    for (let i = 0; i < ChainPlanner.bridgeWords.length; i++) {
      if (t.indexOf(ChainPlanner.bridgeWords[i]) >= 0) {
        hasBridge = true;
        break;
      }
    }
    // 文档→日程:同时出现"取图/识别"与"日程动作",尤其有桥接词时最像复合任务
    if (docHits > 0 && schedHits > 0) {
      return ChainPlan.of([ChainStepKind.Document, ChainStepKind.Schedule],
        `复合指令:先文档处理,再把其中的日程待办写入(检测到桥接词:${hasBridge})`);
    }
    return undefined;
  }
}
