import { ChatMessage } from '../../model/ChatModels';
import { LLMProvider, ChatDeltaHandler } from './LLMProvider';

export class PanguLlmProvider implements LLMProvider {
  readonly providerName: string = 'Pangu(HuaweiCloud)';
  private apiKey: string = '';
  private endpoint: string = '';

  configure(apiKey: string, endpoint: string): void {
    this.apiKey = apiKey;
    this.endpoint = endpoint;
  }

  async chat(messages: ChatMessage[]): Promise<string> {
    throw new Error('Pangu LLM 尚未配置:请先开通华为云 ModelArts Studio 并通过 configure() 填入凭证与接入点。');
  }

  async streamChat(messages: ChatMessage[], onDelta: ChatDeltaHandler): Promise<string> {
    throw new Error('Pangu LLM 尚未配置:请先开通华为云 ModelArts Studio 并通过 configure() 填入凭证与接入点。');
  }
}
