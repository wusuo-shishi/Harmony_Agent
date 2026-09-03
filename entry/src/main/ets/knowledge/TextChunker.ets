import { KnowledgeChunk } from '../model/KnowledgeModels';

export class TextChunker {
  static readonly maxChunkChars: number = 500;

  static normalize(text: string): string {
    let normalized: string = text.split('\r\n').join('\n');
    normalized = normalized.split('\r').join('\n');
    return normalized;
  }

  static buildChunks(docId: string, content: string): KnowledgeChunk[] {
    const normalized: string = TextChunker.normalize(content);
    const lines: string[] = normalized.split('\n');
    const chunks: KnowledgeChunk[] = [];
    let lineStartGlobal: number = 0;
    let chunkStart: number = 0;
    let buffer: string = '';
    let chunkIndex: number = 0;

    const flush = (): void => {
      if (buffer.length > 0) {
        chunks.push(KnowledgeChunk.of(docId, chunkIndex, chunkStart, buffer));
        chunkIndex++;
        buffer = '';
      }
    };

    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      const lineEndGlobal: number = lineStartGlobal + line.length;
      const blank: boolean = line.trim().length === 0;
      if (blank) {
        flush();
      } else {
        if (buffer.length === 0) {
          chunkStart = lineStartGlobal;
        } else if (buffer.length + 1 + line.length > TextChunker.maxChunkChars) {
          flush();
          chunkStart = lineStartGlobal;
        }
        buffer = buffer.length > 0 ? `${buffer}\n${line}` : line;
      }
      lineStartGlobal = lineEndGlobal + 1;
    }
    flush();
    return chunks;
  }
}
