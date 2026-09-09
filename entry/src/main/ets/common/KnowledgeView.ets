import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { DocSource, KnowledgeDoc, RetrievalHit } from '../model/KnowledgeModels';
import { KnowledgeStore } from '../knowledge/KnowledgeStore';
import { SensitiveWordFilter } from '../knowledge/SensitiveWordFilter';
import { RetrievalProvider } from '../provider/retrieval/RetrievalProvider';
import { Bm25Retrieval } from '../provider/retrieval/Bm25Retrieval';
import { ProviderHub } from '../provider/ProviderHub';
import { RetrievalConfig } from '../provider/retrieval/RetrievalConfig';
import { UiTheme } from './UiTheme';

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
      Text('删除')
        .fontSize(12)
        .fontColor(UiTheme.Danger)
        .backgroundColor(UiTheme.DangerSoft)
        .borderRadius(9)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .onClick(() => {
          this.onRemoveDoc(doc.id);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .backgroundColor(UiTheme.Card)
    .border({ width: 1, color: UiTheme.Border })
    .borderRadius(16)
    .padding({ left: 13, right: 10, top: 11, bottom: 11 })
    .shadow({ radius: 12, color: UiTheme.ShadowColor, offsetX: 0, offsetY: 3 })
    .onClick(() => {
      this.openPreview(doc);
    })
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
            Text('知识文档')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(UiTheme.TextPrimary)
            Text(`${this.docs.length}`)
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

        if (this.docs.length === 0) {
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
              Text('知识库为空')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(UiTheme.TextSecondary)
                .margin({ top: 14 })
              Text('点击「恢复示例文档」一键导入演示资料,或「导入文档」从本地选择 md/txt 文件')
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
    }
    .width('100%')
    .height('100%')
  }
}
