import { common } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScheduleDraft } from '../../agent/AgentModels';
import { ScheduleProvider } from './ScheduleProvider';

export class CalendarScheduleProvider implements ScheduleProvider {
  readonly providerName: string = '系统日历(HarmonyOS CalendarKit)';
  private ctx: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.ctx = context;
  }

  available(): boolean {
    return true;
  }

  async addEvent(draft: ScheduleDraft): Promise<string> {
    const manager: calendarManager.CalendarManager = calendarManager.getCalendarManager(this.ctx);
    let cal: calendarManager.Calendar | undefined = undefined;
    try {
      cal = await manager.getCalendar();
    } catch (err) {
      cal = undefined;
    }
    if (cal === undefined) {
      const account: calendarManager.CalendarAccount = {
        name: 'OpenHarmonyAgent',
        type: calendarManager.CalendarType.LOCAL,
        displayName: 'OpenHarmonyAgent'
      };
      try {
        cal = await manager.createCalendar(account);
      } catch (createErr) {
        const e = createErr as BusinessError;
        throw new Error(`创建日历失败(code=${e.code}, message=${e.message})`);
      }
    }
    const event: calendarManager.Event = {
      type: calendarManager.EventType.NORMAL,
      title: draft.title,
      startTime: draft.startTime,
      endTime: draft.endTime,
      reminderTime: [draft.reminderMinutes * 60 * 1000],
      description: draft.rawText,
      location: draft.location.length > 0 ? { location: draft.location } : undefined
    };
    try {
      const eventId: number = await cal.addEvent(event);
      return `已写入系统日历(eventId=${eventId})`;
    } catch (err) {
      const e = err as BusinessError;
      throw new Error(`写入日历失败(code=${e.code}, message=${e.message})`);
    }
  }

  async listEvents(): Promise<string[]> {
    const manager: calendarManager.CalendarManager = calendarManager.getCalendarManager(this.ctx);
    const cal: calendarManager.Calendar | undefined = await this.tryGetCalendar(manager);
    if (cal === undefined) {
      return [];
    }
    try {
      const events: calendarManager.Event[] = await cal.getEvents();
      const lines: string[] = [];
      for (let i = 0; i < events.length; i++) {
        const ev: calendarManager.Event = events[i];
        const t: string = ev.title ?? '未命名';
        lines.push(`${t} @ ${ScheduleProvider_time(ev.startTime)}`);
      }
      return lines;
    } catch (err) {
      return [];
    }
  }

  private async tryGetCalendar(manager: calendarManager.CalendarManager): Promise<calendarManager.Calendar | undefined> {
    try {
      return await manager.getCalendar();
    } catch (err) {
      return undefined;
    }
  }
}

function ScheduleProvider_time(ts: number): string {
  const d = new Date(ts);
  const pad = (v: number): string => (v < 10 ? `0${v}` : `${v}`);
  return `${d.getMonth() + 1}-${d.getDate()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
