import { ChatMessage } from '../../model/ChatModels';
import { LLMProvider, ChatDeltaHandler } from './LLMProvider';

export class MockLLMProvider implements LLMProvider {
  readonly providerName: string = 'Mock';
  private cancelled: boolean = false;

  cancelActive(): void {
    this.cancelled = true;
  }

  async chat(messages: ChatMessage[]): Promise<string> {
    return this.buildReply(messages);
  }

  async streamChat(messages: ChatMessage[], onDelta: ChatDeltaHandler): Promise<string> {
    this.cancelled = false;
    const full: string = this.buildReply(messages);
    const step: number = 6;
    let i: number = 0;
    while (i < full.length) {
      if (this.cancelled) {
        return '';
      }
      const end: number = Math.min(full.length, i + step);
      onDelta(full.substring(i, end));
      i = end;
      await delay(16);
    }
    return full;
  }

  private buildReply(messages: ChatMessage[]): string {
    const last: ChatMessage | undefined = messages.length > 0 ? messages[messages.length - 1] : undefined;
    const userText: string = last?.content ?? '';
    const brief: string = userText.length > 40 ? `${userText.substring(0, 40)}...` : userText;
    const count: number = messages.length;
    return `[Mock LLM] 已收到 ${count} 条消息,最近输入:${brief}\n当前为 Mock 回复,接入真实 LLM 后此文本将被模型输出替换。`;
  }
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}
