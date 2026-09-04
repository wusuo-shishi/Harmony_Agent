import { ChatMessage, ChatRole } from '../model/ChatModels';
import { ToolCallMsg } from '../provider/llm/AgentToolTypes';

export class ToolDefinition {
  name: string = '';
  description: string = '';
  parametersJson: string = '';

  static of(name: string, description: string, parametersJson: string): ToolDefinition {
    const t = new ToolDefinition();
    t.name = name;
    t.description = description;
    t.parametersJson = parametersJson;
    return t;
  }
}

export class AgentTools {
  static definitions(): ToolDefinition[] {
    return [
      ToolDefinition.of('search_knowledge', '在个人知识库中检索与问题相关的资料并回答(带引用)。用于"知识库/检索/资料/是什么/引用溯源"类问题。',
        '{"type":"object","properties":{"query":{"type":"string","description":"用户问题或检索关键词"}},"required":["query"]}'),
      ToolDefinition.of('recognize_summarize', '识别一张图片中的文字(OCR)并总结要点,存入知识库。用于"拍照/识图/图片文档/OCR"类请求。',
        '{"type":"object","properties":{"hint":{"type":"string","description":"图片说明,例如文档标题"}},"required":["hint"]}'),
      ToolDefinition.of('create_schedule', '把一项日程写入日历。用于"提醒/日程/安排/组会/会议/待办"并带有时间描述的请求。',
        '{"type":"object","properties":{"title":{"type":"string","description":"日程事项名"},' +
        '"time":{"type":"string","description":"自然语言时间,如 明天下午3点"}},"required":["title","time"]}')
    ];
  }

  static buildToolsJson(): string {
    const defs: ToolDefinition[] = AgentTools.definitions();
    const items: ToolWire[] = [];
    for (let i = 0; i < defs.length; i++) {
      const d: ToolDefinition = defs[i];
      const func: ToolFunctionWire = {
        name: d.name,
        description: d.description,
        parameters: JSON.parse(d.parametersJson) as Record<string, Object>
      };
      const item: ToolWire = { type: 'function', function: func };
      items.push(item);
    }
    return JSON.stringify(items);
  }

  static readStringArg(argsJson: string, key: string): string {
    try {
      const obj = JSON.parse(argsJson) as Record<string, Object>;
      const v = obj[key];
      return v === undefined ? '' : `${v}`;
    } catch (err) {
      return '';
    }
  }

  static asChatMessage(role: ChatRole, content: string): ChatMessage {
    return ChatMessage.of(role, content);
  }

  static toolCallOf(id: string, name: string, args: string): ToolCallMsg {
    return ToolCallMsg.of(id, name, args);
  }
}

interface ToolFunctionWire {
  name: string;
  description: string;
  parameters: Record<string, Object>;
}

interface ToolWire {
  type: string;
  function: ToolFunctionWire;
}
