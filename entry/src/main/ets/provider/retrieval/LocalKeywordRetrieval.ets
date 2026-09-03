import { KnowledgeChunk, RetrievalHit } from '../../model/KnowledgeModels';
import { KnowledgeStore } from '../../knowledge/KnowledgeStore';
import { RetrievalProvider } from './RetrievalProvider';

export class LocalKeywordRetrieval implements RetrievalProvider {
  readonly providerName: string = '本地关键词检索(ArkTS)';

  available(): boolean {
    return true;
  }

  async retrieve(query: string, topK: number): Promise<RetrievalHit[]> {
    const store: KnowledgeStore = KnowledgeStore.shared;
    const chunks: KnowledgeChunk[] = store.listChunks();
    if (chunks.length === 0) {
      return [];
    }
    const terms: string[] = this.tokenize(query.toLowerCase());
    const queryFull: string = query.toLowerCase();
    const scored: RetrievalHit[] = [];
    for (let i = 0; i < chunks.length; i++) {
      const chunk: KnowledgeChunk = chunks[i];
      const lowerText: string = chunk.text.toLowerCase();
      const docTitle: string = store.docTitle(chunk.docId).toLowerCase();
      let score: number = 0;
      let termCount: number = 0;
      let anchorPos: number = -1;
      if (lowerText.indexOf(queryFull) >= 0) {
        score += 4;
      }
      for (let j = 0; j < terms.length; j++) {
        const term: string = terms[j];
        if (term.length === 0) {
          continue;
        }
        const pos: number = lowerText.indexOf(term);
        if (pos >= 0) {
          score += 2;
          termCount++;
          if (anchorPos < 0 || pos < anchorPos) {
            anchorPos = pos;
          }
        }
        if (docTitle.indexOf(term) >= 0) {
          score += 1;
        }
      }
      if (termCount > 0 && anchorPos >= 0) {
        const hit: RetrievalHit = this.buildHit(chunk, anchorPos, score, termCount);
        scored.push(hit);
      }
    }
    scored.sort((a: RetrievalHit, b: RetrievalHit): number => {
      if (b.score !== a.score) {
        return b.score - a.score;
      }
      if (b.termCount !== a.termCount) {
        return b.termCount - a.termCount;
      }
      return a.chunkIndex - b.chunkIndex;
    });
    const limit: number = topK > 0 ? topK : 3;
    return scored.length > limit ? scored.slice(0, limit) : scored;
  }

  private buildHit(chunk: KnowledgeChunk, anchorPos: number, score: number, termCount: number): RetrievalHit {
    const snippetStart: number = anchorPos > 12 ? anchorPos - 12 : 0;
    let snippetEnd: number = snippetStart + 90;
    if (snippetEnd > chunk.text.length) {
      snippetEnd = chunk.text.length;
    }
    let snippet: string = chunk.text.substring(snippetStart, snippetEnd);
    if (snippetStart > 0) {
      snippet = `…${snippet}`;
    }
    if (snippetEnd < chunk.text.length) {
      snippet = `${snippet}…`;
    }
    return RetrievalHit.of(chunk.docId, KnowledgeStore.shared.docTitle(chunk.docId), chunk.chunkIndex,
      chunk.charStart + anchorPos, snippet, score, termCount);
  }

  private tokenize(text: string): string[] {
    const terms: string[] = [];
    const n: number = text.length;
    let i: number = 0;
    while (i < n) {
      const code: number = text.charCodeAt(i);
      if (this.isCjk(code)) {
        const nextCode: number = i + 1 < n ? text.charCodeAt(i + 1) : 0;
        if (this.isCjk(nextCode)) {
          const bigram: string = text.substring(i, i + 2);
          if (terms.indexOf(bigram) < 0) {
            terms.push(bigram);
          }
          i++;
        } else {
          const single: string = text.substring(i, i + 1);
          if (terms.indexOf(single) < 0) {
            terms.push(single);
          }
          i++;
        }
      } else if (this.isAlnum(code)) {
        let j: number = i;
        while (j < n) {
          const c: number = text.charCodeAt(j);
          if (this.isAlnum(c) || c === 0x2d) {
            j++;
          } else {
            break;
          }
        }
        const word: string = text.substring(i, j);
        if (word.length > 0 && terms.indexOf(word) < 0) {
          terms.push(word);
        }
        i = j;
      } else {
        i++;
      }
    }
    return terms;
  }

  private isCjk(code: number): boolean {
    return code >= 0x4e00 && code <= 0x9fff;
  }

  private isAlnum(code: number): boolean {
    return (code >= 0x30 && code <= 0x39) || (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
  }
}
