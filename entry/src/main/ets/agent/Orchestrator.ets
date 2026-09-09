import { common } from '@kit.AbilityKit';
import { LLMProvider } from '../provider/llm/LLMProvider';
import { ChatDeltaHandler } from '../provider/llm/LLMProvider';
import { DeepSeekLlmProvider } from '../provider/llm/DeepSeekLlmProvider';
import { LlmConfig } from '../provider/llm/LlmConfig';
import { AgentToolTurn, ToolCallMsg, ToolMessage } from '../provider/llm/AgentToolTypes';
import { AgentTools } from './AgentTools';
import { RetrievalProvider } from '../provider/retrieval/RetrievalProvider';
import { ScheduleProvider } from '../provider/schedule/ScheduleProvider';
import { VisionProvider } from '../provider/vision/VisionProvider';
import { KnowledgeStore } from '../knowledge/KnowledgeStore';
import { AgentKind, AgentRunResult, AgentStep, StepState } from './AgentModels';
import { RetrievalHit } from '../model/KnowledgeModels';
import { RetrievalConfig } from '../provider/retrieval/RetrievalConfig';
import { StepListener } from './StepListener';
import { IntentResult, IntentRouter } from './IntentRouter';
import { ChainPlan, ChainPlanner, ChainStepKind } from './ChainPlanner';
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
  imageUris: string[] = [];
  requestImage: (() => Promise<string>) | undefined = undefined;

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

  async execute(text: string, deps: AgentDeps, onStep: StepListener,
    onDelta?: ChatDeltaHandler): Promise<AgentRunResult> {
    // Agentic(L2):开启且后端为 DeepSeek 时,优先让 LLM 自主决定是否调用工具
    if (LlmConfig.ENABLE_AGENTIC && deps.llm instanceof DeepSeekLlmProvider) {
      return await this.executeAgentic(text, deps, onStep, onDelta);
    }
    // 复合指令优先:识别为链则交给 executeChain
    const plan: ChainPlan | undefined = ChainPlanner.plan(text);
    if (plan !== undefined) {
      return await this.executeChain(plan, text, deps, onStep, onDelta);
    }
    const intent: IntentResult = IntentRouter.route(text);
    if (intent.kind === AgentKind.Learning) {
      return await this.learning.run(text, deps.llm, deps.retrieval, onStep, onDelta);
    }
    if (intent.kind === AgentKind.Schedule) {
      this.prepareScheduleProvider(deps);
      return await this.scheduleAgent.run(text, deps.llm, deps.schedule, onStep);
    }
    if (intent.kind === AgentKind.Document) {
      return await this.runDocument(text, deps, onStep, onDelta);
    }
    // General(无明确操作意图):先探测知识库,命中则给带引用回答;未命中才纯通用对话
    if (IntentRouter.isTrivialQuery(text)) {
      const result: AgentRunResult = new AgentRunResult();
      result.kind = AgentKind.General;
      result.agentName = '通用对话';
      const history: ChatMessage[] = [ChatMessage.of(ChatRole.User, text)];
      try {
        result.answer = await deps.llm.streamChat(history, (delta: string): void => {
          onDelta?.(delta);
        });
      } catch (err) {
        result.answer = '抱歉,获取回复失败,请稍后重试。';
      }
      return result;
    }
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
      return await this.learning.answerWithHitsInto(text, deps.llm, probeHits, steps, onStep, onDelta);
    }
    const result: AgentRunResult = new AgentRunResult();
    result.kind = AgentKind.General;
    result.agentName = '通用对话';
    const history: ChatMessage[] = [ChatMessage.of(ChatRole.User, text)];
    try {
      result.answer = await deps.llm.streamChat(history, (delta: string): void => {
        onDelta?.(delta);
      });
    } catch (err) {
      result.answer = '抱歉,获取回复失败,请稍后重试。';
    }
    return result;
  }

  private async executeAgentic(text: string, deps: AgentDeps, onStep: StepListener,
    onDelta?: ChatDeltaHandler): Promise<AgentRunResult> {
    const llm: DeepSeekLlmProvider = deps.llm as DeepSeekLlmProvider;
    const result: AgentRunResult = new AgentRunResult();
    result.agentName = 'Agentic(LLM 自主编排)';
    result.kind = AgentKind.General;
    const steps: AgentStep[] = [];
    const history: ToolMessage[] = [];
    history.push(ToolMessage.user(text));
    const toolsJson: string = AgentTools.buildToolsJson();
    let finalText: string = '';
    try {
      for (let round = 0; round < 5; round++) {
        const turn: AgentToolTurn = await llm.chatWithTools(history, toolsJson);
        if (turn.toolCalls.length === 0) {
          finalText = turn.text;
          break;
        }
        history.push(ToolMessage.assistantCalls(turn.text, turn.toolCalls));
        for (let c = 0; c < turn.toolCalls.length; c++) {
          const call: ToolCallMsg = turn.toolCalls[c];
          const step: AgentStep = AgentStep.of(`调用工具:${call.name}`);
          steps.push(step);
          onStep(steps);
          const out: string = await this.execTool(call.name, call.argsJson, text, deps, onStep, onDelta);
          const safeOut: string = out.length > 1500 ? out.substring(0, 1500) : out;
          history.push(ToolMessage.toolResult(call.id, safeOut));
          step.state = StepState.Done;
          step.detail = out.length > 0 ? out.substring(0, 60) : '空结果';
          onStep(steps);
        }
      }
    } catch (err) {
      finalText = '';
    }
    if (finalText.trim().length === 0) {
      // 兜底:LLM 未走工具或无输出时,回退普通对话,保证始终有回复
      try {
        const historyMsgs: ChatMessage[] = [ChatMessage.of(ChatRole.User, text)];
        finalText = await deps.llm.chat(historyMsgs);
      } catch (err2) {
        finalText = '抱歉,获取回复失败,请稍后重试。';
      }
    }
    if (steps.length === 0) {
      steps.push(AgentStep.of('1. LLM 自主判断无需调用工具,直接回答'));
      steps[steps.length - 1].state = StepState.Done;
    }
    result.answer = finalText;
    result.steps = steps;
    onStep(steps);
    return result;
  }

  private async execTool(name: string, argsJson: string, originText: string, deps: AgentDeps,
    onStep: StepListener, onDelta?: ChatDeltaHandler): Promise<string> {
    if (name === 'search_knowledge') {
      const q: string = AgentTools.readStringArg(argsJson, 'query');
      const query: string = q.length > 0 ? q : originText;
      const sub = await this.learning.run(query, deps.llm, deps.retrieval, onStep, onDelta);
      return sub.answer;
    }
    if (name === 'recognize_summarize') {
      const hint: string = AgentTools.readStringArg(argsJson, 'hint');
      this.prepareVisionProvider(deps);
      const sub = await this.document.run(hint.length > 0 ? hint : originText, deps.llm, deps.vision,
        deps.imageUri, deps.store, onStep, onDelta, deps.imageUris);
      return sub.answer;
    }
    if (name === 'create_schedule') {
      const title: string = AgentTools.readStringArg(argsJson, 'title');
      const time: string = AgentTools.readStringArg(argsJson, 'time');
      this.prepareScheduleProvider(deps);
      const sentence: string = `${time} 安排「${title}」提醒我`;
      const sub = await this.scheduleAgent.run(sentence, deps.llm, deps.schedule, onStep);
      return sub.answer;
    }
    return `未知工具:${name}`;
  }

  private async runDocument(text: string, deps: AgentDeps, onStep: StepListener,
    onDelta?: ChatDeltaHandler): Promise<AgentRunResult> {
    this.prepareVisionProvider(deps);
    // 真机文档处理需要图片:纯文本说"拍一下…"时若无图,先拉起取图回调
    if (!CapabilityManager.isEmulator() && deps.imageUri.length === 0 && deps.requestImage !== undefined) {
      const steps: AgentStep[] = [];
      steps.push(AgentStep.of('1. 检测到文档/识图意图'));
      onStep(steps);
      steps.push(AgentStep.of('2. 请选择或拍摄图片'));
      onStep(steps);
      try {
        const picked: string = await deps.requestImage();
        if (picked.length > 0) {
          deps.imageUri = picked;
          steps[steps.length - 1].state = StepState.Done;
          steps[steps.length - 1].detail = '已获取图片,开始 OCR';
          onStep(steps);
          return await this.document.run(text, deps.llm, deps.vision, deps.imageUri, deps.store, onStep, onDelta,
            deps.imageUris);
        }
      } catch (err) {
      }
      const cancelled: AgentRunResult = new AgentRunResult();
      cancelled.kind = AgentKind.Document;
      cancelled.agentName = '文档处理';
      cancelled.steps = steps;
      cancelled.answer = '未选择图片,已取消文档处理。可点输入框右侧「+」选图/拍照重试,或直接输入要处理的文字内容。';
      onStep(steps);
      return cancelled;
    }
    return await this.document.run(text, deps.llm, deps.vision, deps.imageUri, deps.store, onStep, onDelta,
      deps.imageUris);
  }

  private async executeChain(plan: ChainPlan, text: string, deps: AgentDeps, onStep: StepListener,
    onDelta?: ChatDeltaHandler): Promise<AgentRunResult> {
    const result: AgentRunResult = new AgentRunResult();
    const allSteps: AgentStep[] = [];
    const seen: Set<string> = new Set<string>();
    const subResults: AgentRunResult[] = [];
    let carry: string = '';
    // 链首步若为文档处理:真机需先有图片,无图则请求取图;未取得则取消整链
    if (plan.steps.length > 0 && plan.steps[0] === ChainStepKind.Document) {
      this.prepareVisionProvider(deps);
      if (!CapabilityManager.isEmulator() && deps.imageUri.length === 0 && deps.requestImage !== undefined) {
        const stepPick: AgentStep = AgentStep.of('0. 请选择或拍摄待处理图片');
        allSteps.push(stepPick);
        onStep(allSteps);
        try {
          const picked: string = await deps.requestImage();
          if (picked.length === 0) {
            const cancelled: AgentRunResult = new AgentRunResult();
            cancelled.kind = AgentKind.Document;
            cancelled.agentName = '复合任务';
            cancelled.steps = allSteps;
            cancelled.answer = '未选择图片,已取消复合任务。可点输入框右侧「+」选图/拍照重新选择。';
            onStep(allSteps);
            return cancelled;
          }
          deps.imageUri = picked;
          stepPick.state = StepState.Done;
          stepPick.detail = '已获取图片';
          onStep(allSteps);
        } catch (err) {
          const cancelled: AgentRunResult = new AgentRunResult();
          cancelled.kind = AgentKind.Document;
          cancelled.agentName = '复合任务';
          cancelled.steps = allSteps;
          cancelled.answer = '获取图片失败,已取消复合任务。';
          onStep(allSteps);
          return cancelled;
        }
      }
    }
    for (let i = 0; i < plan.steps.length; i++) {
      const kind: ChainStepKind = plan.steps[i];
      let sub: AgentRunResult = new AgentRunResult();
      if (kind === ChainStepKind.Document) {
        const stepHead: AgentStep = AgentStep.of(`第${i + 1}步(文档处理):识别并总结`);
        allSteps.push(stepHead);
        onStep(allSteps);
        sub = await this.document.run(carry.length > 0 ? carry : text, deps.llm, deps.vision, deps.imageUri,
          deps.store, onStep, onDelta, deps.imageUris);
        if (sub.payload.length === 0) {
          sub.payload = sub.answer;
        }
      } else if (kind === ChainStepKind.Schedule) {
        this.prepareScheduleProvider(deps);
        const stepHead: AgentStep = AgentStep.of(`第${i + 1}步(日程管家):将待办写入日程`);
        allSteps.push(stepHead);
        onStep(allSteps);
        // 日程输入优先取上游原始文本(payload),否则用上一步结果文本
        const scheduleInput: string = carry.length > 0 ? carry : text;
        sub = await this.scheduleAgent.run(scheduleInput, deps.llm, deps.schedule, onStep);
      } else if (kind === ChainStepKind.Learning) {
        const stepHead: AgentStep = AgentStep.of(`第${i + 1}步(学习助手):知识库问答`);
        allSteps.push(stepHead);
        onStep(allSteps);
        const learnText: string = carry.length > 0 ? carry : text;
        sub = await this.learning.run(learnText, deps.llm, deps.retrieval, onStep, onDelta);
      }
      subResults.push(sub);
      if (sub.payload.length > 0) {
        carry = sub.payload;
      } else if (sub.answer.length > 0) {
        carry = sub.answer;
      }
      for (let s = 0; s < sub.steps.length; s++) {
        const t: string = sub.steps[s].title;
        if (!seen.has(t)) {
          seen.add(t);
          allSteps.push(sub.steps[s]);
        }
      }
    }
    result.agentName = this.chainName(plan.steps);
    result.kind = this.chainTopKind(plan.steps);
    const answers: string[] = [];
    for (let i = 0; i < subResults.length; i++) {
      if (subResults[i].answer.length > 0) {
        answers.push(subResults[i].answer);
      }
    }
    result.answer = answers.length > 0 ? answers.join('\n\n---\n\n') : '复合任务已执行完成,但未产生可展示结果。';
    result.payload = carry;
    result.steps = allSteps;
    onStep(allSteps);
    return result;
  }

  private chainName(steps: ChainStepKind[]): string {
    const names: string[] = [];
    for (let i = 0; i < steps.length; i++) {
      if (steps[i] === ChainStepKind.Document) {
        names.push('文档处理');
      } else if (steps[i] === ChainStepKind.Schedule) {
        names.push('日程管家');
      } else {
        names.push('学习助手');
      }
    }
    return `复合任务(${names.join(' → ')})`;
  }

  private chainTopKind(steps: ChainStepKind[]): AgentKind {
    if (steps.length > 0 && steps[0] === ChainStepKind.Document) {
      return AgentKind.Document;
    }
    if (steps.length > 0 && steps[0] === ChainStepKind.Schedule) {
      return AgentKind.Schedule;
    }
    if (steps.length > 0 && steps[0] === ChainStepKind.Learning) {
      return AgentKind.Learning;
    }
    return AgentKind.General;
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
