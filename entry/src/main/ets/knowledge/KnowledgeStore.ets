import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { DocSource, KnowledgeChunk, KnowledgeDoc, KnowledgeDocRecord, KnowledgeFolder,
  KnowledgeFolderRecord } from '../model/KnowledgeModels';
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
  private folders: KnowledgeFolder[] = [];
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
    this.loadFolders();
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
    this.ensureDefaultFolders();
  }

  listDocs(): KnowledgeDoc[] {
    return this.docs.slice();
  }

  listDocsInFolder(folderId: string): KnowledgeDoc[] {
    return this.docs.filter((doc: KnowledgeDoc): boolean => doc.folderId === folderId);
  }

  listFolders(parentId: string): KnowledgeFolder[] {
    return this.folders.filter((folder: KnowledgeFolder): boolean => folder.parentId === parentId);
  }

  allFolders(): KnowledgeFolder[] {
    return this.folders.slice();
  }

  createFolder(name: string, parentId: string): KnowledgeFolder {
    const clean: string = name.trim();
    if (clean.length === 0) {
      throw new Error('文件夹名称不能为空');
    }
    const siblings: KnowledgeFolder[] = this.listFolders(parentId);
    for (let i = 0; i < siblings.length; i++) {
      if (siblings[i].name === clean) {
        throw new Error('当前目录已存在同名文件夹');
      }
    }
    const folder: KnowledgeFolder = KnowledgeFolder.of(this.buildId(), parentId, clean.substring(0, 40), Date.now());
    this.folders.push(folder);
    this.persistFolders();
    return folder;
  }

  removeFolder(folderId: string): void {
    if (this.listFolders(folderId).length > 0 || this.listDocsInFolder(folderId).length > 0) {
      throw new Error('文件夹非空,请先移动或删除其中内容');
    }
    this.folders = this.folders.filter((folder: KnowledgeFolder): boolean => folder.id !== folderId);
    this.persistFolders();
  }

  renameFolder(folderId: string, name: string): void {
    const folder: KnowledgeFolder | undefined = this.folderById(folderId);
    const clean: string = name.trim();
    if (folder === undefined) {
      throw new Error('文件夹不存在');
    }
    if (clean.length === 0) {
      throw new Error('文件夹名称不能为空');
    }
    const siblings: KnowledgeFolder[] = this.listFolders(folder.parentId);
    for (let i = 0; i < siblings.length; i++) {
      if (siblings[i].id !== folderId && siblings[i].name === clean) {
        throw new Error('目标目录已存在同名文件夹');
      }
    }
    folder.name = clean.substring(0, 40);
    folder.updatedAt = Date.now();
    this.persistFolders();
  }

  moveFolder(folderId: string, targetParentId: string): void {
    const folder: KnowledgeFolder | undefined = this.folderById(folderId);
    if (folder === undefined) {
      throw new Error('文件夹不存在');
    }
    if (folderId === targetParentId || this.descendantFolderIds(folderId).indexOf(targetParentId) >= 0) {
      throw new Error('不能把文件夹移动到自身或其子文件夹中');
    }
    const siblings: KnowledgeFolder[] = this.listFolders(targetParentId);
    for (let i = 0; i < siblings.length; i++) {
      if (siblings[i].id !== folderId && siblings[i].name === folder.name) {
        throw new Error('目标目录已存在同名文件夹');
      }
    }
    folder.parentId = targetParentId;
    folder.updatedAt = Date.now();
    this.persistFolders();
  }

  renameDoc(docId: string, title: string): void {
    const doc: KnowledgeDoc | undefined = this.docById(docId);
    const clean: string = title.trim();
    if (doc === undefined) {
      throw new Error('文档不存在');
    }
    if (clean.length === 0) {
      throw new Error('文档名称不能为空');
    }
    const siblings: KnowledgeDoc[] = this.listDocsInFolder(doc.folderId);
    for (let i = 0; i < siblings.length; i++) {
      if (siblings[i].id !== docId && siblings[i].title === clean) {
        throw new Error('当前文件夹已存在同名文档');
      }
    }
    doc.title = clean.substring(0, 60);
    this.persist();
  }

  moveDoc(docId: string, targetFolderId: string): void {
    const doc: KnowledgeDoc | undefined = this.docById(docId);
    if (doc === undefined) {
      throw new Error('文档不存在');
    }
    if (targetFolderId.length > 0 && this.folderById(targetFolderId) === undefined) {
      throw new Error('目标文件夹不存在');
    }
    const targetDocs: KnowledgeDoc[] = this.listDocsInFolder(targetFolderId);
    for (let i = 0; i < targetDocs.length; i++) {
      if (targetDocs[i].id !== docId && targetDocs[i].title === doc.title) {
        throw new Error('目标文件夹已存在同名文档');
      }
    }
    doc.folderId = targetFolderId;
    this.persist();
  }

  folderPath(folderId: string): string {
    const names: string[] = [];
    let cursor: string = folderId;
    let guard: number = 0;
    while (cursor.length > 0 && guard < 20) {
      const folder: KnowledgeFolder | undefined = this.folderById(cursor);
      if (folder === undefined) {
        break;
      }
      names.unshift(folder.name);
      cursor = folder.parentId;
      guard++;
    }
    return names.length > 0 ? `我的知识库 / ${names.join(' / ')}` : '我的知识库';
  }

  documentPath(docId: string): string {
    for (let i = 0; i < this.docs.length; i++) {
      if (this.docs[i].id === docId) {
        return `${this.folderPath(this.docs[i].folderId)} / ${this.docs[i].title}`;
      }
    }
    return '';
  }

  descendantFolderIds(folderId: string): string[] {
    const result: string[] = [folderId];
    for (let cursor = 0; cursor < result.length; cursor++) {
      const children: KnowledgeFolder[] = this.listFolders(result[cursor]);
      for (let i = 0; i < children.length; i++) {
        if (result.indexOf(children[i].id) < 0) {
          result.push(children[i].id);
        }
      }
    }
    return result;
  }

  listChunksInFolder(folderId: string, includeChildren: boolean): KnowledgeChunk[] {
    const folderIds: string[] = includeChildren ? this.descendantFolderIds(folderId) : [folderId];
    const docIds: string[] = [];
    for (let i = 0; i < this.docs.length; i++) {
      if (folderIds.indexOf(this.docs[i].folderId) >= 0) {
        docIds.push(this.docs[i].id);
      }
    }
    return this.chunks.filter((chunk: KnowledgeChunk): boolean => docIds.indexOf(chunk.docId) >= 0);
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
      doc.folderId = rec.folderId ?? '';
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
        content: content,
        folderId: doc.folderId
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

  private addDoc(title: string, source: DocSource, content: string, folderId: string = ''): KnowledgeDoc {
    const doc: KnowledgeDoc = KnowledgeDoc.of(this.buildId(), title, source, Date.now());
    doc.charCount = content.length;
    doc.folderId = folderId;
    const docChunks: KnowledgeChunk[] = TextChunker.buildChunks(doc.id, content);
    doc.chunkCount = docChunks.length;
    this.docs.push(doc);
    this.chunks = this.chunks.concat(docChunks);
    this.contentById.set(doc.id, content);
    this.persist();
    return doc;
  }

  importContent(title: string, content: string, folderId: string = ''): KnowledgeDoc {
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
    const cleanTitle: string = title.trim();
    const siblings: KnowledgeDoc[] = this.listDocsInFolder(folderId);
    for (let i = 0; i < siblings.length; i++) {
      if (siblings[i].title === cleanTitle) {
        throw new Error('当前文件夹已存在同名文档');
      }
    }
    const hit = SensitiveWordFilter.firstHit(trimmed);
    if (hit !== undefined) {
      throw new Error(`文档包含敏感词「${hit.word}」,已拒绝导入`);
    }
    return this.addDoc(cleanTitle, DocSource.Imported, trimmed, folderId);
  }

  private decodeText(data: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(data);
  }

  private async readSample(info: SampleFileInfo, folderId: string): Promise<boolean> {
    if (this.ctx === undefined) {
      return false;
    }
    if (this.hasSampleTitle(info.title)) {
      return false;
    }
    const data: Uint8Array = await this.ctx.resourceManager.getRawFileContent(info.rawPath);
    this.addDoc(info.title, DocSource.Sample, this.decodeText(data), folderId);
    return true;
  }

  async seedSamples(): Promise<number> {
    let added: number = 0;
    let sampleFolderId: string = '';
    const rootFolders: KnowledgeFolder[] = this.listFolders('');
    for (let i = 0; i < rootFolders.length; i++) {
      if (rootFolders[i].name === '示例资料') {
        sampleFolderId = rootFolders[i].id;
        break;
      }
    }
    if (sampleFolderId.length === 0) {
      sampleFolderId = this.createFolder('示例资料', '').id;
    }
    for (let i = 0; i < this.sampleFiles.length; i++) {
      const ok: boolean = await this.readSample(this.sampleFiles[i], sampleFolderId);
      if (ok) {
        added++;
      }
    }
    return added;
  }

  async importFromUri(uri: string, title: string, folderId: string = ''): Promise<KnowledgeDoc> {
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
    return this.importContent(title, content, folderId);
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


  private folderById(id: string): KnowledgeFolder | undefined {
    for (let i = 0; i < this.folders.length; i++) {
      if (this.folders[i].id === id) {
        return this.folders[i];
      }
    }
    return undefined;
  }

  private docById(id: string): KnowledgeDoc | undefined {
    for (let i = 0; i < this.docs.length; i++) {
      if (this.docs[i].id === id) {
        return this.docs[i];
      }
    }
    return undefined;
  }

  private ensureDefaultFolders(): void {
    const names: string[] = ['学习资料', '项目资料', '日程与计划', '校园生活', '示例资料'];
    const roots: KnowledgeFolder[] = this.listFolders('');
    let changed: boolean = false;
    for (let i = 0; i < names.length; i++) {
      let exists: boolean = false;
      for (let j = 0; j < roots.length; j++) {
        if (roots[j].name === names[i]) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        this.folders.push(KnowledgeFolder.of(this.buildId(), '', names[i], Date.now()));
        changed = true;
      }
    }
    if (changed) {
      this.persistFolders();
    }
    const updatedRoots: KnowledgeFolder[] = this.listFolders('');
    let sampleFolderId: string = '';
    for (let i = 0; i < updatedRoots.length; i++) {
      if (updatedRoots[i].name === '示例资料') {
        sampleFolderId = updatedRoots[i].id;
        break;
      }
    }
    let docsChanged: boolean = false;
    if (sampleFolderId.length > 0) {
      for (let i = 0; i < this.docs.length; i++) {
        if (this.docs[i].source === DocSource.Sample && this.docs[i].folderId.length === 0) {
          this.docs[i].folderId = sampleFolderId;
          docsChanged = true;
        }
      }
    }
    if (docsChanged) {
      this.persist();
    }
  }

  private loadFolders(): void {
    const path: string = `${this.dir}/folders.json`;
    if (!fs.accessSync(path)) {
      this.folders = [];
      return;
    }
    try {
      const records = JSON.parse(fs.readTextSync(path)) as KnowledgeFolderRecord[];
      this.folders = records.map((record: KnowledgeFolderRecord): KnowledgeFolder => {
        const folder = KnowledgeFolder.of(record.id, record.parentId, record.name, record.createdAt);
        folder.updatedAt = record.updatedAt;
        return folder;
      });
    } catch (err) {
      this.folders = [];
    }
  }

  private persistFolders(): void {
    if (this.dir.length === 0) {
      return;
    }
    const records: KnowledgeFolderRecord[] = this.folders.map((folder: KnowledgeFolder): KnowledgeFolderRecord => ({
      id: folder.id, parentId: folder.parentId, name: folder.name,
      createdAt: folder.createdAt, updatedAt: folder.updatedAt
    }));
    const path: string = `${this.dir}/folders.json`;
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, JSON.stringify(records));
    } finally {
      fs.closeSync(file);
    }
  }
}
