import { ChatMessage, ChatRole } from '../model/ChatModels';

interface ChatMsgWire {
  role?: string;
  content?: string;
  ts?: number;
  uris?: string[];
}

export class SessionCodec {
  static encode(messages: ChatMessage[], includeImages: boolean = true): string {
    const wires: ChatMsgWire[] = [];
    for (let i = 0; i < messages.length; i++) {
      const m: ChatMessage = messages[i];
      const w: ChatMsgWire = { role: m.role, content: m.content, ts: m.timestamp };
      if (includeImages && m.imageUris.length > 0) {
        w.uris = m.imageUris;
      }
      wires.push(w);
    }
    return JSON.stringify(wires);
  }

  static decode(json: string): ChatMessage[] {
    if (json.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(json) as ChatMsgWire[];
      if (parsed === undefined || parsed === null) {
        return [];
      }
      const out: ChatMessage[] = [];
      for (let i = 0; i < parsed.length; i++) {
        const msg: ChatMessage = SessionCodec.wireToMessage(parsed[i]);
        if (msg.content.length > 0 || msg.imageUris.length > 0) {
          out.push(msg);
        }
      }
      return out;
    } catch (err) {
      return [];
    }
  }

  static roleOf(raw: string | undefined): ChatRole {
    if (raw === 'user') {
      return ChatRole.User;
    }
    if (raw === 'assistant') {
      return ChatRole.Assistant;
    }
    return ChatRole.System;
  }

  static wireToMessage(w: ChatMsgWire): ChatMessage {
    const msg: ChatMessage = new ChatMessage();
    msg.role = SessionCodec.roleOf(w === undefined || w === null ? undefined : w.role);
    const content: string | undefined = w === undefined || w === null ? undefined : w.content;
    msg.content = content === undefined ? '' : `${content}`;
    const ts: number | undefined = w === undefined || w === null ? undefined : w.ts;
    msg.timestamp = ts === undefined ? Date.now() : ts;
    msg.id = `${msg.timestamp}_restored`;
    if (w !== undefined && w !== null && w.uris !== undefined && w.uris.length > 0) {
      const uris: string[] = [];
      for (let i = 0; i < w.uris.length; i++) {
        const uri: string = w.uris[i];
        if (uri !== undefined && uri.length > 0) {
          uris.push(uri);
        }
      }
      msg.imageUris = uris;
    }
    return msg;
  }
}
