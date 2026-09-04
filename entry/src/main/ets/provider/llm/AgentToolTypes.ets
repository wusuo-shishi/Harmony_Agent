export class ToolCallMsg {
  id: string = '';
  name: string = '';
  argsJson: string = '';

  static of(id: string, name: string, argsJson: string): ToolCallMsg {
    const t = new ToolCallMsg();
    t.id = id;
    t.name = name;
    t.argsJson = argsJson;
    return t;
  }
}

export class ToolMessage {
  role: string = 'user';
  content: string = '';
  toolCalls: ToolCallMsg[] = [];
  toolCallId: string = '';

  static user(content: string): ToolMessage {
    const m = new ToolMessage();
    m.role = 'user';
    m.content = content;
    return m;
  }

  static assistantCalls(content: string, calls: ToolCallMsg[]): ToolMessage {
    const m = new ToolMessage();
    m.role = 'assistant';
    m.content = content;
    m.toolCalls = calls;
    return m;
  }

  static toolResult(toolCallId: string, content: string): ToolMessage {
    const m = new ToolMessage();
    m.role = 'tool';
    m.content = content;
    m.toolCallId = toolCallId;
    return m;
  }
}

export class AgentToolTurn {
  text: string = '';
  toolCalls: ToolCallMsg[] = [];
  finished: boolean = false;

  static reply(text: string, finished: boolean): AgentToolTurn {
    const turn = new AgentToolTurn();
    turn.text = text;
    turn.finished = finished;
    return turn;
  }

  static withCalls(text: string, calls: ToolCallMsg[]): AgentToolTurn {
    const turn = new AgentToolTurn();
    turn.text = text;
    turn.toolCalls = calls;
    return turn;
  }
}
