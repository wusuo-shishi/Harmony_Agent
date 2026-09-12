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
import { AgentRunResult, AgentStep, AgentKind, StepState, ScheduleDraft } from '../agent/AgentModels';
import { KnowledgeView } from '../common/KnowledgeView';
import { MarkdownText, MdParser } from '../common/MarkdownText';
import { UiTheme } from '../common/UiTheme';
import { ConversationStore, ConversationSummary } from '../core/ConversationStore';
import { UserSettings } from '../core/UserSettings';

interface PermissionRequest {
  authResults: number[];
}

interface DialogResult {
  index: number;
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
  @State knowledgeVisible: boolean = true;
  @State paneWv: number = 0;
  private wideListener: mediaquery.MediaQueryListener | undefined = undefined;
  @State agentSteps: AgentStep[] = [];
  @State streamingText: string = '';
  @State streamingVisible: boolean = false;
  @State pendingImages: string[] = [];
  @State atBottom: boolean = true;
  @State selectedMessageId: string = '';
  @State stopRequested: boolean = false;
  @State conversationPanelVisible: boolean = false;
  @State conversationItems: ConversationSummary[] = [];
  @State currentConversationId: string = '';
  @State conversationRenameText: string = '';
  @StorageProp('kbHeightPx') kbHeightPx: number = 0;
  @State bubbleCapVp: number = 420;
  private readonly maxPendingImages: number = 9;
  private scroller: Scroller = new Scroller();
  private maxHistory: number = 20;
  private asr: AsrService = new AsrService();
  private orchestrator: Orchestrator = new Orchestrator();
  private agentDeps: AgentDeps | undefined = undefined;
  private agentGreetingShown: boolean = false;
  private conversationStore: ConversationStore = new ConversationStore();

  aboutToAppear(): void {
    try {
      // 禁止系统整体上抬避让(会把顶栏顶出屏幕),改由 EntryAbility 监听键盘高度手动抬起输入条
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    } catch (err) {
    }
    ProviderHub.initFromConfig();
    UserSettings.load(this.context()).catch((): void => {
    });
    this.registerWideMode();
    const ctx = this.context();
    if (ctx !== undefined) {
      ctx.eventHub.on('continuationRestore', this.onContinuationRestore);
    }
    this.initConversations();
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
    try {
      if (this.tryRestoreSession()) {
        this.scrollToBottom();
      }
    } catch (err) {
      hilog.error(0x0000, 'Continuation', 'event restore failed: %{public}s', JSON.stringify(err));
      AppStorage.delete('restoredSession');
    }
  };

  private tryRestoreSession(): boolean {
    try {
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
      hilog.info(0x0000, 'Continuation', 'restore ok: msgs=%{public}d, chars=%{public}d',
        restoredMsgs.length, restored.length);
      return true;
    } catch (err) {
      hilog.error(0x0000, 'Continuation', 'restore failed: %{public}s', JSON.stringify(err));
      AppStorage.delete('restoredSession');
      return false;
    }
  }

  private syncSessionSnapshot(): void {
    // 接续参数只带最近 20 条且不带本机图片 URI(对端无法访问),避免超限与还原异常
    const maxTransfer: number = 20;
    const limited: ChatMessage[] = this.messages.length > maxTransfer
      ? this.messages.slice(this.messages.length - maxTransfer)
      : this.messages;
    AppStorage.setOrCreate<string>('sessionSnapshot', SessionCodec.encode(limited, false));
    if (this.currentConversationId.length > 0) {
      this.conversationStore.save(this.currentConversationId, this.messages).then((): void => {
        this.conversationItems = this.conversationStore.summaries();
      }).catch((): void => {
      });
    }
  }

  private async initConversations(): Promise<void> {
    try {
      await this.conversationStore.init(this.context());
      if (this.tryRestoreSession()) {
        this.currentConversationId = this.conversationStore.newId();
      } else {
        const savedId: string = this.conversationStore.currentId();
        const saved: ChatMessage[] = savedId.length > 0 ? this.conversationStore.load(savedId) : [];
        if (saved.length > 0) {
          this.currentConversationId = savedId;
          this.messages = saved;
        } else {
          this.currentConversationId = this.conversationStore.newId();
          this.messages = [this.createGreeting()];
        }
      }
      await this.conversationStore.save(this.currentConversationId, this.messages);
      this.conversationItems = this.conversationStore.summaries();
      this.syncSessionSnapshot();
      this.scrollToBottom();
    } catch (err) {
      if (this.messages.length === 0) {
        this.messages = [this.createGreeting()];
      }
      this.showToast('历史会话加载失败,本次对话仍可继续使用');
    }
  }

  private createGreeting(): ChatMessage {
    return ChatMessage.of(ChatRole.Assistant,
      '你好,我是 OpenHarmonyAgent(当前后端:' + ProviderHub.llmProvider().providerName + ')。\n' +
      '支持学习问答、日程管理、图片 OCR 与文档总结。直接输入需求,我会自动选择合适的助手。');
  }

  private async createConversation(): Promise<void> {
    if (this.agentRunning) {
      return;
    }
    this.currentConversationId = this.conversationStore.newId();
    this.messages = [this.createGreeting()];
    this.inputText = '';
    this.pendingImages = [];
    this.selectedMessageId = '';
    this.conversationPanelVisible = false;
    await this.conversationStore.save(this.currentConversationId, this.messages);
    this.conversationItems = this.conversationStore.summaries();
    this.syncSessionSnapshot();
  }

  private async switchConversation(id: string): Promise<void> {
    if (this.agentRunning || id === this.currentConversationId) {
      this.conversationPanelVisible = false;
      return;
    }
    const loaded: ChatMessage[] = this.conversationStore.load(id);
    if (loaded.length === 0) {
      this.showToast('该会话为空或已损坏');
      return;
    }
    this.currentConversationId = id;
    this.messages = loaded;
    this.inputText = '';
    this.pendingImages = [];
    this.selectedMessageId = '';
    this.conversationPanelVisible = false;
    this.syncSessionSnapshot();
    this.scrollToBottom();
  }

  private async removeConversation(id: string): Promise<void> {
    if (this.agentRunning) {
      return;
    }
    await this.conversationStore.remove(id);
    if (id === this.currentConversationId) {
      await this.createConversation();
      return;
    }
    this.conversationItems = this.conversationStore.summaries();
  }

  private async renameCurrentConversation(): Promise<void> {
    const title: string = this.conversationRenameText.trim();
    if (title.length === 0 || this.currentConversationId.length === 0) {
      this.showToast('请输入会话名称');
      return;
    }
    await this.conversationStore.rename(this.currentConversationId, title);
    this.conversationItems = this.conversationStore.summaries();
    this.conversationRenameText = '';
    this.showToast('会话已重命名');
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
      this.paneWv = Math.floor(widthVp * 0.36);
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
      this.agentDeps.confirmSchedule = async (draft: ScheduleDraft): Promise<boolean> => {
        return await this.confirmScheduleDraft(draft);
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

  private buildContext(): ChatMessage[] {
    const maxTurns: number = 8;
    const result: ChatMessage[] = [];
    const end: number = this.messages.length - 1;
    const start: number = end - maxTurns > 0 ? end - maxTurns : 0;
    for (let i = start; i < end; i++) {
      const m: ChatMessage = this.messages[i];
      const content: string = m.content.trim();
      if (content.length === 0) {
        continue;
      }
      const clipped: string = content.length > 500 ? content.substring(0, 500) : content;
      result.push(ChatMessage.of(m.role, clipped));
    }
    return result;
  }

  private async confirmScheduleDraft(draft: ScheduleDraft): Promise<boolean> {
    const start = new Date(draft.startTime);
    const end = new Date(draft.endTime);
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    const startText: string = `${start.getFullYear()}-${pad(start.getMonth() + 1)}-${pad(start.getDate())} ` +
      `${pad(start.getHours())}:${pad(start.getMinutes())}`;
    const endText: string = `${pad(end.getHours())}:${pad(end.getMinutes())}`;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: '确认创建日程',
        message: `标题:${draft.title}\n时间:${startText} - ${endText}\n提醒:提前 ${draft.reminderMinutes} 分钟`,
        buttons: [
          { text: '取消', color: UiTheme.TextSubtle },
          { text: '确认创建', color: UiTheme.Accent }
        ]
      }) as DialogResult;
      return result.index === 1;
    } catch (err) {
      return false;
    }
  }

  private toggleMessageActions(id: string): void {
    this.selectedMessageId = this.selectedMessageId === id ? '' : id;
  }

  private deleteMessage(id: string): void {
    const next: ChatMessage[] = [];
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].id !== id) {
        next.push(this.messages[i]);
      }
    }
    this.messages = next;
    this.selectedMessageId = '';
    this.syncSessionSnapshot();
    this.showToast('消息已删除');
  }

  private reuseUserMessage(msg: ChatMessage): void {
    this.inputText = msg.content;
    this.pendingImages = msg.imageUris.slice();
    this.selectedMessageId = '';
    this.showToast('内容已填入输入框');
  }

  private canRetryMessage(msg: ChatMessage): boolean {
    if (msg.role !== ChatRole.Assistant || this.messages.length < 2) {
      return false;
    }
    return this.messages[this.messages.length - 1].id === msg.id;
  }

  private async retryLastAssistant(msg: ChatMessage): Promise<void> {
    if (this.agentRunning || !this.canRetryMessage(msg)) {
      return;
    }
    let user: ChatMessage | undefined = undefined;
    for (let i = this.messages.length - 2; i >= 0; i--) {
      if (this.messages[i].role === ChatRole.User) {
        user = this.messages[i];
        break;
      }
    }
    if (user === undefined) {
      this.showToast('没有找到可重试的用户消息');
      return;
    }
    this.deleteMessageSilently(msg.id);
    const deps: AgentDeps = this.ensureAgentDeps();
    deps.imageUris = user.imageUris.slice();
    deps.imageUri = user.imageUris.length > 0 ? user.imageUris[0] : '';
    this.selectedMessageId = '';
    await this.runAgent(user.content);
  }

  private deleteMessageSilently(id: string): void {
    const next: ChatMessage[] = [];
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].id !== id) {
        next.push(this.messages[i]);
      }
    }
    this.messages = next;
    this.syncSessionSnapshot();
  }

  private stopGeneration(): void {
    if (!this.agentRunning) {
      return;
    }
    this.stopRequested = true;
    ProviderHub.llmProvider().cancelActive();
    this.streamingText = '';
    this.streamingVisible = false;
    this.agentSteps = [];
    this.agentTitle = '正在停止…';
    this.showToast('已停止显示本次回复');
  }


  private scrollToBottom(): void {
    this.atBottom = true;
    setTimeout(() => {
      try {
        this.scroller.scrollEdge(Edge.Bottom);
      } catch (err) {
      }
    }, 80);
  }

  private toggleKnowledge(): void {
    if (this.isWide) {
      this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, (): void => {
        this.knowledgeVisible = !this.knowledgeVisible;
      });
    } else {
      this.openKnowledge();
    }
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

  private friendlyError(err: Object): string {
    const raw: string = err instanceof Error ? err.message : `${err}`;
    const lower: string = raw.toLowerCase();
    if (lower.indexOf('401') >= 0 || lower.indexOf('403') >= 0 || lower.indexOf('api key') >= 0) {
      return 'AI 服务认证失败,请检查服务配置后重试。';
    }
    if (lower.indexOf('timeout') >= 0 || raw.indexOf('超时') >= 0) {
      return '请求超时,请检查网络后重试。';
    }
    if (lower.indexOf('network') >= 0 || lower.indexOf('connect') >= 0 || raw.indexOf('网络') >= 0) {
      return '当前网络不可用或服务无法连接,请稍后重试。';
    }
    if (raw.indexOf('权限') >= 0 || lower.indexOf('permission') >= 0) {
      return '缺少所需权限,请在系统设置中授权后重试。';
    }
    return '本次处理失败,请稍后重试或换一种说法。';
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
    deps.context = this.buildContext();
    if (!KnowledgeStore.shared.isReady()) {
      try {
        await KnowledgeStore.shared.init(this.context());
      } catch (err) {
      }
    }
    this.agentRunning = true;
    this.stopRequested = false;
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
        if (delta.length === 0 || this.stopRequested) {
          return;
        }
        this.streamingText += delta;
        this.streamingVisible = true;
        this.scrollToBottom();
      });
      this.agentTitle = this.agentNameOf(result.kind);
      if (!this.stopRequested && result.answer.trim().length > 0) {
        this.appendMessage(ChatMessage.of(ChatRole.Assistant, result.answer));
      }
      this.streamingText = '';
      this.streamingVisible = false;
      this.agentSteps = [];
    } catch (err) {
      this.agentSteps = [];
      if (!this.stopRequested) {
        this.appendMessage(ChatMessage.of(ChatRole.Assistant, this.friendlyError(err as Object)));
      }
      this.streamingText = '';
      this.streamingVisible = false;
    } finally {
      this.agentRunning = false;
      this.stopRequested = false;
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
    const remaining: number = this.maxPendingImages - this.pendingImages.length;
    if (remaining <= 0) {
      this.showToast(`最多只能添加 ${this.maxPendingImages} 张图片`);
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
        maxSelectNumber: remaining
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
    if (this.pendingImages.length >= this.maxPendingImages) {
      this.showToast(`最多只能添加 ${this.maxPendingImages} 张图片`);
      return;
    }
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

  private clearPendingImages(): void {
    this.pendingImages = [];
    this.showToast('已清空待发送图片');
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
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
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
    .onClick(() => {
      this.toggleMessageActions(msg.id);
    })
  }

  @Builder
  MessageActions(msg: ChatMessage) {
    Row({ space: 6 }) {
      if (msg.role === ChatRole.User) {
        Button('再次输入')
          .fontSize(11)
          .fontColor(UiTheme.Accent)
          .height(28)
          .backgroundColor(UiTheme.AccentSoft)
          .borderRadius(14)
          .onClick(() => {
            this.reuseUserMessage(msg);
          })
      } else if (this.canRetryMessage(msg)) {
        Button('重新生成')
          .fontSize(11)
          .fontColor(UiTheme.Accent)
          .height(28)
          .backgroundColor(UiTheme.AccentSoft)
          .borderRadius(14)
          .enabled(!this.agentRunning)
          .onClick(() => {
            this.retryLastAssistant(msg);
          })
      }
      Button('删除')
        .fontSize(11)
        .fontColor(UiTheme.Danger)
        .height(28)
        .backgroundColor(UiTheme.DangerSoft)
        .borderRadius(14)
        .enabled(!this.agentRunning)
        .onClick(() => {
          this.deleteMessage(msg.id);
        })
    }
    .margin({ top: 4 })
  }

  @Builder
  ChatColumn() {
    Column() {
      if (this.conversationPanelVisible) {
        Column() {
          Row() {
            Text('历史会话')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(UiTheme.TextPrimary)
              .layoutWeight(1)
            Button('新对话')
              .height(30)
              .fontSize(12)
              .fontColor('#FFFFFF')
              .backgroundColor(UiTheme.Accent)
              .borderRadius(15)
              .enabled(!this.agentRunning)
              .onClick(() => {
                this.createConversation();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Row({ space: 6 }) {
            TextInput({ placeholder: '重命名当前会话', text: this.conversationRenameText })
              .layoutWeight(1)
              .height(34)
              .fontSize(13)
              .backgroundColor(UiTheme.Bg)
              .borderRadius(17)
              .onChange((value: string) => {
                this.conversationRenameText = value;
              })
            Button('保存')
              .height(32)
              .fontSize(12)
              .fontColor(UiTheme.Accent)
              .backgroundColor(UiTheme.AccentSoft)
              .borderRadius(16)
              .onClick(() => {
                this.renameCurrentConversation();
              })
          }
          .width('100%')
          .margin({ top: 8 })

          if (this.conversationItems.length === 0) {
            Text('暂无历史会话')
              .fontSize(13)
              .fontColor(UiTheme.TextSubtle)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding(16)
          } else {
            List({ space: 4 }) {
              ForEach(this.conversationItems, (item: ConversationSummary) => {
                ListItem() {
                  Row({ space: 8 }) {
                    Column() {
                      Text(item.title)
                        .fontSize(14)
                        .fontColor(item.id === this.currentConversationId ? UiTheme.Accent : UiTheme.TextPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(this.formatConversationTime(item.updatedAt))
                        .fontSize(10)
                        .fontColor(UiTheme.TextSubtle)
                        .margin({ top: 2 })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    .onClick(() => {
                      this.switchConversation(item.id);
                    })
                    Text('删除')
                      .fontSize(11)
                      .fontColor(UiTheme.Danger)
                      .padding(6)
                      .onClick(() => {
                        this.removeConversation(item.id);
                      })
                  }
                  .width('100%')
                  .padding({ left: 10, right: 6, top: 8, bottom: 8 })
                  .backgroundColor(item.id === this.currentConversationId ? UiTheme.AccentSoft : UiTheme.Bg)
                  .borderRadius(10)
                }
              }, (item: ConversationSummary) => item.id)
            }
            .width('100%')
            .height(Math.min(260, this.conversationItems.length * 54))
            .margin({ top: 8 })
            .scrollBar(BarState.Auto)
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor(UiTheme.Card)
        .border({ width: 1, color: UiTheme.Border })
        .shadow({ radius: 12, color: UiTheme.ShadowColor, offsetY: 3 })
      }
      Stack({ alignContent: Alignment.BottomEnd }) {
        List({ space: 10, scroller: this.scroller }) {
        ForEach(this.messages, (msg: ChatMessage) => {
          ListItem() {
            Column() {
              Row() {
                this.MessageBubble(msg)
              }
              .width('100%')
              .justifyContent(msg.role === ChatRole.User ? FlexAlign.End : FlexAlign.Start)
              if (this.selectedMessageId === msg.id) {
                Row() {
                  this.MessageActions(msg)
                }
                .width('100%')
                .justifyContent(msg.role === ChatRole.User ? FlexAlign.End : FlexAlign.Start)
              }
            }
            .width('100%')
            .alignItems(msg.role === ChatRole.User ? HorizontalAlign.End : HorizontalAlign.Start)
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
              Text(MdParser.plain(this.streamingText))
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
      .height('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 6 })
      .scrollBar(BarState.Off)
      .onReachEnd(() => {
        this.atBottom = true;
      })
      .onDidScroll((offset: number, state: ScrollState) => {
        this.atBottom = this.scroller.isAtEnd();
      })
      .onScrollStop(() => {
        this.atBottom = this.scroller.isAtEnd();
      })

      if (!this.atBottom) {
        Button() {
          Image($r('app.media.ic_arrow_down'))
            .width(20)
            .height(20)
            .objectFit(ImageFit.Contain)
        }
        .width(40)
        .height(40)
        .type(ButtonType.Circle)
        .backgroundColor(UiTheme.Card)
        .border({ width: 1, color: UiTheme.Border })
        .shadow({ radius: 12, color: UiTheme.ShadowColor, offsetX: 0, offsetY: 3 })
        .margin({ right: 12, bottom: 12 })
        .onClick(() => {
          this.scrollToBottom();
        })
      }
      }
      .width('100%')
      .layoutWeight(1)

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
            .constraintSize({ minWidth: '100%' })
            .justifyContent(FlexAlign.Start)
          }
          .scrollable(ScrollDirection.Horizontal)
          .width('100%')

          Row() {
            Text('已选 ' + this.pendingImages.length + '/' + this.maxPendingImages + ' 张,可继续输入文字后一并发送')
              .fontSize(11)
              .fontColor(UiTheme.TextSubtle)
              .layoutWeight(1)
            Text('清空')
              .fontSize(11)
              .fontColor(UiTheme.Danger)
              .padding({ left: 10, top: 4, bottom: 4 })
              .onClick(() => {
                this.clearPendingImages();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
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
        TextArea({ placeholder: this.voiceOn ? '聆听中,请说话…' : '输入消息…', text: this.inputText })
          .layoutWeight(1)
          .constraintSize({ minHeight: 42, maxHeight: 120 })
          .fontSize(16)
          .fontColor(UiTheme.TextPrimary)
          .placeholderColor('#8A94A6')
          .backgroundColor('#EEF2F9')
          .border({ width: 1, color: '#D9E0EC' })
          .borderRadius(21)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .onChange((value: string) => {
            this.inputText = value;
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
        Button(this.agentRunning ? '停止' : (this.loading ? '…' : '发送'))
          .height(42)
          .fontSize(15)
          .fontColor('#FFFFFF')
          .backgroundColor(this.agentRunning ? UiTheme.Danger : '#4C6EF5')
          .borderRadius(21)
          .enabled(!this.loading)
          .onClick(() => {
            if (this.agentRunning) {
              this.stopGeneration();
            } else {
              this.onSend();
            }
          })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Bottom)
      .margin({ left: 10, right: 10, bottom: this.kbHeightPx > 0 ? `${this.kbHeightPx}px` : 10 })
      .backgroundColor(UiTheme.Card)
      .border({ width: 1, color: UiTheme.Border })
      .borderRadius(24)
      .shadow({ radius: 16, color: UiTheme.ShadowColor, offsetX: 0, offsetY: 4 })
    }
    .width('100%')
    .height('100%')
  }

  private formatConversationTime(timestamp: number): string {
    const date = new Date(timestamp);
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    return `${date.getMonth() + 1}-${date.getDate()} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
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
    .width('100%')
    .height('100%')
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
        Button() {
          Image($r('app.media.ic_history_chat'))
            .width(21)
            .height(21)
            .objectFit(ImageFit.Contain)
        }
          .width(38)
          .height(38)
          .type(ButtonType.Circle)
          .backgroundColor('rgba(255,255,255,0.18)')
          .margin({ right: 8 })
          .accessibilityText('历史会话')
          .onClick(() => {
            this.conversationPanelVisible = !this.conversationPanelVisible;
          })
        Button() {
          Image($r('app.media.ic_settings'))
            .width(21)
            .height(21)
            .objectFit(ImageFit.Contain)
        }
          .width(38)
          .height(38)
          .type(ButtonType.Circle)
          .backgroundColor('rgba(255,255,255,0.18)')
          .margin({ right: 8 })
          .accessibilityText('设置')
          .onClick(() => {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/SettingsPage' });
          })
        Button() {
          Image($r('app.media.ic_book'))
            .width(22)
            .height(22)
            .objectFit(ImageFit.Contain)
        }
        .width(38)
        .height(38)
        .type(ButtonType.Circle)
        .backgroundColor('rgba(255,255,255,0.18)')
        .accessibilityText('知识库')
        .onClick(() => {
          this.toggleKnowledge();
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
          Column() {
            this.KnowledgePane()
          }
          .width(this.knowledgeVisible ? this.paneWv : 0)
          .height('100%')
          .backgroundColor(UiTheme.Bg)
          .border({ width: { left: 1 }, color: UiTheme.Border })
          .clip(true)
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
