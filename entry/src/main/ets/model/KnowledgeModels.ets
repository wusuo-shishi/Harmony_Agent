export enum DocSource {
  Sample = 'sample',
  Imported = 'imported'
}

export class KnowledgeDoc {
  id: string = '';
  title: string = '';
  source: DocSource = DocSource.Imported;
  createdAt: number = 0;
  charCount: number = 0;
  chunkCount: number = 0;

  static of(id: string, title: string, source: DocSource, createdAt: number): KnowledgeDoc {
    const doc = new KnowledgeDoc();
    doc.id = id;
    doc.title = title;
    doc.source = source;
    doc.createdAt = createdAt;
    return doc;
  }
}

export class KnowledgeChunk {
  docId: string = '';
  chunkIndex: number = 0;
  charStart: number = 0;
  text: string = '';

  static of(docId: string, chunkIndex: number, charStart: number, text: string): KnowledgeChunk {
    const chunk = new KnowledgeChunk();
    chunk.docId = docId;
    chunk.chunkIndex = chunkIndex;
    chunk.charStart = charStart;
    chunk.text = text;
    return chunk;
  }
}

export class RetrievalHit {
  docId: string = '';
  docTitle: string = '';
  chunkIndex: number = 0;
  charStart: number = 0;
  snippet: string = '';
  score: number = 0;
  termCount: number = 0;

  static of(docId: string, docTitle: string, chunkIndex: number, charStart: number, snippet: string,
    score: number, termCount: number): RetrievalHit {
    const hit = new RetrievalHit();
    hit.docId = docId;
    hit.docTitle = docTitle;
    hit.chunkIndex = chunkIndex;
    hit.charStart = charStart;
    hit.snippet = snippet;
    hit.score = score;
    hit.termCount = termCount;
    return hit;
  }
}

export interface KnowledgeDocRecord {
  id: string;
  title: string;
  source: string;
  createdAt: number;
  content: string;
}
