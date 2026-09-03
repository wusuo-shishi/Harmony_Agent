import { ChatMessage } from '../../model/ChatModels';

export interface LLMProvider {
  readonly providerName: string;
  chat(messages: ChatMessage[]): Promise<string>;
}
