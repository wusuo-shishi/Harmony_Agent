import { AgentKind } from './AgentModels';

export class IntentResult {
  kind: AgentKind = AgentKind.General;
  label: string = '';
  hint: string = '';

  static of(kind: AgentKind, label: string, hint: string): IntentResult {
    const r = new IntentResult();
    r.kind = kind;
    r.label = label;
    r.hint = hint;
    return r;
  }
}

export class IntentRouter {
  private static readonly scheduleKeys: string[] = ['提醒', '日程', '日历', '组会', '会议', '安排', '记得'];
  private static readonly documentKeys: string[] = ['拍照', '拍一下', '照片', '图片', '拍摄', 'ocr', '扫描', '拍这个', '识图', '图里'];
  private static readonly learningKeys: string[] = ['知识库', '检索', '引用', '资料', '文档总结', '总结一下', '汇总'];

  static route(text: string): IntentResult {
    const t: string = text.toLowerCase();
    let bestKind: AgentKind = AgentKind.General;
    let bestScore: number = 0;

    let docScore: number = 0;
    for (let i = 0; i < IntentRouter.documentKeys.length; i++) {
      if (t.indexOf(IntentRouter.documentKeys[i]) >= 0) {
        docScore++;
      }
    }
    let schedScore: number = 0;
    for (let i = 0; i < IntentRouter.scheduleKeys.length; i++) {
      if (t.indexOf(IntentRouter.scheduleKeys[i]) >= 0) {
        schedScore++;
      }
    }
    let learnScore: number = 0;
    for (let i = 0; i < IntentRouter.learningKeys.length; i++) {
      if (t.indexOf(IntentRouter.learningKeys[i]) >= 0) {
        learnScore++;
      }
    }

    // 时间词可强化日程意图(如下午/明天/周X/点/半)
    if (t.indexOf('下午') >= 0 || t.indexOf('明天') >= 0 || t.indexOf('上午') >= 0 ||
      t.indexOf('周') >= 0 || t.indexOf('今天') >= 0 || t.indexOf('星期') >= 0) {
      schedScore++;
    }

    if (docScore >= 2 || (docScore >= 1 && t.indexOf('总结') >= 0)) {
      bestKind = AgentKind.Document;
      bestScore = 3;
    } else if (schedScore >= learnScore && schedScore >= docScore && schedScore > 0) {
      bestKind = AgentKind.Schedule;
      bestScore = 2;
    } else if (learnScore > 0) {
      bestKind = AgentKind.Learning;
      bestScore = 1;
    }

    if (bestKind === AgentKind.General) {
      return IntentResult.of(AgentKind.General, '通用对话', '直接对话大模型');
    }
    if (bestKind === AgentKind.Schedule) {
      return IntentResult.of(AgentKind.Schedule, '日程管家', '从自然语言提取时间/事项并写入日历');
    }
    if (bestKind === AgentKind.Document) {
      return IntentResult.of(AgentKind.Document, '文档处理', '拍照/取图→OCR→总结要点(可存入知识库)');
    }
    return IntentResult.of(AgentKind.Learning, '学习助手', '检索知识库并以大模型生成带引用的回答');
  }
}
