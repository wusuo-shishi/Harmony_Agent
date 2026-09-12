import { describe, it, expect } from '@ohos/hypium';
import { AgentKind } from '../main/ets/agent/AgentModels';
import { IntentResult } from '../main/ets/agent/IntentRouter';
import { IntentRouter } from '../main/ets/agent/IntentRouter';
import { ParsedSchedule } from '../main/ets/agent/ScheduleTextParser';
import { ScheduleTextParser } from '../main/ets/agent/ScheduleTextParser';
import { ChainPlan, ChainPlanner, ChainStepKind } from '../main/ets/agent/ChainPlanner';
import { AgentTools } from '../main/ets/agent/AgentTools';
import { ChatMessage, ChatRole } from '../main/ets/model/ChatModels';
import { SessionCodec } from '../main/ets/core/SessionCodec';

export default function agentUnitTest() {
  describe('IntentRouter', () => {
    it('scheduleKeywords_routeToSchedule', 0, () => {
      const r: IntentResult = IntentRouter.route('明天下午三点开组会提醒我');
      expect(r.kind).assertEqual(AgentKind.Schedule);
    });

    it('remindWord_routesToSchedule', 0, () => {
      const r: IntentResult = IntentRouter.route('提醒我写作业');
      expect(r.kind).assertEqual(AgentKind.Schedule);
    });

    it('photoKeyword_routesToDocument', 0, () => {
      const r: IntentResult = IntentRouter.route('拍一下这个文档帮我总结重点');
      expect(r.kind).assertEqual(AgentKind.Document);
    });

    it('photoWordWithoutSummary_alsoRoutesToDocument', 0, () => {
      const r: IntentResult = IntentRouter.route('拍照识图');
      expect(r.kind).assertEqual(AgentKind.Document);
    });

    it('knowledgeKeyword_routesToLearning', 0, () => {
      const r: IntentResult = IntentRouter.route('引用溯源是什么');
      expect(r.kind).assertEqual(AgentKind.Learning);
    });

    it('plainGreeting_routesToGeneral', 0, () => {
      const r: IntentResult = IntentRouter.route('你好');
      expect(r.kind).assertEqual(AgentKind.General);
    });

    it('mixedText_withDate_prioritizesSchedule', 0, () => {
      // 同时含「提醒/会议」(日程)与「资料」(学习),含时间词,日程信号更强应判日程
      const r: IntentResult = IntentRouter.route('明天下午提醒我整理会议资料');
      expect(r.kind).assertEqual(AgentKind.Schedule);
    });

    it('pureDigitOrSymbol_isTrivial', 0, () => {
      expect(IntentRouter.isTrivialQuery('1')).assertTrue();
      expect(IntentRouter.isTrivialQuery('123')).assertTrue();
      expect(IntentRouter.isTrivialQuery('!!!')).assertTrue();
      expect(IntentRouter.isTrivialQuery('  ')).assertTrue();
    });

    it('lettersOrCjk_notTrivial', 0, () => {
      expect(IntentRouter.isTrivialQuery('AI')).assertFalse();
      expect(IntentRouter.isTrivialQuery('5G')).assertFalse();
      expect(IntentRouter.isTrivialQuery('hi')).assertFalse();
      expect(IntentRouter.isTrivialQuery('栈')).assertFalse();
      expect(IntentRouter.isTrivialQuery('2026年安排')).assertFalse();
      expect(IntentRouter.isTrivialQuery('hello world')).assertFalse();
    });
  });

  describe('ScheduleTextParser', () => {
    it('tomorrowAfternoon_parsesStartTime', 0, () => {
      const p: ParsedSchedule = ScheduleTextParser.parse('明天下午3点开组会提醒我');
      expect(p.found).assertTrue();
      if (p.found) {
        expect(p.draft.title).assertContain('组会');
        const start: Date = new Date(p.draft.startTime);
        const today: Date = new Date();
        const expectDay: Date = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1);
        expect(start.getFullYear()).assertEqual(expectDay.getFullYear());
        expect(start.getMonth()).assertEqual(expectDay.getMonth());
        expect(start.getDate()).assertEqual(expectDay.getDate());
        expect(start.getHours()).assertEqual(15);
        expect(start.getMinutes()).assertEqual(0);
      }
    });

    it('tonight_parsesTodayEvening', 0, () => {
      const p: ParsedSchedule = ScheduleTextParser.parse('今晚八点记得交作业');
      expect(p.found).assertTrue();
      if (p.found) {
        expect(p.draft.title).assertContain('交作业');
        // 若当前时刻已过 20:00,解析器会把过期起始时间顺延到次日 20:00,故只验证:
        // 1) 小时=20;2) 起始在 [now, now+36h] 内
        expect(new Date(p.draft.startTime).getHours()).assertEqual(20);
        expect(p.draft.startTime).assertLargerOrEqual(Date.now());
        expect(p.draft.startTime).assertLessOrEqual(Date.now() + 36 * 3600 * 1000);
      }
    });

    it('nextWeekday_parsesOffsetDay', 0, () => {
      const p: ParsedSchedule = ScheduleTextParser.parse('下周三上午十点半开会');
      expect(p.found).assertTrue();
      if (p.found) {
        expect(p.draft.title).assertContain('开会');
        expect(new Date(p.draft.startTime).getMinutes()).assertEqual(30);
        expect(new Date(p.draft.startTime).getHours()).assertEqual(10);
      }
    });

    it('withoutTimeToken_returnsMiss', 0, () => {
      const p: ParsedSchedule = ScheduleTextParser.parse('帮我订个外卖');
      expect(p.found).assertFalse();
    });

    it('draftHasOneHourDurationByDefault', 0, () => {
      const p: ParsedSchedule = ScheduleTextParser.parse('明天上午9点开晨会');
      expect(p.found).assertTrue();
      if (p.found) {
        expect(p.draft.endTime - p.draft.startTime).assertEqual(3600 * 1000);
      }
    });

    it('dayAfterTomorrow_withNineThirty', 0, () => {
      const p: ParsedSchedule = ScheduleTextParser.parse('后天上午九点半开会');
      expect(p.found).assertTrue();
      if (p.found) {
        expect(p.draft.title).assertContain('开会');
        const start: Date = new Date(p.draft.startTime);
        const expectDay: Date = new Date(Date.now() + 2 * 24 * 3600 * 1000);
        expect(start.getFullYear()).assertEqual(expectDay.getFullYear());
        expect(start.getMonth()).assertEqual(expectDay.getMonth());
        expect(start.getDate()).assertEqual(expectDay.getDate());
        expect(start.getHours()).assertEqual(9);
        expect(start.getMinutes()).assertEqual(30);
      }
    });

    it('evening_noPrefix_shiftToPm', 0, () => {
      // "晚上八点"含"晚"前缀,8 点应转为 20 点
      const p: ParsedSchedule = ScheduleTextParser.parse('明天晚上八点看电影');
      expect(p.found).assertTrue();
      if (p.found) {
        expect(p.draft.title).assertContain('看电影');
        expect(new Date(p.draft.startTime).getHours()).assertEqual(20);
      }
    });

    it('afternoon5_is17Not5', 0, () => {
      const p: ParsedSchedule = ScheduleTextParser.parse('今天下午5点交作业');
      expect(p.found).assertTrue();
      if (p.found) {
        expect(p.draft.title).assertContain('交作业');
        expect(new Date(p.draft.startTime).getHours()).assertEqual(17);
      }
    });

    it('bare3oclock_interpretedAsAfternoon', 0, () => {
      // 无上下午前缀且 1-7 点,按下午处理(如"三点开会"=15:00)
      const p: ParsedSchedule = ScheduleTextParser.parse('明天三点开会');
      expect(p.found).assertTrue();
      if (p.found) {
        expect(new Date(p.draft.startTime).getHours()).assertEqual(15);
      }
    });

    it('bare8oclock_keptAsMorning', 0, () => {
      // 8 点不在 1-7 区间,不自动转下午
      const p: ParsedSchedule = ScheduleTextParser.parse('明天八点晨练');
      expect(p.found).assertTrue();
      if (p.found) {
        expect(new Date(p.draft.startTime).getHours()).assertEqual(8);
      }
    });

    it('nextMonday_offsetIsNextWeek', 0, () => {
      const p: ParsedSchedule = ScheduleTextParser.parse('下周一上午九点周会');
      expect(p.found).assertTrue();
      if (p.found) {
        const start: Date = new Date(p.draft.startTime);
        // 周一是 1;偏移应 >7(下周一),绝不落在本周
        const today: number = new Date().getDay();
        let rawOffset: number = (1 - today + 7) % 7;
        if (rawOffset === 0) {
          rawOffset = 7;
        }
        const expectDay: Date = new Date(Date.now() + (rawOffset + 7) * 24 * 3600 * 1000);
        expect(start.getFullYear()).assertEqual(expectDay.getFullYear());
        expect(start.getMonth()).assertEqual(expectDay.getMonth());
        expect(start.getDate()).assertEqual(expectDay.getDate());
      }
    });

    it('quarterPast_parsesFifteenMin', 0, () => {
      const p: ParsedSchedule = ScheduleTextParser.parse('明天上午十点一刻开会');
      expect(p.found).assertTrue();
      if (p.found) {
        expect(new Date(p.draft.startTime).getHours()).assertEqual(10);
        expect(new Date(p.draft.startTime).getMinutes()).assertEqual(15);
      }
    });

    it('emptyInput_returnsMiss', 0, () => {
      const p: ParsedSchedule = ScheduleTextParser.parse('');
      expect(p.found).assertFalse();
    });

    it('dateWithoutClockToken_returnsMiss', 0, () => {
      // 只有"明天"没有"N点",缺时间仍判未找到
      const p: ParsedSchedule = ScheduleTextParser.parse('明天开会');
      expect(p.found).assertFalse();
    });

    it('repeatedTime_takesFirstResolvedSlot', 0, () => {
      // 含两个时间词:解析器按先命中规则取其一,结果不抛错且为未来时间
      const p: ParsedSchedule = ScheduleTextParser.parse('明天下午三点到五点开组会');
      expect(p.found).assertTrue();
      if (p.found) {
        expect(p.draft.startTime).assertLarger(Date.now());
      }
    });

    it('chineseNumeralTen_parses', 0, () => {
      const p: ParsedSchedule = ScheduleTextParser.parse('明天十点交报告');
      expect(p.found).assertTrue();
      if (p.found) {
        // 无前缀且 10 不在 1-7,不转下午
        expect(new Date(p.draft.startTime).getHours()).assertEqual(10);
      }
    });

    it('noon12oclock_parsesAsTwelve', 0, () => {
      const p: ParsedSchedule = ScheduleTextParser.parse('明天中午12点开组会');
      expect(p.found).assertTrue();
      if (p.found) {
        expect(new Date(p.draft.startTime).getHours()).assertEqual(12);
        expect(new Date(p.draft.startTime).getMinutes()).assertEqual(0);
      }
    });

    it('twoDigitHour_parsesCorrectly', 0, () => {
      const p: ParsedSchedule = ScheduleTextParser.parse('明天上午11点开会');
      expect(p.found).assertTrue();
      if (p.found) {
        expect(new Date(p.draft.startTime).getHours()).assertEqual(11);
      }
    });

    it('noonOneOclock_isAfternoon', 0, () => {
      const p: ParsedSchedule = ScheduleTextParser.parse('明天中午1点开会');
      expect(p.found).assertTrue();
      if (p.found) {
        expect(new Date(p.draft.startTime).getHours()).assertEqual(13);
      }
    });
  });

  describe('ChainPlanner', () => {
    it('photoAndSchedule_buildsDocumentScheduleChain', 0, () => {
      const plan: ChainPlan | undefined = ChainPlanner.plan('拍一下会议纪要,总结后把待办写进日程提醒我');
      expect(plan !== undefined).assertTrue();
      if (plan !== undefined) {
        expect(plan.steps.length).assertEqual(2);
        expect(plan.steps[0]).assertEqual(ChainStepKind.Document);
        expect(plan.steps[1]).assertEqual(ChainStepKind.Schedule);
      }
    });

    it('photoAndMeeting_buildsChain', 0, () => {
      const plan: ChainPlan | undefined = ChainPlanner.plan('识别这张照片,里面有会议安排请加进日程');
      expect(plan !== undefined).assertTrue();
      if (plan !== undefined) {
        expect(plan.steps[1]).assertEqual(ChainStepKind.Schedule);
      }
    });

    it('pureDocument_returnsNoChain', 0, () => {
      const plan: ChainPlan | undefined = ChainPlanner.plan('拍一下这个文档帮我总结重点');
      expect(plan).assertUndefined();
    });

    it('pureSchedule_returnsNoChain', 0, () => {
      const plan: ChainPlan | undefined = ChainPlanner.plan('明天下午3点开组会提醒我');
      expect(plan).assertUndefined();
    });

    it('greeting_returnsNoChain', 0, () => {
      const plan: ChainPlan | undefined = ChainPlanner.plan('你好');
      expect(plan).assertUndefined();
    });
  });

  describe('AgentTools', () => {
    it('buildToolsJson_containsThreeFunctions', 0, () => {
      const json: string = AgentTools.buildToolsJson();
      expect(json.indexOf('search_knowledge') >= 0).assertTrue();
      expect(json.indexOf('recognize_summarize') >= 0).assertTrue();
      expect(json.indexOf('create_schedule') >= 0).assertTrue();
      const parsed = JSON.parse(json) as Array<Object>;
      expect(parsed.length).assertEqual(3);
    });

    it('readStringArg_returnsEmptyWhenAbsent', 0, () => {
      expect(AgentTools.readStringArg('{"query":"x"}', 'title')).assertEqual('');
    });

    it('readStringArg_returnsValue', 0, () => {
      expect(AgentTools.readStringArg('{"query":"RAG是什么"}', 'query')).assertEqual('RAG是什么');
    });
  });

  describe('SessionCodec', () => {
    it('roundTrip_preservesMessages', 0, () => {
      const msgs: ChatMessage[] = [
        ChatMessage.of(ChatRole.User, '明天下午三点开会'),
        ChatMessage.of(ChatRole.Assistant, '已安排日程')
      ];
      const json: string = SessionCodec.encode(msgs);
      const restored: ChatMessage[] = SessionCodec.decode(json);
      expect(restored.length).assertEqual(2);
      expect(restored[0].role).assertEqual(ChatRole.User);
      expect(restored[0].content).assertEqual('明天下午三点开会');
      expect(restored[1].role).assertEqual(ChatRole.Assistant);
      expect(restored[1].content).assertEqual('已安排日程');
    });

    it('emptyEncode_decodeReturnsEmpty', 0, () => {
      const restored: ChatMessage[] = SessionCodec.decode(SessionCodec.encode([]));
      expect(restored.length).assertEqual(0);
    });

    it('badJson_returnsEmpty', 0, () => {
      expect(SessionCodec.decode('not-json{').length).assertEqual(0);
    });

    it('roundTrip_preservesImageUris', 0, () => {
      const msgs: ChatMessage[] = [ChatMessage.ofImages(ChatRole.User, '看图', ['file://a.png', 'file://b.png'])];
      const json: string = SessionCodec.encode(msgs);
      const restored: ChatMessage[] = SessionCodec.decode(json);
      expect(restored.length).assertEqual(1);
      expect(restored[0].imageUris.length).assertEqual(2);
      expect(restored[0].imageUris[1]).assertEqual('file://b.png');
    });
  });
}
