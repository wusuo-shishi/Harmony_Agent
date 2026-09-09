import { KnowledgeChunk, RetrievalHit } from '../../model/KnowledgeModels';

class ChunkStat {
  chunk: KnowledgeChunk = new KnowledgeChunk();
  title: string = '';
  lowerText: string = '';
  titleTokens: string[] = [];
  tokenCount: number = 0;
  tf: Map<string, number> = new Map<string, number>();
}

export class Bm25Ranker {
  static readonly k1: number = 1.5;
  static readonly b: number = 0.75;
  static readonly snippetWin: number = 90;
  static readonly snippetPad: number = 12;

  static rank(query: string, topK: number, chunks: KnowledgeChunk[],
    titleOf: (docId: string) => string): RetrievalHit[] {
    const trimmed: string = query.trim().toLowerCase();
    if (trimmed.length === 0 || chunks.length === 0) {
      return [];
    }
    const stats: ChunkStat[] = [];
    const docFreq: Map<string, number> = new Map<string, number>();
    let totalTokens: number = 0;
    for (let i = 0; i < chunks.length; i++) {
      const chunk: KnowledgeChunk = chunks[i];
      const stat: ChunkStat = new ChunkStat();
      stat.chunk = chunk;
      stat.title = titleOf(chunk.docId);
      stat.lowerText = chunk.text.toLowerCase();
      stat.titleTokens = Bm25Ranker.uniqueTokens(Bm25Ranker.tokenize(stat.title.toLowerCase()));
      const tokens: string[] = Bm25Ranker.tokenize(stat.lowerText);
      stat.tokenCount = tokens.length;
      totalTokens += tokens.length;
      for (let j = 0; j < tokens.length; j++) {
        const term: string = tokens[j];
        if (!stat.tf.has(term)) {
          docFreq.set(term, (docFreq.get(term) ?? 0) + 1);
        }
        stat.tf.set(term, (stat.tf.get(term) ?? 0) + 1);
      }
      stats.push(stat);
    }
    const n: number = stats.length;
    const avgdl: number = n > 0 ? totalTokens / n : 0;
    if (avgdl <= 0) {
      return [];
    }
    const qTerms: string[] = Bm25Ranker.uniqueTokens(Bm25Ranker.tokenize(trimmed));
    if (qTerms.length === 0) {
      return [];
    }
    const limit: number = topK > 0 ? topK : 3;
    const hits: RetrievalHit[] = [];
    for (let i = 0; i < stats.length; i++) {
      const stat: ChunkStat = stats[i];
      let score: number = 0;
      let matched: number = 0;
      for (let j = 0; j < qTerms.length; j++) {
        const term: string = qTerms[j];
        const tf: number = stat.tf.get(term) ?? 0;
        if (tf <= 0) {
          continue;
        }
        matched++;
        const df: number = docFreq.get(term) ?? 0;
        const idf: number = Math.log(1 + (n - df + 0.5) / (df + 0.5));
        const norm: number = 1 - Bm25Ranker.b + Bm25Ranker.b * stat.tokenCount / avgdl;
        score += idf * (tf * (Bm25Ranker.k1 + 1)) / (tf + Bm25Ranker.k1 * norm);
      }
      if (matched === 0) {
        continue;
      }
      const exactAt: number = stat.lowerText.indexOf(trimmed);
      if (exactAt >= 0) {
        score += 0.8;
      }
      for (let j = 0; j < qTerms.length; j++) {
        if (stat.titleTokens.indexOf(qTerms[j]) >= 0) {
          score += 0.5;
          break;
        }
      }
      const anchor: number = Bm25Ranker.anchorOf(stat, qTerms, exactAt);
      if (anchor < 0) {
        continue;
      }
      hits.push(Bm25Ranker.buildHit(stat, anchor, score, matched));
    }
    hits.sort((a: RetrievalHit, b: RetrievalHit): number => {
      if (b.score !== a.score) {
        return b.score - a.score;
      }
      if (b.termCount !== a.termCount) {
        return b.termCount - a.termCount;
      }
      return a.chunkIndex - b.chunkIndex;
    });
    return hits.length > limit ? hits.slice(0, limit) : hits;
  }

  private static buildHit(stat: ChunkStat, anchor: number, score: number, matched: number): RetrievalHit {
    const len: number = stat.lowerText.length;
    const start: number = anchor > Bm25Ranker.snippetPad ? anchor - Bm25Ranker.snippetPad : 0;
    let end: number = start + Bm25Ranker.snippetWin;
    if (end > len) {
      end = len;
    }
    let snippet: string = stat.chunk.text.substring(start, end);
    if (start > 0) {
      snippet = `…${snippet}`;
    }
    if (end < len) {
      snippet = `${snippet}…`;
    }
    return RetrievalHit.of(stat.chunk.docId, stat.title, stat.chunk.chunkIndex,
      stat.chunk.charStart + anchor, snippet, score, matched);
  }

  private static anchorOf(stat: ChunkStat, qTerms: string[], exactAt: number): number {
    if (exactAt >= 0) {
      return exactAt;
    }
    let best: number = -1;
    for (let j = 0; j < qTerms.length; j++) {
      const term: string = qTerms[j];
      if ((stat.tf.get(term) ?? 0) <= 0) {
        continue;
      }
      const pos: number = stat.lowerText.indexOf(term);
      if (pos >= 0 && (best < 0 || pos < best)) {
        best = pos;
      }
    }
    return best;
  }

  private static uniqueTokens(tokens: string[]): string[] {
    const unique: string[] = [];
    for (let i = 0; i < tokens.length; i++) {
      const term: string = tokens[i];
      if (unique.indexOf(term) < 0) {
        unique.push(term);
      }
    }
    return unique;
  }

  private static tokenize(text: string): string[] {
    const tokens: string[] = [];
    const n: number = text.length;
    let i: number = 0;
    while (i < n) {
      const code: number = text.charCodeAt(i);
      if (Bm25Ranker.isCjk(code)) {
        let j: number = i;
        while (j < n && Bm25Ranker.isCjk(text.charCodeAt(j))) {
          j++;
        }
        for (let k = i; k < j; k++) {
          tokens.push(text.substring(k, k + 1));
        }
        for (let k = i; k < j - 1; k++) {
          tokens.push(text.substring(k, k + 2));
        }
        i = j;
      } else if (Bm25Ranker.isAlnum(code) || code === 0x2d) {
        let j: number = i;
        while (j < n) {
          const c: number = text.charCodeAt(j);
          if (Bm25Ranker.isAlnum(c) || c === 0x2d) {
            j++;
          } else {
            break;
          }
        }
        const word: string = text.substring(i, j);
        if (word.length > 0) {
          tokens.push(word);
        }
        i = j;
      } else {
        i++;
      }
    }
    return tokens;
  }

  private static isCjk(code: number): boolean {
    return code >= 0x4e00 && code <= 0x9fff;
  }

  private static isAlnum(code: number): boolean {
    return (code >= 0x30 && code <= 0x39) || (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
  }
}
