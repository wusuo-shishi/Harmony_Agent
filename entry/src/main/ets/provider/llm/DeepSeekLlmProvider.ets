import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { ChatMessage, ChatRole } from '../../model/ChatModels';
import { LLMProvider, ChatDeltaHandler } from './LLMProvider';
import { AgentToolTurn, ToolCallMsg, ToolMessage } from './AgentToolTypes';

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

// ---- tools / function calling 解析结构 ----
interface RawToolCall {
  id?: string;
  function?: RawToolFunction;
}

interface RawToolFunction {
  name?: string;
  arguments?: string;
}

interface RawMessage {
  content?: string;
  tool_calls?: RawToolCall[];
}

interface RawChoice {
  message?: RawMessage;
}

interface RawResponse {
  choices?: RawChoice[];
}

interface WireMessage {
  role: string;
  content: string;
  tool_calls?: RawWireToolCall[];
  tool_call_id?: string;
}

interface RawWireToolCall {
  id: string;
  type: string;
  function: RawWireToolFunction;
}

interface RawWireToolFunction {
  name: string;
  arguments: string;
}

export class DeepSeekLlmProvider implements LLMProvider {
  readonly providerName: string = 'DeepSeek';
  private apiKey: string = '';
  private baseUrl: string = 'https://api.deepseek.com';
  private model: string = 'deepseek-chat';
  private activeRequest: http.HttpRequest | undefined = undefined;

  cancelActive(): void {
    if (this.activeRequest !== undefined) {
      try {
        this.activeRequest.destroy();
      } catch (err) {
      }
      this.activeRequest = undefined;
    }
  }

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
    this.activeRequest = httpRequest;
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
      if (this.activeRequest === httpRequest) {
        this.activeRequest = undefined;
      }
    }
  }

  async streamChat(messages: ChatMessage[], onDelta: ChatDeltaHandler): Promise<string> {
    if (this.apiKey.length === 0) {
      throw new Error('DeepSeek 未配置 API Key,请在 LlmConfig.ets 中填写。');
    }
    const requestOptions: http.HttpRequestOptions = this.buildRequest(messages, true);
    const httpRequest = http.createHttp();
    this.activeRequest = httpRequest;
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
        if (this.activeRequest === httpRequest) {
          this.activeRequest = undefined;
        }
        resolve(fullText);
      });

      httpRequest.requestInStream(this.buildUrl(), requestOptions).then((code: number) => {
        if (code !== 200) {
          finished = true;
          if (this.activeRequest === httpRequest) {
            this.activeRequest = undefined;
          }
          reject(new Error(`DeepSeek 流式请求失败,HTTP ${code}`));
        }
      }).catch((err: Object) => {
        finished = true;
        if (this.activeRequest === httpRequest) {
          this.activeRequest = undefined;
        }
        reject(new Error(`DeepSeek 流式调用失败:${JSON.stringify(err)}`));
      });
    });
  }

  private toWireMessages(messages: ToolMessage[]): WireMessage[] {
    const wires: WireMessage[] = [];
    for (let i = 0; i < messages.length; i++) {
      const msg: ToolMessage = messages[i];
      const wire: WireMessage = { role: msg.role, content: msg.content };
      if (msg.toolCalls.length > 0) {
        const calls: RawWireToolCall[] = [];
        for (let j = 0; j < msg.toolCalls.length; j++) {
          const c: ToolCallMsg = msg.toolCalls[j];
          const f: RawWireToolFunction = { name: c.name, arguments: c.argsJson };
          const call: RawWireToolCall = { id: c.id, type: 'function', function: f };
          calls.push(call);
        }
        wire.tool_calls = calls;
      }
      if (msg.role === 'tool' && msg.toolCallId.length > 0) {
        wire.tool_call_id = msg.toolCallId;
      }
      wires.push(wire);
    }
    return wires;
  }

  async chatWithTools(messages: ToolMessage[], toolsJson: string): Promise<AgentToolTurn> {
    if (this.apiKey.length === 0) {
      throw new Error('DeepSeek 未配置 API Key,请在 LlmConfig.ets 中填写。');
    }
    const wires: WireMessage[] = this.toWireMessages(messages);
    const tools: Array<Object> = JSON.parse(toolsJson) as Array<Object>;
    const body: string = JSON.stringify({
      model: this.model,
      messages: wires,
      tools: tools,
      stream: false,
      max_tokens: 1200
    });
    const requestOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`
      },
      extraData: body,
      connectTimeout: 10000,
      readTimeout: 60000
    };
    const httpRequest = http.createHttp();
    this.activeRequest = httpRequest;
    try {
      const response = await httpRequest.request(this.buildUrl(), requestOptions);
      if (response.responseCode !== 200) {
        throw new Error(`DeepSeek 工具请求失败,HTTP ${response.responseCode}`);
      }
      const text: string = response.result as string;
      const parsed = JSON.parse(text) as RawResponse;
      if (parsed.choices === undefined || parsed.choices.length === 0) {
        return AgentToolTurn.reply('', true);
      }
      const rawMsg: RawMessage | undefined = parsed.choices[0].message;
      const content: string = rawMsg?.content ?? '';
      if (rawMsg?.tool_calls !== undefined && rawMsg.tool_calls.length > 0) {
        const calls: ToolCallMsg[] = [];
        for (let i = 0; i < rawMsg.tool_calls.length; i++) {
          const raw: RawToolCall = rawMsg.tool_calls[i];
          calls.push(ToolCallMsg.of(raw.id ?? `call_${i}`, raw.function?.name ?? '', raw.function?.arguments ?? '{}'));
        }
        return AgentToolTurn.withCalls(content, calls);
      }
      return AgentToolTurn.reply(content, true);
    } catch (err) {
      throw new Error(`DeepSeek 工具调用失败:${JSON.stringify(err)}`);
    } finally {
      try {
        httpRequest.destroy();
      } catch (err) {
      }
      if (this.activeRequest === httpRequest) {
        this.activeRequest = undefined;
      }
    }
  }
}
