import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ChatMessage, ChatRole } from '../model/ChatModels';
import { SessionCodec } from './SessionCodec';

export class ConversationSummary {
  id: string = '';
  title: string = '';
  updatedAt: number = 0;

  static of(id: string, title: string, updatedAt: number): ConversationSummary {
    const item = new ConversationSummary();
    item.id = id;
    item.title = title;
    item.updatedAt = updatedAt;
    return item;
  }
}

interface StoredConversation {
  id: string;
  title: string;
  updatedAt: number;
  messages: string;
}

interface StoredState {
  currentId: string;
  conversations: StoredConversation[];
}

export class ConversationStore {
  private static readonly fileName: string = 'chat_conversations';
  private static readonly stateKey: string = 'state_v1';
  private static readonly maxConversations: number = 30;
  private pref: preferences.Preferences | undefined = undefined;
  private state: StoredState = { currentId: '', conversations: [] };

  async init(ctx: common.UIAbilityContext): Promise<void> {
    this.pref = await preferences.getPreferences(ctx, { name: ConversationStore.fileName });
    const raw = await this.pref.get(ConversationStore.stateKey, '') as string;
    if (raw.length === 0) {
      return;
    }
    try {
      const parsed = JSON.parse(raw) as StoredState;
      if (Array.isArray(parsed.conversations)) {
        this.state = parsed;
      }
    } catch (err) {
      this.state = { currentId: '', conversations: [] };
    }
  }

  currentId(): string {
    return this.state.currentId;
  }

  summaries(): ConversationSummary[] {
    const result: ConversationSummary[] = [];
    const sorted: StoredConversation[] = this.state.conversations.slice().sort(
      (a: StoredConversation, b: StoredConversation): number => b.updatedAt - a.updatedAt);
    for (let i = 0; i < sorted.length; i++) {
      result.push(ConversationSummary.of(sorted[i].id, sorted[i].title, sorted[i].updatedAt));
    }
    return result;
  }

  load(id: string): ChatMessage[] {
    const item = this.find(id);
    return item === undefined ? [] : SessionCodec.decode(item.messages);
  }

  async save(id: string, messages: ChatMessage[]): Promise<void> {
    if (id.length === 0) {
      return;
    }
    let item = this.find(id);
    if (item === undefined) {
      item = { id: id, title: '新对话', updatedAt: Date.now(), messages: '' };
      this.state.conversations.push(item);
    }
    item.messages = SessionCodec.encode(messages);
    item.updatedAt = Date.now();
    item.title = this.titleFrom(messages);
    this.state.currentId = id;
    this.trimOldest();
    await this.flush();
  }

  async remove(id: string): Promise<void> {
    this.state.conversations = this.state.conversations.filter(
      (item: StoredConversation): boolean => item.id !== id);
    if (this.state.currentId === id) {
      this.state.currentId = '';
    }
    await this.flush();
  }

  async rename(id: string, title: string): Promise<void> {
    const item = this.find(id);
    const clean: string = title.trim();
    if (item === undefined || clean.length === 0) {
      return;
    }
    item.title = clean.substring(0, 30);
    item.updatedAt = Date.now();
    await this.flush();
  }

  newId(): string {
    return `chat_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  }

  private find(id: string): StoredConversation | undefined {
    for (let i = 0; i < this.state.conversations.length; i++) {
      if (this.state.conversations[i].id === id) {
        return this.state.conversations[i];
      }
    }
    return undefined;
  }

  private titleFrom(messages: ChatMessage[]): string {
    for (let i = 0; i < messages.length; i++) {
      if (messages[i].role === ChatRole.User && messages[i].content.trim().length > 0) {
        return messages[i].content.trim().replace(/\n/g, ' ').substring(0, 24);
      }
    }
    return '新对话';
  }

  private trimOldest(): void {
    if (this.state.conversations.length <= ConversationStore.maxConversations) {
      return;
    }
    this.state.conversations.sort(
      (a: StoredConversation, b: StoredConversation): number => b.updatedAt - a.updatedAt);
    this.state.conversations = this.state.conversations.slice(0, ConversationStore.maxConversations);
  }

  private async flush(): Promise<void> {
    if (this.pref === undefined) {
      return;
    }
    await this.pref.put(ConversationStore.stateKey, JSON.stringify(this.state));
    await this.pref.flush();
  }
}
