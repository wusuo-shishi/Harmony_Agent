export class SensitiveHit {
  word: string = '';
  index: number = -1;

  static of(word: string, index: number): SensitiveHit {
    const hit = new SensitiveHit();
    hit.word = word;
    hit.index = index;
    return hit;
  }
}

export class SensitiveWordFilter {
  private static readonly defaultWords: string[] = [
    '赌博', '诈骗', '刷单', '洗钱', '博彩', '色情', '毒品', '赌场',
    '代开发票', '假发票', '违禁品', '管制刀具', '枪支弹药', '翻墙'
  ];
  private static words: string[] = SensitiveWordFilter.defaultWords.slice();

  static resetDefault(): void {
    SensitiveWordFilter.words = SensitiveWordFilter.defaultWords.slice();
  }

  static addWord(word: string): void {
    const trimmed: string = word.trim();
    if (trimmed.length === 0) {
      return;
    }
    if (SensitiveWordFilter.words.indexOf(trimmed) < 0) {
      SensitiveWordFilter.words.push(trimmed);
    }
  }

  static wordCount(): number {
    return SensitiveWordFilter.words.length;
  }

  static firstHit(text: string): SensitiveHit | undefined {
    let best: SensitiveHit | undefined = undefined;
    for (let i = 0; i < SensitiveWordFilter.words.length; i++) {
      const word: string = SensitiveWordFilter.words[i];
      const idx: number = text.indexOf(word);
      if (idx >= 0 && (best === undefined || idx < best.index)) {
        best = SensitiveHit.of(word, idx);
      }
    }
    return best;
  }

  static hasSensitive(text: string): boolean {
    return SensitiveWordFilter.firstHit(text) !== undefined;
  }
}
