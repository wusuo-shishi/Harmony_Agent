import { AgentKind, AgentRunResult, AgentStep, StepState } from './AgentModels';
import { StepListener } from './StepListener';
import { VisionProvider } from '../provider/vision/VisionProvider';
import { SampleVisionProvider } from '../provider/vision/SampleVisionProvider';
import { LLMProvider } from '../provider/llm/LLMProvider';
import { ChatDeltaHandler } from '../provider/llm/LLMProvider';
import { ChatMessage, ChatRole } from '../model/ChatModels';
import { KnowledgeStore } from '../knowledge/KnowledgeStore';

export class DocumentAgent {
  readonly agentName: string = '文档处理';

  async run(query: string, llm: LLMProvider, vision: VisionProvider | undefined, imageUri: string | undefined,
    store: KnowledgeStore, onStep: StepListener, onDelta?: ChatDeltaHandler): Promise<AgentRunResult> {
    const result: AgentRunResult = new AgentRunResult();
    result.kind = AgentKind.Document;
    result.agentName = this.agentName;
    const steps: AgentStep[] = [];
    steps.push(AgentStep.of('1. 识别文档/拍照意图'));
    onStep(steps);
    await delay(200);

    const provider: VisionProvider = vision ?? new SampleVisionProvider();
    steps.push(AgentStep.of(`2. OCR 识别文字(${provider.providerName})`));
    onStep(steps);
    let text: string = '';
    try {
      text = await provider.recognizeImageUri(imageUri ?? '');
      steps[steps.length - 1].state = StepState.Done;
      steps[steps.length - 1].detail = text.length > 0 ? `识别出 ${text.length} 字` : '识别结果为空';
    } catch (err) {
      steps[steps.length - 1].state = StepState.Failed;
      steps[steps.length - 1].detail = err instanceof Error ? err.message : 'OCR 失败';
      result.answer = '图片文字识别失败:' + (err instanceof Error ? err.message : '未知错误');
      result.steps = steps;
      onStep(steps);
      return result;
    }
    if (text.trim().length === 0) {
      result.answer = '图片中未识别到文字,请换一张更清晰的图片重试。';
      result.steps = steps;
      onStep(steps);
      return result;
    }

    steps.push(AgentStep.of('3. 大模型总结要点'));
    onStep(steps);
    const prompt: string =
      `下面是 OCR 识别出的文档内容,请总结要点(分条,中文,不超过 200 字):\n${truncate(text, 3000)}`;
    const messages: ChatMessage[] = [ChatMessage.of(ChatRole.User, prompt)];
    let summary: string = '';
    try {
      summary = await llm.streamChat(messages, (delta: string): void => {
        onDelta?.(delta);
      });
    } catch (err) {
      summary = '(大模型总结失败,以下为识别原文片段)\n' + truncate(text, 300);
    }
    steps[steps.length - 1].state = StepState.Done;

    let savedInfo: string = '';
    try {
      const docTitle: string = guessDocTitle(query);
      const doc = store.importContent(docTitle, text);
      steps.push(AgentStep.of('4. 写入知识库(可选)'));
      steps[steps.length - 1].state = StepState.Done;
      savedInfo = `\n已将识别内容存入知识库「${doc.title}」(${doc.chunkCount} 分块),可到知识库页检索。`;
      onStep(steps);
    } catch (err) {
      savedInfo = '';
    }

    result.answer = `【OCR 文档处理完成】\n\n${summary}${savedInfo}`;
    result.payload = text;
    result.steps = steps;
    onStep(steps);
    return result;
  }
}

function truncate(text: string, max: number): string {
  if (text.length <= max) {
    return text;
  }
  return text.substring(0, max) + '…';
}

function guessDocTitle(query: string): string {
  const candidates: string[] = ['拍照', '图片', '文档', '照片', '拍一下', '这个', 'OCR', 'ocr'];
  for (let i = 0; i < candidates.length; i++) {
    if (query.indexOf(candidates[i]) >= 0) {
      return `拍照文档_${Date.now()}`;
    }
  }
  return `识别文档_${Date.now()}`;
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}
