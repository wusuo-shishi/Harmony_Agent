import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { DocSource, KnowledgeChunk, KnowledgeDoc, KnowledgeDocRecord } from '../model/KnowledgeModels';
import { TextChunker } from './TextChunker';
import { SensitiveWordFilter } from './SensitiveWordFilter';

class SampleFileInfo {
  rawPath: string = '';
  title: string = '';

  static of(rawPath: string, title: string): SampleFileInfo {
    const info = new SampleFileInfo();
    info.rawPath = rawPath;
    info.title = title;
    return info;
  }
}

export class KnowledgeStore {
  static readonly shared: KnowledgeStore = new KnowledgeStore();
  static readonly maxDocChars: number = 500000;
  private static readonly sampleDir: string = 'knowledge';

  private ctx: common.UIAbilityContext | undefined = undefined;
  private dir: string = '';
  private docs: KnowledgeDoc[] = [];
  private chunks: KnowledgeChunk[] = [];
  private contentById: Map<string, string> = new Map<string, string>();
  private sampleFiles: SampleFileInfo[] = [
    SampleFileInfo.of('knowledge/multimodal_assistant.md', '鸿蒙多模态个人助理产品说明'),
    SampleFileInfo.of('knowledge/endside_rag.md', '端侧 RAG 与引用溯源说明'),
    SampleFileInfo.of('knowledge/schedule_helper.md', '日程管家与语音热词说明')
  ];

  isReady(): boolean {
    return this.ctx !== undefined;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.ctx !== undefined) {
      return;
    }
    this.ctx = context;
    this.dir = `${context.filesDir}/knowledge`;
    if (!fs.accessSync(this.dir)) {
      fs.mkdirSync(this.dir);
    }
    const indexPath: string = `${this.dir}/docs.json`;
    if (fs.accessSync(indexPath)) {
      try {
        const content: string = fs.readTextSync(indexPath);
        this.loadRecords(content);
      } catch (err) {
        this.docs = [];
        this.chunks = [];
        await this.seedSamples();
      }
    } else {
      await this.seedSamples();
    }
  }

  listDocs(): KnowledgeDoc[] {
    return this.docs.slice();
  }

  listChunks(): KnowledgeChunk[] {
    return this.chunks.slice();
  }

  docTitle(docId: string): string {
    for (let i = 0; i < this.docs.length; i++) {
      if (this.docs[i].id === docId) {
        return this.docs[i].title;
      }
    }
    return '';
  }

  getContent(docId: string): string {
    const content: string | undefined = this.contentById.get(docId);
    return content ?? '';
  }

  hasSampleTitle(title: string): boolean {
    for (let i = 0; i < this.docs.length; i++) {
      if (this.docs[i].source === DocSource.Sample && this.docs[i].title === title) {
        return true;
      }
    }
    return false;
  }

  private sourceOf(raw: string): DocSource {
    if (raw === 'sample') {
      return DocSource.Sample;
    }
    return DocSource.Imported;
  }

  private loadRecords(jsonText: string): void {
    const records = JSON.parse(jsonText) as KnowledgeDocRecord[];
    this.docs = [];
    this.chunks = [];
    this.contentById = new Map<string, string>();
    for (let i = 0; i < records.length; i++) {
      const rec: KnowledgeDocRecord = records[i];
      const doc: KnowledgeDoc = KnowledgeDoc.of(rec.id, rec.title, this.sourceOf(rec.source), rec.createdAt);
      doc.charCount = rec.content.length;
      const docChunks: KnowledgeChunk[] = TextChunker.buildChunks(rec.id, rec.content);
      doc.chunkCount = docChunks.length;
      this.docs.push(doc);
      this.chunks = this.chunks.concat(docChunks);
      this.contentById.set(rec.id, rec.content);
    }
  }

  private persist(): void {
    if (this.dir.length === 0) {
      return;
    }
    const records: KnowledgeDocRecord[] = [];
    for (let i = 0; i < this.docs.length; i++) {
      const doc: KnowledgeDoc = this.docs[i];
      const content: string = this.contentById.get(doc.id) ?? '';
      const rec: KnowledgeDocRecord = {
        id: doc.id,
        title: doc.title,
        source: doc.source === DocSource.Sample ? 'sample' : 'imported',
        createdAt: doc.createdAt,
        content: content
      };
      records.push(rec);
    }
    const indexPath: string = `${this.dir}/docs.json`;
    const file = fs.openSync(indexPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, JSON.stringify(records));
    } finally {
      fs.closeSync(file);
    }
  }

  private buildId(): string {
    return `${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  }

  private addDoc(title: string, source: DocSource, content: string): KnowledgeDoc {
    const doc: KnowledgeDoc = KnowledgeDoc.of(this.buildId(), title, source, Date.now());
    doc.charCount = content.length;
    const docChunks: KnowledgeChunk[] = TextChunker.buildChunks(doc.id, content);
    doc.chunkCount = docChunks.length;
    this.docs.push(doc);
    this.chunks = this.chunks.concat(docChunks);
    this.contentById.set(doc.id, content);
    this.persist();
    return doc;
  }

  importContent(title: string, content: string): KnowledgeDoc {
    if (title.trim().length === 0) {
      throw new Error('文档标题不能为空');
    }
    const trimmed: string = content.trim();
    if (trimmed.length === 0) {
      throw new Error('文档内容为空,未导入');
    }
    if (trimmed.length > KnowledgeStore.maxDocChars) {
      throw new Error(`文档过大(超过 ${KnowledgeStore.maxDocChars} 字),未导入`);
    }
    const hit = SensitiveWordFilter.firstHit(trimmed);
    if (hit !== undefined) {
      throw new Error(`文档包含敏感词「${hit.word}」,已拒绝导入`);
    }
    return this.addDoc(title.trim(), DocSource.Imported, trimmed);
  }

  private decodeText(data: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(data);
  }

  private async readSample(info: SampleFileInfo): Promise<boolean> {
    if (this.ctx === undefined) {
      return false;
    }
    if (this.hasSampleTitle(info.title)) {
      return false;
    }
    const data: Uint8Array = await this.ctx.resourceManager.getRawFileContent(info.rawPath);
    this.addDoc(info.title, DocSource.Sample, this.decodeText(data));
    return true;
  }

  async seedSamples(): Promise<number> {
    let added: number = 0;
    for (let i = 0; i < this.sampleFiles.length; i++) {
      const ok: boolean = await this.readSample(this.sampleFiles[i]);
      if (ok) {
        added++;
      }
    }
    return added;
  }

  async importFromUri(uri: string, title: string): Promise<KnowledgeDoc> {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    let content: string = '';
    try {
      const stat = fs.statSync(file.fd);
      const total: number = stat.size;
      if (total > KnowledgeStore.maxDocChars * 6) {
        throw new Error('文件过大,未导入');
      }
      const step: number = 65536;
      const parts: Uint8Array[] = [];
      let offset: number = 0;
      while (offset < total) {
        const remain: number = total - offset;
        const stepSize: number = remain > step ? step : remain;
        const segment = new ArrayBuffer(stepSize);
        const readCount: number = fs.readSync(file.fd, segment);
        if (readCount <= 0) {
          break;
        }
        parts.push(new Uint8Array(segment));
        offset += readCount;
      }
      const merged = new Uint8Array(offset);
      let copied: number = 0;
      for (let i = 0; i < parts.length; i++) {
        const part: Uint8Array = parts[i];
        for (let j = 0; j < part.length; j++) {
          merged[copied] = part[j];
          copied++;
        }
      }
      content = this.decodeText(merged);
    } finally {
      fs.closeSync(file);
    }
    return this.importContent(title, content);
  }

  removeDoc(docId: string): void {
    const remaining: KnowledgeDoc[] = [];
    for (let i = 0; i < this.docs.length; i++) {
      if (this.docs[i].id !== docId) {
        remaining.push(this.docs[i]);
      }
    }
    const remainingChunks: KnowledgeChunk[] = [];
    for (let i = 0; i < this.chunks.length; i++) {
      if (this.chunks[i].docId !== docId) {
        remainingChunks.push(this.chunks[i]);
      }
    }
    this.docs = remaining;
    this.chunks = remainingChunks;
    this.contentById.delete(docId);
    this.persist();
  }
}
