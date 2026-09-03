import { http } from '@kit.NetworkKit';
import { ChatMessage, ChatRole } from '../../model/ChatModels';
import { LLMProvider } from './LLMProvider';

interface RequestMessage {
  role: string;
  content: string;
}

interface RequestPayload {
  model: string;
  messages: RequestMessage[];
  stream: boolean;
}

interface ReplyMessage {
  content: string;
}

interface ChatChoice {
  message: ReplyMessage;
}

interface ChatResponse {
  choices: ChatChoice[];
}

export class DeepSeekLlmProvider implements LLMProvider {
  readonly providerName: string = 'DeepSeek';
  private apiKey: string = '';
  private baseUrl: string = 'https://api.deepseek.com';
  private model: string = 'deepseek-chat';

  configure(apiKey: string, baseUrl: string, model: string): void {
    if (apiKey.length > 0) {
      this.apiKey = apiKey;
    }
    if (baseUrl.length > 0) {
      this.baseUrl = baseUrl;
    }
    if (model.length > 0) {
      this.model = model;
    }
  }

  private toRole(role: ChatRole): string {
    if (role === ChatRole.System) {
      return 'system';
    }
    if (role === ChatRole.User) {
      return 'user';
    }
    return 'assistant';
  }

  async chat(messages: ChatMessage[]): Promise<string> {
    if (this.apiKey.length === 0) {
      throw new Error('DeepSeek 未配置 API Key,请在 LlmConfig.ets 中填写。');
    }
    const reqMessages: RequestMessage[] = [];
    for (const item of messages) {
      const reqMsg: RequestMessage = { role: this.toRole(item.role), content: item.content };
      reqMessages.push(reqMsg);
    }
    const payload: RequestPayload = {
      model: this.model,
      messages: reqMessages,
      stream: false
    };
    const url: string = this.baseUrl.endsWith('/chat/completions') ?
      this.baseUrl : `${this.baseUrl}/chat/completions`;
    const requestOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`
      },
      extraData: JSON.stringify(payload),
      connectTimeout: 10000,
      readTimeout: 30000
    };
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, requestOptions);
      if (response.responseCode !== 200) {
        throw new Error(`DeepSeek 请求失败,HTTP ${response.responseCode}`);
      }
      const text: string = response.result as string;
      const parsed = JSON.parse(text) as ChatResponse;
      if (parsed.choices.length > 0) {
        return parsed.choices[0].message.content;
      }
      return '';
    } catch (err) {
      throw new Error(`DeepSeek 调用失败,请检查网络与 API Key:${JSON.stringify(err)}`);
    } finally {
      try {
        httpRequest.destroy();
      } catch (err) {
      }
    }
  }
}
