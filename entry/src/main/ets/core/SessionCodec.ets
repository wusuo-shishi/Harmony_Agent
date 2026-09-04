import { ChatMessage, ChatRole } from '../model/ChatModels';

interface ChatMsgWire {
  role: string;
  content: string;
  ts: number;
}

export class SessionCodec {
  static encode(messages: ChatMessage[]): string {
    const wires: ChatMsgWire[] = [];
    for (let i = 0; i < messages.length; i++) {
      const m: ChatMessage = messages[i];
      const w: ChatMsgWire = { role: m.role, content: m.content, ts: m.timestamp };
      wires.push(w);
    }
    return JSON.stringify(wires);
  }

  static decode(json: string): ChatMessage[] {
    if (json.length === 0) {
      return [];
    }
    let wires: ChatMsgWire[] = [];
    try {
      wires = JSON.parse(json) as ChatMsgWire[];
    } catch (err) {
      return [];
    }
    const out: ChatMessage[] = [];
    for (let i = 0; i < wires.length; i++) {
      const w: ChatMsgWire = wires[i];
      const msg: ChatMessage = SessionCodec.wireToMessage(w);
      if (msg.content.length > 0) {
        out.push(msg);
      }
    }
    return out;
  }

  static roleOf(raw: string): ChatRole {
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
    msg.role = SessionCodec.roleOf(w.role);
    msg.content = w.content;
    msg.timestamp = w.ts;
    msg.id = `${w.ts}_restored`;
    return msg;
  }
}
