import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { DocSource, KnowledgeDoc, KnowledgeFolder, RetrievalHit } from '../model/KnowledgeModels';
import { KnowledgeStore } from '../knowledge/KnowledgeStore';
import { SensitiveWordFilter } from '../knowledge/SensitiveWordFilter';
import { RetrievalProvider } from '../provider/retrieval/RetrievalProvider';
import { Bm25Retrieval } from '../provider/retrieval/Bm25Retrieval';
import { ProviderHub } from '../provider/ProviderHub';
import { RetrievalConfig } from '../provider/retrieval/RetrievalConfig';
import { UiTheme } from './UiTheme';

interface KnowledgeDialogResult {
  index: number;
}

@Component
export struct KnowledgeView {
  @State docs: KnowledgeDoc[] = [];
  @State hits: RetrievalHit[] = [];
  @State query: string = '';
  @State searching: boolean = false;
  @State importing: boolean = false;
  @State tip: string = '';
  @State previewTitle: string = '';
  @State previewContent: string = '';
  @State previewVisible: boolean = false;
  @State folders: KnowledgeFolder[] = [];
  @State currentFolderId: string = '';
  @State folderPath: string = '我的知识库';
  @State newFolderName: string = '';
  @State creatingFolder: boolean = false;
  @State searchAllFolders: boolean = false;
  @State manageVisible: boolean = false;
  @State manageKind: string = '';
  @State manageId: string = '';
  @State manageName: string = '';
  @State moveVisible: boolean = false;
  @State destinations: KnowledgeFolder[] = [];
  @Prop embedded: boolean = false;
  private store: KnowledgeStore = KnowledgeStore.shared;

  aboutToAppear(): void {
    this.refreshDocs();
  }

  private context(): common.UIAbilityContext {
    const host = this.getUIContext().getHostContext();
    if (host === undefined) {
      return getContext(this) as common.UIAbilityContext;
    }
    return host as common.UIAbilityContext;
  }

  async refreshDocs(): Promise<void> {
    if (!this.store.isReady()) {
      try {
        await this.store.init(this.context());
      } catch (err) {
        this.showToast('知识库初始化失败');
        return;
      }
    }
    this.refreshCurrentFolder();
  }

  private refreshCurrentFolder(): void {
    this.docs = this.store.listDocsInFolder(this.currentFolderId);
    this.folders = this.store.listFolders(this.currentFolderId);
    this.folderPath = this.store.folderPath(this.currentFolderId);
  }

  private enterFolder(folder: KnowledgeFolder): void {
    this.currentFolderId = folder.id;
    this.clearResults();
    this.refreshCurrentFolder();
  }

  private goParentFolder(): void {
    if (this.currentFolderId.length === 0) {
      return;
    }
    const all: KnowledgeFolder[] = this.store.allFolders();
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === this.currentFolderId) {
        this.currentFolderId = all[i].parentId;
        break;
      }
    }
    this.clearResults();
    this.refreshCurrentFolder();
  }

  private createFolder(): void {
    try {
      this.store.createFolder(this.newFolderName, this.currentFolderId);
      this.newFolderName = '';
      this.creatingFolder = false;
      this.refreshCurrentFolder();
      this.showToast('文件夹已创建');
    } catch (err) {
      this.showToast(err instanceof Error ? err.message : '创建文件夹失败');
    }
  }

  private removeFolder(folderId: string): void {
    try {
      this.store.removeFolder(folderId);
      this.refreshCurrentFolder();
      this.showToast('文件夹已删除');
    } catch (err) {
      this.showToast(err instanceof Error ? err.message : '删除文件夹失败');
    }
  }

  private manageFolder(folder: KnowledgeFolder): void {
    this.manageKind = 'folder';
    this.manageId = folder.id;
    this.manageName = folder.name;
    this.destinations = this.store.allFolders();
    this.moveVisible = false;
    this.manageVisible = true;
  }

  private manageDoc(doc: KnowledgeDoc): void {
    this.manageKind = 'doc';
    this.manageId = doc.id;
    this.manageName = doc.title;
    this.destinations = this.store.allFolders();
    this.moveVisible = false;
    this.manageVisible = true;
  }

  private closeManage(): void {
    this.manageVisible = false;
    this.moveVisible = false;
    this.manageId = '';
    this.manageName = '';
  }

  private renameManaged(): void {
    try {
      if (this.manageKind === 'folder') {
        this.store.renameFolder(this.manageId, this.manageName);
      } else {
        this.store.renameDoc(this.manageId, this.manageName);
      }
      this.refreshCurrentFolder();
      this.closeManage();
      this.showToast('名称已更新');
    } catch (err) {
      this.showToast(err instanceof Error ? err.message : '重命名失败');
    }
  }

  private moveManaged(targetFolderId: string): void {
    try {
      if (this.manageKind === 'folder') {
        this.store.moveFolder(this.manageId, targetFolderId);
      } else {
        this.store.moveDoc(this.manageId, targetFolderId);
      }
      this.refreshCurrentFolder();
      this.closeManage();
      this.showToast('已移动到目标文件夹');
    } catch (err) {
      this.showToast(err instanceof Error ? err.message : '移动失败');
    }
  }

  private async deleteManaged(): Promise<void> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: this.manageKind === 'folder' ? '删除文件夹' : '删除文档',
        message: this.manageKind === 'folder' ?
          '仅空文件夹可以删除。删除后无法恢复，是否继续？' :
          '文档内容及其检索索引将一并删除，删除后无法恢复。',
        buttons: [
          { text: '取消', color: UiTheme.TextSubtle },
          { text: '删除', color: UiTheme.Danger }
        ]
      }) as KnowledgeDialogResult;
      if (result.index !== 1) {
        return;
      }
    } catch (err) {
      return;
    }
    try {
      if (this.manageKind === 'folder') {
        this.store.removeFolder(this.manageId);
      } else {
        this.store.removeDoc(this.manageId);
      }
      this.refreshCurrentFolder();
      this.clearResults();
      this.closeManage();
      this.showToast(this.manageKind === 'folder' ? '文件夹已删除' : '文档已删除');
    } catch (err) {
      this.showToast(err instanceof Error ? err.message : '删除失败');
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (err) {
    }
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  private formatTime(ts: number): string {
    const d = new Date(ts);
    return `${this.pad2(d.getMonth() + 1)}-${this.pad2(d.getDate())} ${this.pad2(d.getHours())}:${this.pad2(d.getMinutes())}`;
  }

  private sourceLabel(source: DocSource): string {
    return source === DocSource.Sample ? '示例' : '导入';
  }

  private clearResults(): void {
    this.hits = [];
  }

  async onSearch(): Promise<void> {
    const q: string = this.query.trim();
    if (q.length === 0) {
      this.showToast('请输入检索内容');
      return;
    }
    if (this.searching) {
      return;
    }
    const hit = SensitiveWordFilter.firstHit(q);
    if (hit !== undefined) {
      this.tip = `输入包含敏感词「${hit.word}」,已拦截本次检索`;
      return;
    }
    if (!this.store.isReady()) {
      await this.refreshDocs();
    }
    this.searching = true;
    this.tip = '';
    this.hits = [];
    try {
      const provider: RetrievalProvider = this.currentFolderId.length > 0 && !this.searchAllFolders ?
        new Bm25Retrieval(this.currentFolderId) : ProviderHub.retrievalProvider();
      if (!provider.available()) {
        this.tip = '真机高级检索能力未就绪,本次使用本地 BM25 检索';
      }
      const results: RetrievalHit[] = await provider.retrieve(q, RetrievalConfig.DEFAULT_TOP_K);
      if (results.length === 0) {
        this.tip = '未命中相关文档,可换关键词或先导入更多资料';
      } else {
        this.hits = results;
      }
    } catch (err) {
      try {
        const local: RetrievalProvider = new Bm25Retrieval();
        const fallback: RetrievalHit[] = await local.retrieve(q, RetrievalConfig.DEFAULT_TOP_K);
        this.hits = fallback;
        this.tip = fallback.length > 0 ? '主检索异常,已降级本地 BM25 检索' : '未命中相关文档,可换关键词或先导入更多资料';
      } catch (fallbackErr) {
        this.tip = '检索失败,请重试';
      }
    } finally {
      this.searching = false;
    }
  }

  async onRemoveDoc(docId: string): Promise<void> {
    this.store.removeDoc(docId);
    this.refreshCurrentFolder();
    this.hits = [];
    this.showToast('已删除文档');
  }

  private guessTitle(uri: string): string {
    const segments: string[] = uri.split('/');
    const rawName: string = segments.length > 0 ? segments[segments.length - 1] : '';
    let name: string = rawName.length > 0 ? rawName : `导入文档_${this.docs.length + 1}`;
    if (name.length > 40) {
      name = `导入文档_${this.docs.length + 1}`;
    }
    return name;
  }

  async onPickFile(): Promise<void> {
    if (this.importing) {
      return;
    }
    const docPicker = new picker.DocumentViewPicker();
    let uris: string[] = [];
    try {
      uris = await docPicker.select();
    } catch (err) {
      this.showToast('取消或无法打开文件选择器');
      return;
    }
    if (uris.length === 0) {
      return;
    }
    this.importing = true;
    try {
      let imported: number = 0;
      let failed: number = 0;
      let lastTitle: string = '';
      for (let i = 0; i < uris.length; i++) {
        try {
          const title: string = this.guessTitle(uris[i]);
          const doc = await this.store.importFromUri(uris[i], title, this.currentFolderId);
          lastTitle = doc.title;
          imported++;
        } catch (itemErr) {
          failed++;
        }
      }
      this.refreshCurrentFolder();
      if (imported === 1 && failed === 0) {
        this.showToast(`已导入:${lastTitle}`);
      } else {
        this.showToast(`导入完成:${imported} 篇成功${failed > 0 ? `，${failed} 篇失败` : ''}`);
      }
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : '未知错误';
      this.showToast(`导入失败:${msg}`);
    } finally {
      this.importing = false;
    }
  }

  async onSeedSamples(): Promise<void> {
    if (this.importing) {
      return;
    }
    if (!this.store.isReady()) {
      await this.refreshDocs();
    }
    this.importing = true;
    try {
      const added: number = await this.store.seedSamples();
      this.refreshCurrentFolder();
      if (added === 0) {
        this.showToast('示例文档已存在,无需重复恢复');
      } else {
        this.showToast(`已恢复 ${added} 篇示例文档`);
      }
    } catch (err) {
      this.showToast('恢复示例失败');
    } finally {
      this.importing = false;
    }
  }

  @Builder
  ResultCard(hit: RetrievalHit) {
    Column() {
      Row() {
        Text(hit.docTitle)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(UiTheme.Accent)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(`#分块 ${hit.chunkIndex + 1}`)
          .fontSize(11)
          .fontColor(UiTheme.Accent)
          .backgroundColor(UiTheme.AccentSoft)
          .borderRadius(9)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(hit.snippet)
        .fontSize(13)
        .fontColor(UiTheme.TextSecondary)
        .lineHeight(20)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 8 })
      Text(`命中 ${hit.termCount} 个关键词 · 得分 ${hit.score} · 原文偏移 ${hit.charStart}`)
        .fontSize(11)
        .fontColor(UiTheme.TextSubtle)
        .width('100%')
        .margin({ top: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(UiTheme.Card)
    .border({ width: 1, color: UiTheme.Border })
    .borderRadius(16)
    .padding(13)
    .shadow({ radius: 12, color: UiTheme.ShadowColor, offsetX: 0, offsetY: 3 })
  }

  @Builder
  FolderRow(folder: KnowledgeFolder) {
    Row({ space: 10 }) {
      Text('📁')
        .fontSize(22)
      Column() {
        Text(folder.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(UiTheme.TextPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.store.listFolders(folder.id).length} 个文件夹 · ${this.store.listDocsInFolder(folder.id).length} 篇文档`)
          .fontSize(11)
          .fontColor(UiTheme.TextSubtle)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => {
        this.enterFolder(folder);
      })
      Text('管理')
        .fontSize(11)
        .fontColor(UiTheme.Accent)
        .backgroundColor(UiTheme.AccentSoft)
        .borderRadius(9)
        .padding(6)
        .onClick(() => {
          this.manageFolder(folder);
        })
      Text('›')
        .fontSize(22)
        .fontColor(UiTheme.TextSubtle)
        .onClick(() => {
          this.enterFolder(folder);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .backgroundColor(UiTheme.Card)
    .border({ width: 1, color: UiTheme.Border })
    .borderRadius(16)
    .padding({ left: 13, right: 10, top: 11, bottom: 11 })
  }

  private openPreview(doc: KnowledgeDoc): void {
    this.previewTitle = doc.title;
    const content: string = this.store.getContent(doc.id);
    this.previewContent = content.length > 0 ? content : '(该文档内容为空)';
    this.previewVisible = true;
  }

  private closePreview(): void {
    this.previewVisible = false;
  }

  @Builder
  DocRow(doc: KnowledgeDoc) {
    Row() {
      Column() {
        Row() {
          Text(doc.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(UiTheme.TextPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.sourceLabel(doc.source))
            .fontSize(10)
            .fontColor(doc.source === DocSource.Sample ? UiTheme.Accent : UiTheme.Success)
            .backgroundColor(doc.source === DocSource.Sample ? UiTheme.AccentSoft : UiTheme.SuccessSoft)
            .borderRadius(5)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .margin({ left: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        Text(`${doc.chunkCount} 分块 · ${doc.charCount} 字 · ${this.formatTime(doc.createdAt)}`)
          .fontSize(11)
          .fontColor(UiTheme.TextSubtle)
          .width('100%')
          .margin({ top: 6 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .onClick(() => {
        this.openPreview(doc);
      })
      Text('管理')
        .fontSize(12)
        .fontColor(UiTheme.Accent)
        .backgroundColor(UiTheme.AccentSoft)
        .borderRadius(9)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .onClick(() => {
          this.manageDoc(doc);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .backgroundColor(UiTheme.Card)
    .border({ width: 1, color: UiTheme.Border })
    .borderRadius(16)
    .padding({ left: 13, right: 10, top: 11, bottom: 11 })
    .shadow({ radius: 12, color: UiTheme.ShadowColor, offsetX: 0, offsetY: 3 })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
      Row({ space: 8 }) {
        TextInput({ placeholder: '检索知识库,如:引用溯源', text: this.query })
          .layoutWeight(1)
          .height(42)
          .fontSize(15)
          .fontColor(UiTheme.TextPrimary)
          .placeholderColor('#7A8699')
          .backgroundColor(UiTheme.Card)
          .border({ width: 1, color: '#C3CDDF' })
          .borderRadius(21)
          .onChange((value: string) => {
            this.query = value;
          })
          .onSubmit(() => {
            this.onSearch();
          })
        Button(this.searching ? '…' : '检索')
          .height(42)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .backgroundColor('#4C6EF5')
          .borderRadius(21)
          .enabled(!this.searching)
          .onClick(() => {
            this.onSearch();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 4 })
      .backgroundColor(UiTheme.Bg)

      Row({ space: 8 }) {
        if (this.currentFolderId.length > 0) {
          Button('‹ 返回')
            .height(30)
            .fontSize(12)
            .fontColor(UiTheme.Accent)
            .backgroundColor(UiTheme.AccentSoft)
            .borderRadius(15)
            .onClick(() => {
              this.goParentFolder();
            })
        }
        Text(this.folderPath)
          .fontSize(12)
          .fontColor(UiTheme.TextSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.currentFolderId.length > 0) {
          Button(this.searchAllFolders ? '全库检索' : '当前目录')
            .height(30)
            .fontSize(10)
            .fontColor(this.searchAllFolders ? UiTheme.Success : UiTheme.Accent)
            .backgroundColor(this.searchAllFolders ? UiTheme.SuccessSoft : UiTheme.AccentSoft)
            .borderRadius(15)
            .onClick(() => {
              this.searchAllFolders = !this.searchAllFolders;
              this.clearResults();
              this.tip = this.searchAllFolders ? '检索范围已切换为全部知识库' : '检索范围为当前文件夹及其子文件夹';
            })
        }
        Button(this.creatingFolder ? '取消' : '新建文件夹')
          .height(30)
          .fontSize(11)
          .fontColor(UiTheme.Accent)
          .backgroundColor(UiTheme.AccentSoft)
          .borderRadius(15)
          .onClick(() => {
            this.creatingFolder = !this.creatingFolder;
            this.newFolderName = '';
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 4 })
      .alignItems(VerticalAlign.Center)

      if (this.creatingFolder) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '输入文件夹名称', text: this.newFolderName })
            .layoutWeight(1)
            .height(38)
            .fontSize(14)
            .backgroundColor(UiTheme.Card)
            .border({ width: 1, color: UiTheme.Border })
            .borderRadius(19)
            .onChange((value: string) => {
              this.newFolderName = value;
            })
            .onSubmit(() => {
              this.createFolder();
            })
          Button('创建')
            .height(38)
            .fontSize(13)
            .fontColor('#FFFFFF')
            .backgroundColor(UiTheme.Accent)
            .borderRadius(19)
            .onClick(() => {
              this.createFolder();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      }

      if (this.tip.length > 0) {
        Text(this.tip)
          .fontSize(12)
          .fontColor(UiTheme.Danger)
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })
          .backgroundColor(UiTheme.Bg)
      }

      List({ space: 10 }) {
        if (this.hits.length > 0) {
          ListItem() {
            Row() {
              Text('检索结果')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(UiTheme.TextPrimary)
              Text(`${this.hits.length}`)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(UiTheme.Accent)
                .backgroundColor(UiTheme.AccentSoft)
                .borderRadius(8)
                .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                .margin({ left: 6 })
              Text('清除')
                .fontSize(12)
                .fontColor(UiTheme.TextSubtle)
                .backgroundColor('#F1F4FA')
                .borderRadius(9)
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .onClick(() => {
                  this.clearResults();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .alignItems(VerticalAlign.Center)
            .padding({ left: 2, right: 2, top: 4, bottom: 2 })
          }
          ForEach(this.hits, (hit: RetrievalHit) => {
            ListItem() {
              this.ResultCard(hit)
            }
          }, (hit: RetrievalHit) => `${hit.docId}_${hit.chunkIndex}_${hit.charStart}`)
        }

        ListItem() {
          Row() {
            Text('当前目录')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.TextPrimary)
            Text(`${this.folders.length} 个文件夹 · ${this.docs.length} 篇文档`)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.Accent)
              .backgroundColor(UiTheme.AccentSoft)
              .borderRadius(8)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .margin({ left: 6 })
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .padding({ left: 2, right: 2, top: 8, bottom: 2 })
        }

        if (this.folders.length === 0 && this.docs.length === 0) {
          ListItem() {
            Column() {
              Text('文')
                .fontSize(26)
                .fontColor(UiTheme.Accent)
                .fontWeight(FontWeight.Medium)
                .backgroundColor(UiTheme.AccentSoft)
                .width(72)
                .height(72)
                .textAlign(TextAlign.Center)
                .borderRadius(36)
              Text(this.currentFolderId.length === 0 ? '知识库为空' : '当前文件夹为空')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(UiTheme.TextSecondary)
                .margin({ top: 14 })
              Text('可以新建子文件夹，或从本地导入 md/txt 文档')
                .fontSize(12)
                .fontColor(UiTheme.TextSubtle)
                .textAlign(TextAlign.Center)
                .margin({ top: 8 })
                .padding({ left: 28, right: 28 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 36, bottom: 36 })
          }
        }

        ForEach(this.folders, (folder: KnowledgeFolder) => {
          ListItem() {
            this.FolderRow(folder)
          }
        }, (folder: KnowledgeFolder) => folder.id)

        ForEach(this.docs, (doc: KnowledgeDoc) => {
          ListItem() {
            this.DocRow(doc)
          }
        }, (doc: KnowledgeDoc) => doc.id)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .scrollBar(BarState.Off)

      Row({ space: 12 }) {
        Button(this.importing ? '处理中…' : '恢复示例文档')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .enabled(!this.importing)
          .backgroundColor(UiTheme.Card)
          .fontColor(UiTheme.Accent)
          .border({ width: 1, color: UiTheme.BorderStrong })
          .borderRadius(22)
          .onClick(() => {
            this.onSeedSamples();
          })
        Button(this.importing ? '处理中…' : '导入文档')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .enabled(!this.importing)
          .backgroundColor('#4C6EF5')
          .fontColor('#FFFFFF')
          .borderRadius(22)
          .onClick(() => {
            this.onPickFile();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 12 })
      .backgroundColor(UiTheme.Bg)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(UiTheme.Bg)

      if (this.previewVisible) {
        Column() {
          Column() {
            Row() {
              Text(this.previewTitle)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(UiTheme.TextPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text('关闭')
                .fontSize(13)
                .fontColor(UiTheme.TextSecondary)
                .backgroundColor('#F1F4FA')
                .borderRadius(10)
                .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                .onClick(() => {
                  this.closePreview();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding({ bottom: 8 })

            Scroll() {
              Text(this.previewContent)
                .fontSize(14)
                .fontColor('#3A3F47')
                .lineHeight(23)
                .width('100%')
                .copyOption(CopyOptions.LocalDevice)
            }
            .width('100%')
            .layoutWeight(1)
            .align(Alignment.TopStart)
          }
          .width('92%')
          .height('80%')
          .backgroundColor(UiTheme.Card)
          .borderRadius(20)
          .padding(18)
          .shadow({ radius: 24, color: 'rgba(16,20,32,0.18)', offsetX: 0, offsetY: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('rgba(16,20,32,0.5)')
      }

      if (this.manageVisible) {
        Column() {
          Column() {
            Row() {
              Text(this.manageKind === 'folder' ? '管理文件夹' : '管理文档')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(UiTheme.TextPrimary)
                .layoutWeight(1)
              Text('关闭')
                .fontSize(13)
                .fontColor(UiTheme.TextSecondary)
                .padding(6)
                .onClick(() => {
                  this.closeManage();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Text('名称')
              .fontSize(12)
              .fontColor(UiTheme.TextSubtle)
              .width('100%')
              .margin({ top: 14, bottom: 5 })
            Row({ space: 8 }) {
              TextInput({ text: this.manageName, placeholder: '输入名称' })
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .backgroundColor(UiTheme.Bg)
                .border({ width: 1, color: UiTheme.Border })
                .borderRadius(10)
                .onChange((value: string) => {
                  this.manageName = value;
                })
              Button('保存')
                .height(40)
                .fontSize(13)
                .fontColor('#FFFFFF')
                .backgroundColor(UiTheme.Accent)
                .borderRadius(10)
                .onClick(() => {
                  this.renameManaged();
                })
            }
            .width('100%')

            Row() {
              Text('移动到…')
                .fontSize(14)
                .fontColor(UiTheme.Accent)
                .layoutWeight(1)
              Text(this.moveVisible ? '收起' : '选择目录')
                .fontSize(12)
                .fontColor(UiTheme.TextSubtle)
            }
            .width('100%')
            .padding({ top: 14, bottom: 10 })
            .onClick(() => {
              this.moveVisible = !this.moveVisible;
            })

            if (this.moveVisible) {
              List({ space: 4 }) {
                ListItem() {
                  Text('📁 我的知识库（根目录）')
                    .fontSize(13)
                    .fontColor(UiTheme.TextPrimary)
                    .width('100%')
                    .padding(10)
                    .backgroundColor(UiTheme.Bg)
                    .borderRadius(8)
                    .onClick(() => {
                      this.moveManaged('');
                    })
                }
                ForEach(this.destinations, (folder: KnowledgeFolder) => {
                  ListItem() {
                    Text(`📁 ${this.store.folderPath(folder.id)}`)
                      .fontSize(13)
                      .fontColor(folder.id === this.manageId ? UiTheme.TextSubtle : UiTheme.TextPrimary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                      .padding(10)
                      .backgroundColor(UiTheme.Bg)
                      .borderRadius(8)
                      .onClick(() => {
                        this.moveManaged(folder.id);
                      })
                  }
                }, (folder: KnowledgeFolder) => folder.id)
              }
              .width('100%')
              .height(190)
              .scrollBar(BarState.Auto)
            }

            Button(this.manageKind === 'folder' ? '删除空文件夹' : '删除文档')
              .width('100%')
              .height(40)
              .fontSize(13)
              .fontColor(UiTheme.Danger)
              .backgroundColor(UiTheme.DangerSoft)
              .borderRadius(10)
              .margin({ top: 14 })
              .onClick(() => {
                this.deleteManaged();
              })
          }
          .width('90%')
          .constraintSize({ maxWidth: 480 })
          .backgroundColor(UiTheme.Card)
          .borderRadius(20)
          .padding(18)
          .shadow({ radius: 24, color: 'rgba(16,20,32,0.18)', offsetX: 0, offsetY: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('rgba(16,20,32,0.5)')
      }
    }
    .width('100%')
    .height('100%')
  }
}
