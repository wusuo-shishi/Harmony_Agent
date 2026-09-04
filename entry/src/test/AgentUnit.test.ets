import { describe, it, expect } from '@ohos/hypium';
import { AgentKind } from '../main/ets/agent/AgentModels';
import { IntentResult } from '../main/ets/agent/IntentRouter';
import { IntentRouter } from '../main/ets/agent/IntentRouter';
import { ParsedSchedule } from '../main/ets/agent/ScheduleTextParser';
import { ScheduleTextParser } from '../main/ets/agent/ScheduleTextParser';

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
        expect(new Date(p.draft.startTime).getDate()).assertEqual(new Date().getDate());
        expect(new Date(p.draft.startTime).getHours()).assertEqual(20);
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
  });
}
