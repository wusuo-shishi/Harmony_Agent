import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScheduleDraft } from '../../agent/AgentModels';
import { ScheduleProvider } from './ScheduleProvider';

interface CalendarPermissionResult {
  authResults: number[];
}

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
    const granted: boolean = await this.ensureCalendarPermission();
    if (!granted) {
      throw new Error('未授予日历读写权限,请在系统设置中允许本应用访问「日历」后重试。');
    }
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
      // CalendarKit 单位:提前 N 分钟提醒(如 15 = 提前15分钟),不是毫秒
      reminderTime: [draft.reminderMinutes],
      description: draft.rawText
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

  private async ensureCalendarPermission(): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    try {
      const token: number = this.ctx.applicationInfo.accessTokenId;
      const status: abilityAccessCtrl.GrantStatus =
        atManager.checkAccessTokenSync(token, 'ohos.permission.WRITE_CALENDAR');
      if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      }
    } catch (err) {
    }
    try {
      const result = await atManager.requestPermissionsFromUser(this.ctx,
        ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR']);
      const granted: CalendarPermissionResult = result as CalendarPermissionResult;
      return granted.authResults !== undefined && granted.authResults.length > 0 && granted.authResults[0] === 0;
    } catch (err) {
      return false;
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
