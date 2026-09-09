import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { DocSource, KnowledgeDoc, RetrievalHit } from '../model/KnowledgeModels';
import { KnowledgeStore } from '../knowledge/KnowledgeStore';
import { SensitiveWordFilter } from '../knowledge/SensitiveWordFilter';
import { RetrievalProvider } from '../provider/retrieval/RetrievalProvider';
import { Bm25Retrieval } from '../provider/retrieval/Bm25Retrieval';
import { ProviderHub } from '../provider/ProviderHub';
import { RetrievalConfig } from '../provider/retrieval/RetrievalConfig';

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
    this.docs = this.store.listDocs();
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
      const provider: RetrievalProvider = ProviderHub.retrievalProvider();
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
    this.docs = this.store.listDocs();
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
      const title: string = this.guessTitle(uris[0]);
      const doc = await this.store.importFromUri(uris[0], title);
      this.docs = this.store.listDocs();
      this.showToast(`已导入:${doc.title}`);
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
      this.docs = this.store.listDocs();
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
          .fontColor('#0A59F7')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(`#分块 ${hit.chunkIndex + 1}`)
          .fontSize(11)
          .fontColor('#8A8A8E')
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(hit.snippet)
        .fontSize(13)
        .fontColor('#3A3A3C')
        .lineHeight(19)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 6 })
      Text(`命中 ${hit.termCount} 个关键词 · 得分 ${hit.score} · 原文偏移 ${hit.charStart}`)
        .fontSize(11)
        .fontColor('#8A8A8E')
        .width('100%')
        .margin({ top: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .padding(12)
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
            .fontColor('#1A1A1A')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.sourceLabel(doc.source))
            .fontSize(10)
            .fontColor(doc.source === DocSource.Sample ? '#5B7CFA' : '#10A37F')
            .backgroundColor(doc.source === DocSource.Sample ? '#EEF2FF' : '#E8F7F1')
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .margin({ left: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        Text(`${doc.chunkCount} 分块 · ${doc.charCount} 字 · ${this.formatTime(doc.createdAt)}`)
          .fontSize(11)
          .fontColor('#8A8A8E')
          .width('100%')
          .margin({ top: 6 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('删除')
        .fontSize(12)
        .fontColor('#E84026')
        .padding({ left: 10, right: 4, top: 6, bottom: 6 })
        .onClick(() => {
          this.onRemoveDoc(doc.id);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .padding({ left: 12, right: 4, top: 10, bottom: 10 })
    .onClick(() => {
      this.openPreview(doc);
    })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        if (!this.embedded) {
        Row() {
          Text('知识库')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
          Text('检索后端:本地关键词')
            .fontSize(11)
            .fontColor('#D9E4FF')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .backgroundColor('#0A59F7')
        .alignItems(VerticalAlign.Center)
      }

      Row({ space: 8 }) {
        TextInput({ placeholder: '检索知识库,如:引用溯源', text: this.query })
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .onChange((value: string) => {
            this.query = value;
          })
          .onSubmit(() => {
            this.onSearch();
          })
        Button(this.searching ? '…' : '检索')
          .height(40)
          .enabled(!this.searching)
          .backgroundColor('#0A59F7')
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.onSearch();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10 })
      .backgroundColor('#F1F3F5')

      if (this.tip.length > 0) {
        Text(this.tip)
          .fontSize(12)
          .fontColor('#E84026')
          .width('100%')
          .padding({ left: 16, right: 16, top: 6 })
          .backgroundColor('#F1F3F5')
      }

      List({ space: 10 }) {
        if (this.hits.length > 0) {
          ListItem() {
            Row() {
              Text(`检索结果(${this.hits.length})`)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#5A5A5E')
                .layoutWeight(1)
              Text('清除')
                .fontSize(12)
                .fontColor('#0A59F7')
                .onClick(() => {
                  this.clearResults();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
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
            Text(`知识文档 (${this.docs.length})`)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#5A5A5E')
            if (this.docs.length > 0) {
              Text('点击文档标题区右侧删除')
                .fontSize(11)
                .fontColor('#B0B0B4')
                .margin({ left: 8 })
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: 2, right: 2, top: 8, bottom: 2 })
        }

        if (this.docs.length === 0) {
          ListItem() {
            Column() {
              Text('知识库为空')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor('#6A6A6E')
              Text('点击下方「恢复示例文档」一键导入演示资料,或「导入文档」从本地选择 md/txt 文件')
                .fontSize(12)
                .fontColor('#9A9A9E')
                .textAlign(TextAlign.Center)
                .margin({ top: 8 })
                .padding({ left: 24, right: 24 })
            }
            .width('100%')
            .padding({ top: 40, bottom: 40 })
          }
        }

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
          .enabled(!this.importing)
          .backgroundColor('#FFFFFF')
          .fontColor('#0A59F7')
          .borderWidth(1)
          .borderColor('#0A59F7')
          .onClick(() => {
            this.onSeedSamples();
          })
        Button(this.importing ? '处理中…' : '导入文档')
          .layoutWeight(1)
          .height(44)
          .enabled(!this.importing)
          .backgroundColor('#0A59F7')
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.onPickFile();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 12 })
      .backgroundColor('#F1F3F5')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F1F3F5')

      if (this.previewVisible) {
        Column() {
          Column() {
            Row() {
              Text(this.previewTitle)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1A1A1A')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text('关闭')
                .fontSize(13)
                .fontColor('#0A59F7')
                .padding({ left: 12, top: 4, bottom: 4 })
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
                .fontColor('#333336')
                .lineHeight(22)
                .width('100%')
                .copyOption(CopyOptions.LocalDevice)
            }
            .width('100%')
            .layoutWeight(1)
            .align(Alignment.TopStart)
          }
          .width('92%')
          .height('78%')
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .padding(16)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#80000000')
      }
    }
    .width('100%')
    .height('100%')
  }
}
