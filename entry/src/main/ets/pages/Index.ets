import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { KeyboardAvoidMode, mediaquery, display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { ChatMessage, ChatRole } from '../model/ChatModels';
import { SessionCodec } from '../core/SessionCodec';
import { LLMProvider } from '../provider/llm/LLMProvider';
import { ProviderHub } from '../provider/ProviderHub';
import { AsrService } from '../provider/asr/AsrService';
import { KnowledgeStore } from '../knowledge/KnowledgeStore';
import { CapabilityManager } from '../core/CapabilityManager';
import { AgentDeps, Orchestrator } from '../agent/Orchestrator';
import { AgentRunResult, AgentStep, AgentKind, StepState } from '../agent/AgentModels';
import { KnowledgeView } from '../common/KnowledgeView';
import { MarkdownText } from '../common/MarkdownText';
import { UiTheme } from '../common/UiTheme';

interface PermissionRequest {
  authResults: number[];
}

@Entry
@Component
struct Index {
  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  @State loading: boolean = false;
  @State voiceOn: boolean = false;
  @State agentRunning: boolean = false;
  @State agentTitle: string = '';
  @State isWide: boolean = false;
  private wideListener: mediaquery.MediaQueryListener | undefined = undefined;
  @State agentSteps: AgentStep[] = [];
  @State streamingText: string = '';
  @State streamingVisible: boolean = false;
  @State pendingImages: string[] = [];
  @StorageProp('kbHeightPx') kbHeightPx: number = 0;
  @State bubbleCapVp: number = 420;
  private scroller: Scroller = new Scroller();
  private maxHistory: number = 20;
  private asr: AsrService = new AsrService();
  private orchestrator: Orchestrator = new Orchestrator();
  private agentDeps: AgentDeps | undefined = undefined;
  private agentGreetingShown: boolean = false;

  aboutToAppear(): void {
    try {
      // 禁止系统整体上抬避让(会把顶栏顶出屏幕),改由 EntryAbility 监听键盘高度手动抬起输入条
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    } catch (err) {
    }
    ProviderHub.initFromConfig();
    this.registerWideMode();
    const ctx = this.context();
    if (ctx !== undefined) {
      ctx.eventHub.on('continuationRestore', this.onContinuationRestore);
    }
    if (!this.tryRestoreSession()) {
      const greeting: ChatMessage = ChatMessage.of(ChatRole.Assistant,
        '你好,我是 OpenHarmonyAgent(当前后端:' + ProviderHub.llmProvider().providerName + ')。\n' +
        '支持三类智能体,直接输入即可自动路由:\n' +
        '· 学习助手:如「引用溯源是什么」→ 检索知识库+引用回答\n' +
        '· 日程管家:如「明天下午3点开组会提醒我」\n' +
        '· 文档处理:点输入框右侧「+」选图/拍照→OCR→总结\n' +
        '· 语音输入:点输入框左侧的麦克风按钮\n' +
        '点右上角「知识库」可管理文档。');
      this.appendMessage(greeting);
    }
  }

  aboutToDisappear(): void {
    this.unregisterWideMode();
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    } catch (err) {
    }
    const ctx = this.context();
    if (ctx !== undefined) {
      ctx.eventHub.off('continuationRestore', this.onContinuationRestore);
    }
  }

  private onContinuationRestore = (): void => {
    if (this.tryRestoreSession()) {
      this.scrollToBottom();
    }
  };

  private tryRestoreSession(): boolean {
    const restored: string | undefined = AppStorage.get<string>('restoredSession');
    if (restored === undefined || restored.length === 0) {
      return false;
    }
    const restoredMsgs: ChatMessage[] = SessionCodec.decode(restored);
    if (restoredMsgs.length === 0) {
      AppStorage.delete('restoredSession');
      return false;
    }
    this.messages = restoredMsgs;
    AppStorage.delete('restoredSession');
    this.syncSessionSnapshot();
    return true;
  }

  private syncSessionSnapshot(): void {
    AppStorage.setOrCreate<string>('sessionSnapshot', SessionCodec.encode(this.messages));
  }

  private registerWideMode(): void {
    // 平板/折叠等大屏设备(非 phone)且宽度≥600vp 即双栏:平板横竖屏布局一致
    // 手机保持单栏(即使横屏宽度较大也不切双栏,避免误触/体验割裂)
    const listener = mediaquery.matchMediaSync('(width >= 600vp)');
    this.wideListener = listener;
    this.isWide = listener.matches && CapabilityManager.isLargeScreenDevice();
    this.computeBubbleCap();
    listener.on('change', (result: mediaquery.MediaQueryResult) => {
      this.isWide = result.matches && CapabilityManager.isLargeScreenDevice();
      this.computeBubbleCap();
    });
  }

  private computeBubbleCap(): void {
    try {
      const d = display.getDefaultDisplaySync();
      const widthPx: number = d.width;
      const density: number = d.densityPixels;
      const widthVp: number = density > 0 ? widthPx / density : 0;
      // 单栏取约 82% 屏宽,双栏左列约 50% 屏宽
      const cap: number = this.isWide ? widthVp * 0.5 : widthVp * 0.82;
      this.bubbleCapVp = Math.floor(cap);
    } catch (err) {
    }
  }

  private unregisterWideMode(): void {
    if (this.wideListener !== undefined) {
      this.wideListener.off('change');
      this.wideListener = undefined;
    }
  }

  private context(): common.UIAbilityContext {
    const host = this.getUIContext().getHostContext();
    if (host === undefined) {
      return getContext(this) as common.UIAbilityContext;
    }
    return host as common.UIAbilityContext;
  }

  private ensureAgentDeps(): AgentDeps {
    if (this.agentDeps === undefined) {
      this.agentDeps = new AgentDeps(ProviderHub.llmProvider(), ProviderHub.retrievalProvider(), KnowledgeStore.shared);
      this.agentDeps.uiContext = this.context();
      this.agentDeps.requestImage = async (): Promise<string> => {
        const picked: string = await this.pickPhoto();
        if (picked.length === 0) {
          this.showToast('未选择图片,已取消');
        }
        return picked;
      };
    }
    return this.agentDeps;
  }

  private appendMessage(msg: ChatMessage): void {
    const next: ChatMessage[] = this.messages.concat(msg);
    this.messages = next;
    this.syncSessionSnapshot();
    this.scrollToBottom();
  }


  private scrollToBottom(): void {
    const index: number = this.messages.length - 1;
    if (index < 0) {
      return;
    }
    setTimeout(() => {
      try {
        this.scroller.scrollToIndex(index);
      } catch (err) {
      }
    }, 80);
  }

  private openKnowledge(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/KnowledgePage' });
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (err) {
    }
  }

  private async ensureMicPermission(): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    try {
      const status: abilityAccessCtrl.GrantStatus =
        atManager.checkAccessTokenSync(this.context().applicationInfo.accessTokenId, 'ohos.permission.MICROPHONE');
      if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      }
    } catch (err) {
    }
    try {
      const grantResult = await atManager.requestPermissionsFromUser(this.context(), ['ohos.permission.MICROPHONE']);
      hilog.info(0x0000, 'MicPerm', 'grantResult=%{public}s', JSON.stringify(grantResult));
      return this.grantedOf(grantResult);
    } catch (err) {
      hilog.error(0x0000, 'MicPerm', 'request fail err=%{public}s', JSON.stringify(err));
      return false;
    }
  }

  private grantedOf(result: Object): boolean {
    const cast = result as PermissionRequest;
    if (cast.authResults.length > 0 && cast.authResults[0] === 0) {
      return true;
    }
    // authResults=-1 且 dialogShownResults=false 表示系统未弹授权框(如模拟器不支持)
    // 此时不必反复请求,交回上层给出友好提示
    return false;
  }

  private async toggleVoice(): Promise<void> {
    if (this.voiceOn) {
      this.voiceOn = false;
      await this.asr.stop();
      return;
    }
    const ok: boolean = await this.ensureMicPermission();
    if (!ok) {
      const hint: string = CapabilityManager.isEmulator()
        ? '模拟器无法授权麦克风,语音输入请使用真机(可先尝试设置中授权)'
        : '麦克风权限被拒绝,请到系统设置中为本应用开启麦克风权限';
      this.showToast(hint);
      return;
    }
    this.voiceOn = true;
    this.inputText = '';
    await this.asr.start((text: string): void => {
      if (this.voiceOn) {
        this.inputText = text;
      }
    }, (text: string): void => {
      if (this.voiceOn) {
        this.inputText = text;
      }
      this.voiceOn = false;
      this.asr.stop();
    }, (message: string): void => {
      this.voiceOn = false;
      this.showToast(message);
    });
  }

  private renderSteps(steps: AgentStep[]): void {
    this.agentSteps = steps.slice();
  }

  private async runAgent(text: string): Promise<void> {
    if (this.agentRunning) {
      return;
    }
    const deps: AgentDeps = this.ensureAgentDeps();
    if (deps.uiContext === undefined) {
      deps.uiContext = this.context();
    }
    if (!KnowledgeStore.shared.isReady()) {
      try {
        await KnowledgeStore.shared.init(this.context());
      } catch (err) {
      }
    }
    this.agentRunning = true;
    this.agentTitle = '智能体处理中…';
    this.agentSteps = [AgentStep.of('识别意图…')];
    this.streamingText = '';
    this.streamingVisible = false;
    this.scrollToBottom();
    try {
      const result: AgentRunResult = await this.orchestrator.execute(text, deps, (steps: AgentStep[]): void => {
        this.renderSteps(steps);
        this.scrollToBottom();
      }, (delta: string): void => {
        if (delta.length === 0) {
          return;
        }
        this.streamingText += delta;
        this.streamingVisible = true;
        this.scrollToBottom();
      });
      this.agentTitle = this.agentNameOf(result.kind);
      if (result.answer.trim().length > 0) {
        this.appendMessage(ChatMessage.of(ChatRole.Assistant, result.answer));
      }
      this.streamingText = '';
      this.streamingVisible = false;
      this.agentSteps = [];
    } catch (err) {
      this.agentSteps = [];
      this.appendMessage(ChatMessage.of(ChatRole.Assistant, '智能体执行失败,请稍后重试。'));
      this.streamingText = '';
      this.streamingVisible = false;
    } finally {
      this.agentRunning = false;
      this.agentTitle = '';
    }
  }

  private agentNameOf(kind: AgentKind): string {
    if (kind === AgentKind.Learning) {
      return '学习助手';
    }
    if (kind === AgentKind.Schedule) {
      return '日程管家';
    }
    if (kind === AgentKind.Document) {
      return '文档处理';
    }
    return '通用对话';
  }

  private async onSend(): Promise<void> {
    if (this.voiceOn) {
      this.voiceOn = false;
      await this.asr.stop();
    }
    const text: string = this.inputText.trim();
    const hasImages: boolean = this.pendingImages.length > 0;
    if ((text.length === 0 && !hasImages) || this.loading || this.agentRunning) {
      return;
    }
    this.inputText = '';
    if (this.agentDeps !== undefined) {
      this.agentDeps.imageUri = hasImages ? this.pendingImages[0] : '';
      this.agentDeps.imageUris = this.pendingImages.slice();
    } else {
      const deps = this.ensureAgentDeps();
      deps.imageUri = hasImages ? this.pendingImages[0] : '';
      deps.imageUris = this.pendingImages.slice();
    }
    const content: string = text.length > 0 ? text : (hasImages ? '识别图片并总结要点' : '');
    if (hasImages) {
      this.appendMessage(ChatMessage.ofImages(ChatRole.User, content, this.pendingImages));
    } else {
      this.appendMessage(ChatMessage.of(ChatRole.User, content));
    }
    const instruction: string = text.length > 0 ? text : '拍一下这个文档,帮我总结重点';
    this.pendingImages = [];
    await this.runAgent(instruction);
  }

  private async pickPhoto(): Promise<string> {
    if (CapabilityManager.isEmulator()) {
      return '';
    }
    try {
      const pickerInstance = new photoAccessHelper.PhotoViewPicker();
      const opts: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      };
      const result: photoAccessHelper.PhotoSelectResult = await pickerInstance.select(opts);
      if (result.photoUris.length > 0) {
        return result.photoUris[0];
      }
    } catch (err) {
    }
    return '';
  }

  private async pickImages(): Promise<void> {
    if (this.agentRunning || this.loading) {
      return;
    }
    if (CapabilityManager.isEmulator()) {
      // 模拟器无真实相册/OCR:用占位图,发送走内置样例文本
      this.appendPending('sample://demo_1');
      return;
    }
    try {
      const pickerInstance = new photoAccessHelper.PhotoViewPicker();
      const opts: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 9 - this.pendingImages.length
      };
      const result: photoAccessHelper.PhotoSelectResult = await pickerInstance.select(opts);
      for (let i = 0; i < result.photoUris.length; i++) {
        this.appendPending(result.photoUris[i]);
      }
    } catch (err) {
      this.showToast('取消或无法打开相册');
    }
  }

  private appendPending(uri: string): void {
    const next: string[] = this.pendingImages.concat(uri);
    this.pendingImages = next;
  }

  private removePending(index: number): void {
    const next: string[] = [];
    for (let i = 0; i < this.pendingImages.length; i++) {
      if (i !== index) {
        next.push(this.pendingImages[i]);
      }
    }
    this.pendingImages = next;
  }

  @Builder
  StepRow(step: AgentStep) {
    Row() {
      if (step.state === StepState.Running) {
        LoadingProgress()
          .width(14)
          .height(14)
          .color(UiTheme.Accent)
      } else if (step.state === StepState.Failed) {
        Text('✕')
          .fontSize(10)
          .fontColor(UiTheme.Danger)
          .width(18)
          .height(18)
          .textAlign(TextAlign.Center)
          .backgroundColor(UiTheme.DangerSoft)
          .borderRadius(9)
      } else {
        Text('✓')
          .fontSize(10)
          .fontColor(UiTheme.Success)
          .width(18)
          .height(18)
          .textAlign(TextAlign.Center)
          .backgroundColor(UiTheme.SuccessSoft)
          .borderRadius(9)
      }
      Column() {
        Text(step.title)
          .fontSize(13)
          .fontColor(UiTheme.TextPrimary)
          .width('100%')
        if (step.detail.length > 0) {
          Text(step.detail)
            .fontSize(11)
            .fontColor(UiTheme.TextSubtle)
            .width('100%')
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 8 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  AgentPanel() {
    Column() {
      Row() {
        Text(this.agentTitle)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(UiTheme.Accent)
          .layoutWeight(1)
        if (this.agentRunning) {
          Text('执行中…')
            .fontSize(11)
            .fontColor(UiTheme.Accent)
            .backgroundColor(UiTheme.AccentSoft)
            .borderRadius(9)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ bottom: 6 })
      ForEach(this.agentSteps, (step: AgentStep) => {
        this.StepRow(step)
      }, (step: AgentStep) => step.title)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(UiTheme.Card)
    .border({ width: 1, color: '#E3E9F8' })
    .borderRadius(16)
    .padding(12)
    .margin({ top: 4, bottom: 4 })
    .shadow({ radius: 16, color: UiTheme.ShadowColor, offsetX: 0, offsetY: 4 })
  }

  @Builder
  MessageBubble(msg: ChatMessage) {
    Column() {
      if (msg.content.length > 0) {
        if (msg.role === ChatRole.User) {
          Text(msg.content)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .lineHeight(23)
            .wordBreak(WordBreak.BREAK_ALL)
            .constraintSize({ maxWidth: this.bubbleCapVp })
            .copyOption(CopyOptions.LocalDevice)
        } else {
          MarkdownText({ text: msg.content, maxWidthVp: this.bubbleCapVp })
        }
      }
      if (msg.imageUris.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(msg.imageUris.slice(0, 4), (uri: string) => {
            if (uri.startsWith('sample://')) {
              Column() {
                Text('[图片]')
                  .fontSize(12)
                  .fontColor(UiTheme.TextSubtle)
              }
              .width(70)
              .height(52)
              .justifyContent(FlexAlign.Center)
              .backgroundColor('#EEF1F7')
              .borderRadius(8)
              .margin(2)
            } else {
              Image(uri)
                .width(70)
                .height(52)
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
                .margin(2)
            }
          }, (uri: string) => uri)
          if (msg.imageUris.length > 4) {
            Text(`+${msg.imageUris.length - 4}`)
              .fontSize(14)
              .fontColor(UiTheme.TextSubtle)
              .margin({ left: 4 })
          }
        }
        .width('100%')
        .margin({ top: msg.content.length > 0 ? 6 : 0 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxWidth: this.bubbleCapVp })
    .backgroundColor(msg.role === ChatRole.User ? UiTheme.UserB : UiTheme.Card)
    .borderRadius(18)
    .border({ width: msg.role === ChatRole.User ? 0 : 1, color: UiTheme.Border })
    .padding({ left: 13, right: 13, top: 9, bottom: 9 })
    .shadow({ radius: 12, color: UiTheme.ShadowColor, offsetX: 0, offsetY: 3 })
  }

  @Builder
  ChatColumn() {
    Column() {
      List({ space: 10, scroller: this.scroller }) {
        ForEach(this.messages, (msg: ChatMessage) => {
          ListItem() {
            Row() {
              this.MessageBubble(msg)
            }
            .width('100%')
            .justifyContent(msg.role === ChatRole.User ? FlexAlign.End : FlexAlign.Start)
          }
        }, (msg: ChatMessage) => msg.id)

        if (this.agentSteps.length > 0) {
          ListItem() {
            this.AgentPanel()
          }
        }

        if (this.streamingVisible && this.streamingText.length > 0) {
          ListItem() {
            Row() {
              Text(this.streamingText)
                .fontSize(16)
                .fontColor(UiTheme.TextPrimary)
                .lineHeight(23)
                .wordBreak(WordBreak.BREAK_ALL)
                .copyOption(CopyOptions.LocalDevice)
            }
            .width(this.bubbleCapVp)
            .backgroundColor(UiTheme.Card)
            .border({ width: 1, color: UiTheme.Border })
            .borderRadius(18)
            .padding({ left: 13, right: 13, top: 9, bottom: 9 })
            .shadow({ radius: 12, color: UiTheme.ShadowColor, offsetX: 0, offsetY: 3 })
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 12, bottom: 6 })
      .scrollBar(BarState.Off)

      if (this.pendingImages.length > 0) {
        Column() {
          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.pendingImages, (uri: string, idx: number) => {
                Stack({ alignContent: Alignment.TopEnd }) {
                  if (uri.startsWith('sample://')) {
                    Column() {
                      Text('[图片]')
                        .fontSize(13)
                        .fontColor(UiTheme.TextSubtle)
                    }
                    .width(64)
                    .height(64)
                    .justifyContent(FlexAlign.Center)
                    .backgroundColor('#EEF1F7')
                    .borderRadius(10)
                  } else {
                    Image(uri)
                      .width(64)
                      .height(64)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(8)
                  }
                  Text('×')
                    .fontSize(13)
                    .fontColor('#FFFFFF')
                    .width(18)
                    .height(18)
                    .textAlign(TextAlign.Center)
                    .backgroundColor('#80000000')
                    .borderRadius(9)
                    .onClick(() => {
                      this.removePending(idx);
                    })
                }
                .width(64)
                .height(64)
              }, (uri: string, idx: number) => `${uri}_${idx}`)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .width('100%')

          Text('已选 ' + this.pendingImages.length + ' 张,可继续输入文字后一并发送')
            .fontSize(11)
            .fontColor(UiTheme.TextSubtle)
            .width('100%')
            .margin({ top: 4 })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 6, bottom: 2 })
        .backgroundColor(UiTheme.Bg)
      }

      Row({ space: 8 }) {
        Button() {
          Image($r('app.media.ic_mic'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
        }
        .width(42)
        .height(42)
        .type(ButtonType.Circle)
        .backgroundColor(this.voiceOn ? UiTheme.Danger : '#4C6EF5')
        .onClick(() => {
          this.toggleVoice();
        })
        TextInput({ placeholder: this.voiceOn ? '聆听中,请说话…' : '输入消息…', text: this.inputText })
          .layoutWeight(1)
          .height(42)
          .fontSize(16)
          .fontColor(UiTheme.TextPrimary)
          .placeholderColor('#8A94A6')
          .backgroundColor('#EEF2F9')
          .border({ width: 1, color: '#D9E0EC' })
          .borderRadius(21)
          .onChange((value: string) => {
            this.inputText = value;
          })
          .onSubmit((enterKey: EnterKeyType) => {
            this.onSend();
          })
        Button() {
          Image($r('app.media.ic_plus'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
        }
        .width(42)
        .height(42)
        .type(ButtonType.Circle)
        .backgroundColor(UiTheme.SuccessSoft)
        .enabled(!this.agentRunning)
        .onClick(() => {
          this.pickImages();
        })
        Button(this.loading || this.agentRunning ? '…' : '发送')
          .height(42)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .backgroundColor('#4C6EF5')
          .borderRadius(21)
          .enabled(!this.loading && !this.agentRunning)
          .onClick(() => {
            this.onSend();
          })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .margin({ left: 10, right: 10, bottom: this.kbHeightPx > 0 ? `${this.kbHeightPx}px` : 10 })
      .backgroundColor(UiTheme.Card)
      .border({ width: 1, color: UiTheme.Border })
      .borderRadius(24)
      .shadow({ radius: 16, color: UiTheme.ShadowColor, offsetX: 0, offsetY: 4 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  KnowledgePane() {
    Column() {
      Row() {
        Text('知识库')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(UiTheme.TextPrimary)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 6 })
      KnowledgeView({ embedded: true })
        .layoutWeight(1)
    }
    .width('38%')
    .height('100%')
    .border({ width: { left: 1 }, color: UiTheme.Border })
    .backgroundColor(UiTheme.Bg)
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('OpenHarmonyAgent')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
          Text('鸿蒙原生智能 · 多模态个人助理')
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.75)')
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('知识库')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor('rgba(255,255,255,0.18)')
          .borderRadius(17)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .onClick(() => {
            this.openKnowledge();
          })
      }
      .width('100%')
      .padding({ left: 18, right: 16, top: 16, bottom: 15 })
      .alignItems(VerticalAlign.Center)
      .linearGradient({ angle: 135, colors: [[UiTheme.HdrA, 0.0], [UiTheme.HdrB, 1.0]] })

      if (this.isWide) {
        Row() {
          Column() {
            this.ChatColumn()
          }
          .layoutWeight(1)
          .height('100%')
          this.KnowledgePane()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Column() {
          this.ChatColumn()
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(UiTheme.Bg)
  }
}
