import { UiTheme } from './UiTheme';

export enum MdRowKind {
  Empty = 0,
  Normal = 1,
  Heading = 2,
  SubHeading = 3,
  Quote = 4,
  Code = 5,
  Bullet = 6
}

export class MdRow {
  kind: MdRowKind = MdRowKind.Normal;
  text: string = '';

  static of(kind: MdRowKind, text: string): MdRow {
    const r = new MdRow();
    r.kind = kind;
    r.text = text;
    return r;
  }
}

export class MdParser {
  static parse(raw: string): MdRow[] {
    const normalized: string = raw.split('\r\n').join('\n').split('\r').join('\n');
    const lines: string[] = normalized.split('\n');
    const rows: MdRow[] = [];
    let inCode: boolean = false;
    let codeBuf: string[] = [];
    let lastEmpty: boolean = false;

    const flushCode = (): void => {
      if (codeBuf.length > 0) {
        rows.push(MdRow.of(MdRowKind.Code, codeBuf.join('\n')));
        codeBuf = [];
      }
    };

    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      const trimmed: string = line.trim();
      if (trimmed.startsWith('```')) {
        if (inCode) {
          inCode = false;
          flushCode();
        } else {
          inCode = true;
          codeBuf = [];
        }
        lastEmpty = false;
        continue;
      }
      if (inCode) {
        codeBuf.push(line);
        lastEmpty = false;
        continue;
      }
      if (trimmed.length === 0) {
        if (!lastEmpty) {
          rows.push(MdRow.of(MdRowKind.Empty, ''));
          lastEmpty = true;
        }
        continue;
      }
      lastEmpty = false;
      rows.push(MdParser.classify(trimmed));
    }
    if (inCode) {
      flushCode();
    }
    return rows;
  }

  private static classify(line: string): MdRow {
    if (line.startsWith('#')) {
      let hashCount: number = 0;
      while (hashCount < line.length && line.charAt(hashCount) === '#') {
        hashCount++;
      }
      const headingBody: string = MdParser.clean(line.substring(hashCount));
      if (headingBody.length > 0) {
        return MdRow.of(hashCount >= 3 ? MdRowKind.SubHeading : MdRowKind.Heading, headingBody);
      }
    }
    if (line.startsWith('> ')) {
      return MdRow.of(MdRowKind.Quote, MdParser.clean(line.substring(2)));
    }
    if (line.startsWith('- ') || line.startsWith('* ') || line.startsWith('+ ')) {
      return MdRow.of(MdRowKind.Bullet, MdParser.clean(line.substring(2)));
    }
    return MdRow.of(MdRowKind.Normal, MdParser.clean(line));
  }

  private static clean(text: string): string {
    let s: string = text.trim();
    s = MdParser.replaceAll(s, '**', '');
    s = MdParser.replaceAll(s, '__', '');
    s = MdParser.replaceAll(s, '`', '');
    s = MdParser.replaceAll(s, '*', '');
    return s;
  }

  /** 流式输出时使用:去掉标记符号,仅保留纯文本,避免打字过程中露出 Markdown 语法 */
  static plain(raw: string): string {
    const rows: MdRow[] = MdParser.parse(raw);
    const parts: string[] = [];
    for (let i = 0; i < rows.length; i++) {
      const row: MdRow = rows[i];
      if (row.kind === MdRowKind.Empty) {
        parts.push('');
      } else if (row.kind === MdRowKind.Bullet) {
        parts.push(`• ${row.text}`);
      } else {
        parts.push(row.text);
      }
    }
    return parts.join('\n');
  }

  private static replaceAll(value: string, from: string, to: string): string {
    return value.split(from).join(to);
  }
}

@Component
export struct MarkdownText {
  @Prop text: string = '';
  @Prop maxWidthVp: number = 420;
  @State rows: MdRow[] = [];

  aboutToAppear(): void {
    this.rows = MdParser.parse(this.text);
  }

  build() {
    Column({ space: 5 }) {
      ForEach(this.rows, (row: MdRow, index: number) => {
        if (row.kind === MdRowKind.Empty) {
          Column()
            .height(2)
        } else if (row.kind === MdRowKind.Heading) {
          Text(row.text)
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(UiTheme.TextPrimary)
            .lineHeight(26)
            .wordBreak(WordBreak.BREAK_ALL)
            .constraintSize({ maxWidth: this.maxWidthVp })
        } else if (row.kind === MdRowKind.SubHeading) {
          Text(row.text)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.TextPrimary)
            .lineHeight(23)
            .wordBreak(WordBreak.BREAK_ALL)
            .constraintSize({ maxWidth: this.maxWidthVp })
        } else if (row.kind === MdRowKind.Quote) {
          Row() {
            Column()
              .width(3)
              .height(20)
              .backgroundColor(UiTheme.Accent)
            Text(row.text)
              .fontSize(15)
              .fontColor(UiTheme.TextSecondary)
              .lineHeight(22)
              .wordBreak(WordBreak.BREAK_ALL)
              .layoutWeight(1)
              .margin({ left: 8 })
          }
          .alignItems(VerticalAlign.Top)
          .constraintSize({ maxWidth: this.maxWidthVp })
        } else if (row.kind === MdRowKind.Code) {
          Text(row.text)
            .fontSize(13)
            .fontColor('#3F4753')
            .backgroundColor('#F1F4FA')
            .lineHeight(20)
            .wordBreak(WordBreak.BREAK_ALL)
            .borderRadius(8)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .constraintSize({ maxWidth: this.maxWidthVp })
        } else if (row.kind === MdRowKind.Bullet) {
          Row() {
            Text('•')
              .fontSize(15)
              .fontColor(UiTheme.Accent)
              .fontWeight(FontWeight.Bold)
            Text(row.text)
              .fontSize(16)
              .fontColor(UiTheme.TextPrimary)
              .lineHeight(23)
              .wordBreak(WordBreak.BREAK_ALL)
              .layoutWeight(1)
              .margin({ left: 7 })
          }
          .alignItems(VerticalAlign.Top)
          .constraintSize({ maxWidth: this.maxWidthVp })
        } else {
          Text(row.text)
            .fontSize(16)
            .fontColor(UiTheme.TextPrimary)
            .lineHeight(23)
            .wordBreak(WordBreak.BREAK_ALL)
            .constraintSize({ maxWidth: this.maxWidthVp })
        }
      }, (row: MdRow, index: number) => `${row.kind}_${index}_${row.text}`)
    }
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxWidth: this.maxWidthVp })
  }
}
