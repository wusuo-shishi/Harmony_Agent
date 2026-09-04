import { RetrievalHit } from '../model/KnowledgeModels';
import { RetrievalProvider } from '../provider/retrieval/RetrievalProvider';
import { LLMProvider } from '../provider/llm/LLMProvider';
import { ChatMessage, ChatRole } from '../model/ChatModels';
import { RetrievalConfig } from '../provider/retrieval/RetrievalConfig';
import { AgentKind, AgentRunResult, AgentStep, StepState } from './AgentModels';
import { StepListener } from './StepListener';

export class LearningAgent {
  readonly agentName: string = '学习助手';

  async run(query: string, llm: LLMProvider, retrieval: RetrievalProvider, onStep: StepListener): Promise<AgentRunResult> {
    const steps: AgentStep[] = [];
    steps.push(AgentStep.of('1. 解析问题(意图:知识库问答)'));
    onStep(steps);
    await delay(300);
    steps.push(AgentStep.of('2. 检索知识库'));
    onStep(steps);

    let hits: RetrievalHit[] = [];
    try {
      hits = await retrieval.retrieve(query, RetrievalConfig.DEFAULT_TOP_K);
    } catch (err) {
      hits = [];
    }
    return await this.answerWithHitsInto(query, llm, hits, steps, onStep);
  }

  async answerWithHitsInto(query: string, llm: LLMProvider, hits: RetrievalHit[], steps: AgentStep[],
    onStep: StepListener): Promise<AgentRunResult> {
    const result: AgentRunResult = new AgentRunResult();
    result.kind = AgentKind.Learning;
    result.agentName = this.agentName;
    if (steps.length > 0) {
      steps[steps.length - 1].detail = hits.length > 0 ? `召回 ${hits.length} 条` : '未命中,将直接回答';
      steps[steps.length - 1].state = StepState.Done;
    }
    steps.push(AgentStep.of('3. 组织回答(LLM 生成,附引用)'));
    onStep(steps);

    const prompt: string = buildRagPrompt(query, hits);
    const messages: ChatMessage[] = [ChatMessage.of(ChatRole.User, prompt)];
    let answer: string = '';
    try {
      answer = await llm.chat(messages);
    } catch (err) {
      answer = '抱歉,大模型调用失败。';
    }
    const citeLines: string[] = [];
    for (let i = 0; i < hits.length; i++) {
      const h: RetrievalHit = hits[i];
      citeLines.push(`[${i + 1}]《${h.docTitle}》#分块${h.chunkIndex + 1} 原文偏移${h.charStart}`);
    }
    result.answer = citeLines.length > 0 ? `${answer}\n\n引用来源:\n${citeLines.join('\n')}` : answer;
    steps[steps.length - 1].state = StepState.Done;
    result.steps = steps;
    onStep(steps);
    return result;
  }
}

function buildRagPrompt(query: string, hits: RetrievalHit[]): string {
  const parts: string[] = [];
  parts.push(`问题:${query}`);
  if (hits.length > 0) {
    parts.push('以下是从个人知识库检索到的资料(带来源),请据此回答,并标注使用了哪些资料:');
    for (let i = 0; i < hits.length; i++) {
      const h: RetrievalHit = hits[i];
      parts.push(`资料[${i + 1}]《${h.docTitle}》第${h.chunkIndex + 1}分块:`);
      parts.push(h.snippet);
    }
    parts.push('若资料不足以回答,请明确说明。');
  } else {
    parts.push('知识库未命中相关文档,请基于通用知识简要回答,并提示可导入更多资料。');
  }
  return parts.join('\n');
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}
