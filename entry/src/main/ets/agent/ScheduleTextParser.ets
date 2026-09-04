import { ScheduleDraft } from './AgentModels';

export class ParsedSchedule {
  found: boolean = false;
  draft: ScheduleDraft = new ScheduleDraft();
  remaining: string = '';

  static ok(draft: ScheduleDraft, remaining: string): ParsedSchedule {
    const p = new ParsedSchedule();
    p.found = true;
    p.draft = draft;
    p.remaining = remaining;
    return p;
  }

  static miss(): ParsedSchedule {
    return new ParsedSchedule();
  }
}

export class ScheduleTextParser {
  private static readonly minute: number = 60 * 1000;
  private static readonly hour: number = 60 * ScheduleTextParser.minute;
  private static readonly day: number = 24 * ScheduleTextParser.hour;
  private static readonly weekdays: string[] = ['日', '一', '二', '三', '四', '五', '六'];

  static parse(text: string): ParsedSchedule {
    let work: string = text.replace(new RegExp('\\s+', 'g'), '');
    work = work.replace(new RegExp('[，,。.！!？?]', 'g'), ' ');
    work = ScheduleTextParser.stripReminderPrefix(work);
    const dateInfo: DateToken | undefined = ScheduleTextParser.resolveDate(work);
    if (dateInfo === undefined) {
      return ParsedSchedule.miss();
    }
    const timeInfo: TimeToken | undefined = ScheduleTextParser.resolveTime(work);
    if (timeInfo === undefined) {
      return ParsedSchedule.miss();
    }
    let start: number = ScheduleTextParser.anchorDay(dateInfo.dayOffset, timeInfo.hour, timeInfo.minute);
    const now: number = Date.now();
    if (start <= now) {
      start += ScheduleTextParser.day;
    }
    const title: string = ScheduleTextParser.extractTitle(work, dateInfo.tokens, timeInfo.tokens);
    const draft: ScheduleDraft = ScheduleDraft.of(title, start, start + ScheduleTextParser.hour);
    let remainingText: string = ScheduleTextParser.stripTokens(work, dateInfo.tokens);
    remainingText = ScheduleTextParser.stripTokens(remainingText, timeInfo.tokens);
    remainingText = remainingText.replace(new RegExp('\\s+', 'g'), ' ').trim();
    return ParsedSchedule.ok(draft, remainingText);
  }

  private static anchorDay(dayOffset: number, hour: number, minute: number): number {
    const base: Date = new Date(Date.now());
    const target: Date = new Date(base.getFullYear(), base.getMonth(), base.getDate() + dayOffset, hour, minute, 0, 0);
    return target.getTime();
  }

  private static stripReminderPrefix(input: string): string {
    let work: string = input.trim();
    const prefixCandidates: string[] = ['帮我', '请', '麻烦'];
    for (let i = 0; i < prefixCandidates.length; i++) {
      if (work.startsWith(prefixCandidates[i])) {
        work = work.substring(prefixCandidates[i].length);
      }
    }
    const re = new RegExp('^(记得|提醒我|安排|把|记一下)');
    work = work.replace(re, '');
    return work;
  }

  private static resolveDate(text: string): DateToken | undefined {
    if (text.indexOf('大后天') >= 0) {
      return DateToken.of(3, ['大后天']);
    }
    if (text.indexOf('后天') >= 0) {
      return DateToken.of(2, ['后天']);
    }
    if (text.indexOf('明天') >= 0) {
      return DateToken.of(1, ['明天']);
    }
    if (text.indexOf('今晚') >= 0) {
      return DateToken.of(0, ['今晚', '今天']);
    }
    if (text.indexOf('今天') >= 0) {
      return DateToken.of(0, ['今天']);
    }
    for (let i = 0; i < ScheduleTextParser.weekdays.length; i++) {
      const wd: string = ScheduleTextParser.weekdays[i];
      const direct: string = `周${wd}`;
      const full: string = `星期${wd}`;
      const hasDirect: boolean = text.indexOf(direct) >= 0;
      const hasFull: boolean = text.indexOf(full) >= 0;
      if (hasDirect || hasFull) {
        let offset: number = ScheduleTextParser.nextWeekday(i);
        const re = new RegExp('下(周|星期)');
        if (re.test(text)) {
          offset += 7;
        }
        return DateToken.of(offset, [direct, full]);
      }
    }
    return undefined;
  }

  private static nextWeekday(targetIndex: number): number {
    const today: number = new Date().getDay();
    let delta: number = (targetIndex - today + 7) % 7;
    if (delta === 0) {
      delta = 7;
    }
    return delta;
  }

  private static resolveTime(text: string): TimeToken | undefined {
    const numLike: string = '[0-9０-９一二三四五六七八九十]+';
    const halfRe = new RegExp(`(${numLike})点(半|一刻|三刻|([0-9０-９]+)分)`);
    let hour: number = 0;
    let minute: number = 0;
    let found: boolean = false;
    const m = halfRe.exec(text);
    if (m !== null) {
      hour = ScheduleTextParser.hourOfText(m[1]);
      if (m[2] === '半') {
        minute = 30;
      } else if (m[2] === '一刻') {
        minute = 15;
      } else if (m[2] === '三刻') {
        minute = 45;
      } else if (m[3] !== undefined && m[3].length > 0) {
        minute = ScheduleTextParser.hourOfText(m[3]);
      }
      found = true;
    } else {
      const simpleRe = new RegExp(`(${numLike})点`);
      const sm = simpleRe.exec(text);
      if (sm !== null) {
        hour = ScheduleTextParser.hourOfText(sm[1]);
        found = true;
      }
    }
    if (!found) {
      return undefined;
    }
    if (text.indexOf('下午') >= 0 || text.indexOf('晚上') >= 0 || text.indexOf('晚') >= 0) {
      if (hour < 12) {
        hour += 12;
      }
    } else if (text.indexOf('上午') < 0 && text.indexOf('早上') < 0 && hour >= 1 && hour < 8) {
      hour += 12;
    }
    return TimeToken.of(hour, minute);
  }

  private static hourOfText(raw: string): number {
    const chineseFull: string[] = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十', '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十', '二十一', '二十二', '二十三', '二十四'];
    for (let i = 0; i < chineseFull.length; i++) {
      if (raw === chineseFull[i]) {
        return i;
      }
    }
    const digitFull: string[] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    for (let i = 0; i < digitFull.length; i++) {
      if (raw === digitFull[i]) {
        return i;
      }
    }
    const last: string = raw.substring(raw.length - 1);
    for (let i = 0; i < chineseFull.length; i++) {
      if (last === chineseFull[i]) {
        return i;
      }
    }
    return 0;
  }

  private static extractTitle(text: string, dateTokens: string[], timeTokens: string[]): string {
    let work: string = text;
    work = ScheduleTextParser.stripTokens(work, dateTokens);
    work = ScheduleTextParser.stripTokens(work, timeTokens);
    const dateWords: string[] = ['今天', '明天', '后天', '大后天', '上午', '下午', '晚上', '早上', '晚'];
    for (let i = 0; i < dateWords.length; i++) {
      work = work.split(dateWords[i]).join(' ');
    }
    work = work.replace(new RegExp('([0-9０-９一二三四五六七八九十]+)[点时]', 'g'), ' ');
    const actionCandidates: string[] = ['提醒我', '记一下', '安排一下', '安排', '提醒', '记得'];
    for (let i = 0; i < actionCandidates.length; i++) {
      work = work.split(actionCandidates[i]).join(' ');
    }
    work = work.replace(new RegExp('\\s+', 'g'), ' ').trim();
    const keywords: string[] = ['组会', '会议', '上课', '考试', '汇报', '约会', '面试', '开会', '提交', '交作业', 'deadline', 'ddl'];
    for (let i = 0; i < keywords.length; i++) {
      const kw: string = keywords[i];
      const idx: number = work.indexOf(kw);
      if (idx >= 0) {
        const startIdx: number = idx > 8 ? idx - 8 : 0;
        let title: string = work.substring(startIdx);
        if (title.length > 20) {
          title = title.substring(0, 20);
        }
        return title.trim();
      }
    }
    if (work.length === 0) {
      return '日程提醒';
    }
    return work.length > 30 ? work.substring(0, 30) : work;
  }

  private static stripTokens(text: string, tokens: string[]): string {
    let work: string = text;
    for (let i = 0; i < tokens.length; i++) {
      work = work.split(tokens[i]).join(' ');
    }
    return work;
  }
}

class DateToken {
  dayOffset: number = 0;
  tokens: string[] = [];

  static of(dayOffset: number, tokens: string[]): DateToken {
    const d = new DateToken();
    d.dayOffset = dayOffset;
    d.tokens = tokens;
    return d;
  }
}

class TimeToken {
  hour: number = 0;
  minute: number = 0;
  tokens: string[] = [];

  static of(hour: number, minute: number): TimeToken {
    const t = new TimeToken();
    t.hour = hour;
    t.minute = minute;
    return t;
  }
}
