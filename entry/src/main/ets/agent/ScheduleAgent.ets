import { AgentKind, AgentRunResult, AgentStep, ScheduleDraft, StepState } from './AgentModels';
import { StepListener } from './StepListener';
import { ParsedSchedule, ScheduleTextParser } from './ScheduleTextParser';
import { ScheduleProvider } from '../provider/schedule/ScheduleProvider';
import { MemoryScheduleProvider } from '../provider/schedule/MemoryScheduleProvider';
import { LLMProvider } from '../provider/llm/LLMProvider';
import { ChatMessage, ChatRole } from '../model/ChatModels';

export type ScheduleConfirmHandler = (draft: ScheduleDraft) => Promise<boolean>;

export class ScheduleAgent {
  readonly agentName: string = '日程管家';

  async run(query: string, llm: LLMProvider, schedule: ScheduleProvider | undefined,
    onStep: StepListener, confirm?: ScheduleConfirmHandler): Promise<AgentRunResult> {
    const result: AgentRunResult = new AgentRunResult();
    result.kind = AgentKind.Schedule;
    result.agentName = this.agentName;
    const steps: AgentStep[] = [];
    steps.push(AgentStep.of('1. 识别日程意图'));
    onStep(steps);
    await delay(200);

    const parsed: ParsedSchedule = ScheduleTextParser.parse(query);
    if (!parsed.found) {
      const fallback: ParsedSchedule = await this.llmFallbackParse(query, llm);
      if (!fallback.found) {
        steps.push(AgentStep.of('2. 抽取时间与事项'));
        steps[steps.length - 1].state = StepState.Failed;
        steps[steps.length - 1].detail = '未能从语句中解析出日期/时间';
        result.answer = '我还无法从这句话里确定日程时间,请补充如「明天下午 3 点开组会」这样的说法。';
        result.steps = steps;
        onStep(steps);
        return result;
      }
      return await this.doAdd(query, fallback.draft, schedule, steps, onStep, result, confirm);
    }
    return await this.doAdd(query, parsed.draft, schedule, steps, onStep, result, confirm);
  }

  private async doAdd(query: string, draft: ScheduleDraft, schedule: ScheduleProvider | undefined,
    steps: AgentStep[], onStep: StepListener, result: AgentRunResult,
    confirm?: ScheduleConfirmHandler): Promise<AgentRunResult> {
    steps.push(AgentStep.of('2. 抽取时间与事项'));
    steps[steps.length - 1].detail =
      `事项「${draft.title}」 ${formatScheduleTime(draft.startTime)} 起(默认 1 小时)`;
    steps[steps.length - 1].state = StepState.Done;
    onStep(steps);

    if (confirm !== undefined && !(await confirm(draft))) {
      steps.push(AgentStep.of('3. 等待用户确认'));
      steps[steps.length - 1].state = StepState.Failed;
      steps[steps.length - 1].detail = '用户取消创建';
      result.answer = `已取消创建日程「${draft.title}」。`;
      result.steps = steps;
      onStep(steps);
      return result;
    }

    const provider: ScheduleProvider = schedule ?? new MemoryScheduleProvider();
    const existing: string[] = await provider.listEvents();
    const scheduleTime: string = formatScheduleTime(draft.startTime);
    for (let i = 0; i < existing.length; i++) {
      if (existing[i].indexOf(scheduleTime) >= 0 && existing[i].indexOf(draft.title) >= 0) {
        steps.push(AgentStep.of('3. 检查重复日程'));
        steps[steps.length - 1].state = StepState.Failed;
        steps[steps.length - 1].detail = '发现相同时间和标题的日程';
        result.answer = `未重复创建:「${draft.title}」在 ${formatScheduleTime(draft.startTime)} 已存在。`;
        result.steps = steps;
        onStep(steps);
        return result;
      }
    }
    steps.push(AgentStep.of(`4. 写入日程(${provider.providerName})`));
    onStep(steps);
    try {
      const msg: string = await provider.addEvent(draft);
      steps[steps.length - 1].state = StepState.Done;
      steps[steps.length - 1].detail = msg;
      result.answer = `好的,已为你安排:\n「${draft.title}」\n${formatScheduleTime(draft.startTime)} 开始(时长约 1 小时)。\n(${msg})`;
    } catch (err) {
      steps[steps.length - 1].state = StepState.Failed;
      steps[steps.length - 1].detail = err instanceof Error ? err.message : '写入失败';
      result.answer = '日程写入失败:' + (err instanceof Error ? err.message : '未知错误') + '\n已为你保留计划文本:' + draft.title;
    }
    result.steps = steps;
    onStep(steps);
    return result;
  }

  private async llmFallbackParse(query: string, llm: LLMProvider): Promise<ParsedSchedule> {
    try {
      const prompt: string =
        `从下面句子中提取一条日程,输出 JSON,不要多余文字:\n` +
        `{"title":"事项","date":"YYYY-MM-DD","start":"HH:MM","durationMinutes":60}\n` +
        `句子:${query}`;
      const messages: ChatMessage[] = [ChatMessage.of(ChatRole.User, prompt)];
      const reply: string = (await llm.chat(messages)).trim();
      const jsonStart: number = reply.indexOf('{');
      const jsonEnd: number = reply.lastIndexOf('}');
      if (jsonStart < 0 || jsonEnd <= jsonStart) {
        return ParsedSchedule.miss();
      }
      const body: string = reply.substring(jsonStart, jsonEnd + 1);
      const obj = JSON.parse(body) as Record<string, Object>;
      const title: string = `${obj['title'] ?? ''}`;
      const dateText: string = `${obj['date'] ?? ''}`;
      const timeText: string = `${obj['start'] ?? ''}`;
      const dur: number = Number(obj['durationMinutes'] ?? 60);
      if (title.length === 0 || dateText.length === 0 || timeText.length === 0) {
        return ParsedSchedule.miss();
      }
      const startMs: number = new Date(`${dateText}T${timeText}`).getTime();
      if (Number.isNaN(startMs)) {
        return ParsedSchedule.miss();
      }
      const draft: ScheduleDraft = ScheduleDraft.of(title, startMs, startMs + dur * 60000);
      return ParsedSchedule.ok(draft, '');
    } catch (err) {
      return ParsedSchedule.miss();
    }
  }
}

function formatScheduleTime(ts: number): string {
  const d = new Date(ts);
  const pad = (v: number): string => (v < 10 ? `0${v}` : `${v}`);
  return `${d.getMonth() + 1}-${d.getDate()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}
