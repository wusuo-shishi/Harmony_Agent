import { ChatMessage } from '../../model/ChatModels';

export type ChatDeltaHandler = (delta: string) => void;

export interface LLMProvider {
  readonly providerName: string;
  chat(messages: ChatMessage[]): Promise<string>;
  streamChat(messages: ChatMessage[], onDelta: ChatDeltaHandler): Promise<string>;
  cancelActive(): void;
}
