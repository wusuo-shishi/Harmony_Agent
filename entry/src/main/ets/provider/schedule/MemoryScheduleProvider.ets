import { ScheduleDraft } from '../../agent/AgentModels';
import { ScheduleProvider } from './ScheduleProvider';

class MemoryEvent {
  title: string = '';
  startTime: number = 0;

  static of(title: string, startTime: number): MemoryEvent {
    const e = new MemoryEvent();
    e.title = title;
    e.startTime = startTime;
    return e;
  }
}

export class MemoryScheduleProvider implements ScheduleProvider {
  readonly providerName: string = '内存日程(模拟器)';
  private events: MemoryEvent[] = [];

  available(): boolean {
    return false;
  }

  async addEvent(draft: ScheduleDraft): Promise<string> {
    this.events.push(MemoryEvent.of(draft.title, draft.startTime));
    const t: string = formatScheduleTime(draft.startTime);
    return `已加入内存日程(${t}):${draft.title}`;
  }

  async listEvents(): Promise<string[]> {
    const lines: string[] = [];
    for (let i = 0; i < this.events.length; i++) {
      const e = this.events[i];
      lines.push(`${formatScheduleTime(e.startTime)} ${e.title}`);
    }
    return lines;
  }
}

function formatScheduleTime(ts: number): string {
  const d = new Date(ts);
  const pad = (v: number): string => (v < 10 ? `0${v}` : `${v}`);
  return `${d.getMonth() + 1}-${d.getDate()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
