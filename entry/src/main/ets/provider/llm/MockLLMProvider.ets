import { ChatMessage } from '../../model/ChatModels';
import { LLMProvider } from './LLMProvider';

export class MockLLMProvider implements LLMProvider {
  readonly providerName: string = 'Mock';

  async chat(messages: ChatMessage[]): Promise<string> {
    const last: ChatMessage | undefined = messages.length > 0 ? messages[messages.length - 1] : undefined;
    const userText: string = last?.content ?? '';
    const brief: string = userText.length > 40 ? `${userText.substring(0, 40)}...` : userText;
    const count: number = messages.length;
    return `[Mock LLM] 已收到 ${count} 条消息,最近输入:${brief}\n当前为 Mock 回复,接入真实 LLM 后此文本将被模型输出替换。`;
  }
}
