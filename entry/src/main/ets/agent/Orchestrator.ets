import { common } from '@kit.AbilityKit';
import { LLMProvider } from '../provider/llm/LLMProvider';
import { RetrievalProvider } from '../provider/retrieval/RetrievalProvider';
import { ScheduleProvider } from '../provider/schedule/ScheduleProvider';
import { VisionProvider } from '../provider/vision/VisionProvider';
import { KnowledgeStore } from '../knowledge/KnowledgeStore';
import { AgentKind, AgentRunResult } from './AgentModels';
import { StepListener } from './StepListener';
import { IntentResult, IntentRouter } from './IntentRouter';
import { LearningAgent } from './LearningAgent';
import { ScheduleAgent } from './ScheduleAgent';
import { DocumentAgent } from './DocumentAgent';
import { CapabilityManager } from '../core/CapabilityManager';
import { CalendarScheduleProvider } from '../provider/schedule/CalendarScheduleProvider';
import { MemoryScheduleProvider } from '../provider/schedule/MemoryScheduleProvider';
import { CoreVisionOcrProvider } from '../provider/vision/CoreVisionOcrProvider';
import { SampleVisionProvider } from '../provider/vision/SampleVisionProvider';
import { ChatMessage, ChatRole } from '../model/ChatModels';

export class AgentDeps {
  llm: LLMProvider;
  retrieval: RetrievalProvider;
  schedule: ScheduleProvider;
  vision: VisionProvider;
  store: KnowledgeStore;
  uiContext: common.UIAbilityContext | undefined = undefined;
  imageUri: string = '';

  constructor(llm: LLMProvider, retrieval: RetrievalProvider, store: KnowledgeStore) {
    this.llm = llm;
    this.retrieval = retrieval;
    this.store = store;
    this.schedule = new MemoryScheduleProvider();
    this.vision = new SampleVisionProvider();
  }
}

export class Orchestrator {
  private readonly learning: LearningAgent = new LearningAgent();
  private readonly scheduleAgent: ScheduleAgent = new ScheduleAgent();
  private readonly document: DocumentAgent = new DocumentAgent();

  async execute(text: string, deps: AgentDeps, onStep: StepListener): Promise<AgentRunResult> {
    const intent: IntentResult = IntentRouter.route(text);
    if (intent.kind === AgentKind.Learning) {
      return await this.learning.run(text, deps.llm, deps.retrieval, onStep);
    }
    if (intent.kind === AgentKind.Schedule) {
      this.prepareScheduleProvider(deps);
      return await this.scheduleAgent.run(text, deps.llm, deps.schedule, onStep);
    }
    if (intent.kind === AgentKind.Document) {
      this.prepareVisionProvider(deps);
      return await this.document.run(text, deps.llm, deps.vision, deps.imageUri, deps.store, onStep);
    }
    const result: AgentRunResult = new AgentRunResult();
    result.kind = AgentKind.General;
    result.agentName = '通用对话';
    const history: ChatMessage[] = [ChatMessage.of(ChatRole.User, text)];
    try {
      result.answer = await deps.llm.chat(history);
    } catch (err) {
      result.answer = '抱歉,获取回复失败,请稍后重试。';
    }
    return result;
  }

  private prepareScheduleProvider(deps: AgentDeps): void {
    const ctx: common.UIAbilityContext | undefined = deps.uiContext;
    if (ctx !== undefined && CapabilityManager.supportsCalendar()) {
      deps.schedule = new CalendarScheduleProvider(ctx);
    } else {
      deps.schedule = new MemoryScheduleProvider();
    }
  }

  private prepareVisionProvider(deps: AgentDeps): void {
    if (CapabilityManager.isEmulator()) {
      deps.vision = new SampleVisionProvider();
    } else {
      deps.vision = new CoreVisionOcrProvider();
    }
  }
}
