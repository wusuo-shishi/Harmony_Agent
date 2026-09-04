import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { ChatMessage, ChatRole } from '../../model/ChatModels';
import { LLMProvider, ChatDeltaHandler } from './LLMProvider';

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

interface StreamDelta {
  content?: string;
}

interface StreamChoice {
  delta?: StreamDelta;
}

interface StreamChunk {
  choices?: StreamChoice[];
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

  private buildUrl(): string {
    return this.baseUrl.endsWith('/chat/completions') ?
      this.baseUrl : `${this.baseUrl}/chat/completions`;
  }

  private buildRequest(messages: ChatMessage[], stream: boolean): http.HttpRequestOptions {
    const reqMessages: RequestMessage[] = [];
    for (const item of messages) {
      const reqMsg: RequestMessage = { role: this.toRole(item.role), content: item.content };
      reqMessages.push(reqMsg);
    }
    const payload: RequestPayload = {
      model: this.model,
      messages: reqMessages,
      stream: stream
    };
    return {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`
      },
      extraData: JSON.stringify(payload),
      connectTimeout: 10000,
      readTimeout: 60000
    };
  }

  async chat(messages: ChatMessage[]): Promise<string> {
    if (this.apiKey.length === 0) {
      throw new Error('DeepSeek 未配置 API Key,请在 LlmConfig.ets 中填写。');
    }
    const requestOptions: http.HttpRequestOptions = this.buildRequest(messages, false);
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(this.buildUrl(), requestOptions);
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

  async streamChat(messages: ChatMessage[], onDelta: ChatDeltaHandler): Promise<string> {
    if (this.apiKey.length === 0) {
      throw new Error('DeepSeek 未配置 API Key,请在 LlmConfig.ets 中填写。');
    }
    const requestOptions: http.HttpRequestOptions = this.buildRequest(messages, true);
    const httpRequest = http.createHttp();
    const decoder = new util.TextDecoder('utf-8');
    let buffer: string = '';
    let fullText: string = '';
    let finished: boolean = false;

    return new Promise<string>((resolve: (value: string) => void, reject: (reason: Object) => void) => {
      const dispatch = (): void => {
        while (true) {
          const nl: number = buffer.indexOf('\n');
          if (nl < 0) {
            break;
          }
          const line: string = buffer.substring(0, nl).trim();
          buffer = buffer.substring(nl + 1);
          if (line.length === 0) {
            continue;
          }
          if (!line.startsWith('data:')) {
            continue;
          }
          const data: string = line.substring(5).trim();
          if (data === '[DONE]') {
            finished = true;
            return;
          }
          try {
            const chunk = JSON.parse(data) as StreamChunk;
            if (chunk.choices !== undefined && chunk.choices.length > 0) {
              const delta: StreamDelta | undefined = chunk.choices[0].delta;
              const content: string | undefined = delta?.content;
              if (content !== undefined && content.length > 0) {
                fullText += content;
                onDelta(content);
              }
            }
          } catch (err) {
          }
        }
      };

      httpRequest.on('dataReceive', (data: ArrayBuffer): void => {
        if (finished) {
          return;
        }
        buffer += decoder.decodeToString(new Uint8Array(data));
        dispatch();
        if (finished) {
          resolve(fullText);
        }
      });
      httpRequest.on('dataEnd', (): void => {
        if (!finished) {
          finished = true;
          dispatch();
        }
        try {
          httpRequest.off('dataReceive');
          httpRequest.off('dataEnd');
        } catch (err) {
        }
        resolve(fullText);
      });

      httpRequest.requestInStream(this.buildUrl(), requestOptions).then((code: number) => {
        if (code !== 200) {
          finished = true;
          reject(new Error(`DeepSeek 流式请求失败,HTTP ${code}`));
        }
      }).catch((err: Object) => {
        finished = true;
        reject(new Error(`DeepSeek 流式调用失败:${JSON.stringify(err)}`));
      });
    });
  }
}
