import { common } from '@kit.AbilityKit';
import { LLMProvider } from '../provider/llm/LLMProvider';
import { RetrievalProvider } from '../provider/retrieval/RetrievalProvider';
import { ScheduleProvider } from '../provider/schedule/ScheduleProvider';
import { VisionProvider } from '../provider/vision/VisionProvider';
import { KnowledgeStore } from '../knowledge/KnowledgeStore';
import { AgentKind, AgentRunResult, AgentStep } from './AgentModels';
import { RetrievalHit } from '../model/KnowledgeModels';
import { RetrievalConfig } from '../provider/retrieval/RetrievalConfig';
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
    // General(无明确操作意图):先探测知识库,命中则给带引用回答;未命中才纯通用对话
    let probeHits: RetrievalHit[] = [];
    try {
      probeHits = await deps.retrieval.retrieve(text, RetrievalConfig.DEFAULT_TOP_K);
    } catch (err) {
      probeHits = [];
    }
    if (probeHits.length > 0) {
      const steps: AgentStep[] = [];
      steps.push(AgentStep.of('1. 解析问题'));
      onStep(steps);
      steps.push(AgentStep.of('2. 检索知识库(命中,进入知识问答)'));
      onStep(steps);
      return await this.learning.answerWithHitsInto(text, deps.llm, probeHits, steps, onStep);
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
