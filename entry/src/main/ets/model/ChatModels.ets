export enum ChatRole {
  System = 'system',
  User = 'user',
  Assistant = 'assistant'
}

export class ChatMessage {
  id: string = '';
  role: ChatRole = ChatRole.User;
  content: string = '';
  timestamp: number = 0;
  imageUris: string[] = [];

  static of(role: ChatRole, content: string): ChatMessage {
    const msg = new ChatMessage();
    msg.id = `${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    msg.role = role;
    msg.content = content;
    msg.timestamp = Date.now();
    return msg;
  }

  static ofImages(role: ChatRole, content: string, uris: string[]): ChatMessage {
    const msg = ChatMessage.of(role, content);
    msg.imageUris = uris;
    return msg;
  }
}
