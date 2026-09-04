import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { mediaquery } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { ChatMessage, ChatRole } from '../model/ChatModels';
import { LLMProvider } from '../provider/llm/LLMProvider';
import { ProviderHub } from '../provider/ProviderHub';
import { AsrService } from '../provider/asr/AsrService';
import { KnowledgeStore } from '../knowledge/KnowledgeStore';
import { CapabilityManager } from '../core/CapabilityManager';
import { AgentDeps, Orchestrator } from '../agent/Orchestrator';
import { AgentRunResult, AgentStep, AgentKind, StepState } from '../agent/AgentModels';
import { KnowledgeView } from '../common/KnowledgeView';

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
  private scroller: Scroller = new Scroller();
  private maxHistory: number = 20;
  private asr: AsrService = new AsrService();
  private orchestrator: Orchestrator = new Orchestrator();
  private agentDeps: AgentDeps | undefined = undefined;
  private agentGreetingShown: boolean = false;

  aboutToAppear(): void {
    ProviderHub.initFromConfig();
    this.registerWideMode();
    const greeting: ChatMessage = ChatMessage.of(ChatRole.Assistant,
      '你好,我是 OpenHarmonyAgent(当前后端:' + ProviderHub.llmProvider().providerName + ')。\n' +
      '支持三类智能体,直接输入即可自动路由:\n' +
      '· 学习助手:如「引用溯源是什么」→ 检索知识库+引用回答\n' +
      '· 日程管家:如「明天下午3点开组会提醒我」\n' +
      '· 文档处理:点下方【识图】拍照/相册→OCR→总结\n' +
      '点右上角「知识库」可管理文档。');
    this.appendMessage(greeting);
  }

  aboutToDisappear(): void {
    this.unregisterWideMode();
  }

  private registerWideMode(): void {
    const listener = mediaquery.matchMediaSync('(width >= 840vp)');
    this.wideListener = listener;
    this.isWide = listener.matches;
    listener.on('change', (result: mediaquery.MediaQueryResult) => {
      this.isWide = result.matches;
    });
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
    }
    return this.agentDeps;
  }

  private appendMessage(msg: ChatMessage): void {
    const next: ChatMessage[] = this.messages.concat(msg);
    this.messages = next;
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
      this.inputText = text;
    }, (text: string): void => {
      this.inputText = text;
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
    this.scrollToBottom();
    try {
      const result: AgentRunResult = await this.orchestrator.execute(text, deps, (steps: AgentStep[]): void => {
        this.renderSteps(steps);
        this.scrollToBottom();
      });
      this.agentTitle = this.agentNameOf(result.kind);
      if (result.answer.trim().length > 0) {
        this.appendMessage(ChatMessage.of(ChatRole.Assistant, result.answer));
      }
      this.agentSteps = [];
    } catch (err) {
      this.agentSteps = [];
      this.appendMessage(ChatMessage.of(ChatRole.Assistant, '智能体执行失败,请稍后重试。'));
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
    const text: string = this.inputText.trim();
    if (text.length === 0 || this.loading || this.agentRunning) {
      return;
    }
    this.inputText = '';
    this.appendMessage(ChatMessage.of(ChatRole.User, text));
    await this.runAgent(text);
  }

  private async onPickAndRecognize(): Promise<void> {
    if (this.agentRunning || this.loading) {
      return;
    }
    if (this.agentDeps !== undefined) {
      this.agentDeps.imageUri = '';
    }
    const deps: AgentDeps = this.ensureAgentDeps();
    let uri: string = '';
    if (CapabilityManager.isEmulator()) {
      // 模拟器无相机/OCR:使用内置示例文本走完整流程
      this.appendMessage(ChatMessage.of(ChatRole.User, '识图:拍一下这个文档,帮我总结重点'));
      await this.runAgent('拍一下这个文档,帮我总结重点');
      return;
    }
    try {
      const pickerInstance = new photoAccessHelper.PhotoViewPicker();
      const opts: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      };
      const result: photoAccessHelper.PhotoSelectResult = await pickerInstance.select(opts);
      if (result.photoUris.length > 0) {
        uri = result.photoUris[0];
      }
    } catch (err) {
      this.showToast('取消或无法打开相册');
      return;
    }
    if (uri.length === 0) {
      this.showToast('未选择图片');
      return;
    }
    deps.imageUri = uri;
    this.appendMessage(ChatMessage.of(ChatRole.User, '识图:对所选图片做 OCR 并总结要点'));
    await this.runAgent('拍一下这个文档,帮我总结重点');
  }

  @Builder
  StepRow(step: AgentStep) {
    Row() {
      if (step.state === StepState.Running) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color('#0A59F7')
      } else if (step.state === StepState.Failed) {
        Text('✕')
          .fontSize(13)
          .fontColor('#E84026')
          .width(16)
      } else {
        Text('✓')
          .fontSize(13)
          .fontColor('#10A37F')
          .width(16)
      }
      Column() {
        Text(step.title)
          .fontSize(13)
          .fontColor('#1A1A1A')
          .width('100%')
        if (step.detail.length > 0) {
          Text(step.detail)
            .fontSize(11)
            .fontColor('#8A8A8E')
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
          .fontColor('#0A59F7')
          .layoutWeight(1)
        if (this.agentRunning) {
          Text('执行中…')
            .fontSize(11)
            .fontColor('#8A8A8E')
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ bottom: 4 })
      ForEach(this.agentSteps, (step: AgentStep) => {
        this.StepRow(step)
      }, (step: AgentStep) => step.title)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#F2F6FF')
    .borderRadius(12)
    .padding(12)
  }

  @Builder
  ChatColumn() {
    Column() {
      List({ space: 8, scroller: this.scroller }) {
        ForEach(this.messages, (msg: ChatMessage) => {
          ListItem() {
            Row() {
              if (msg.role === ChatRole.User) {
                Row() {
                  Text(msg.content)
                    .fontSize(16)
                    .fontColor('#FFFFFF')
                    .lineHeight(22)
                    .copyOption(CopyOptions.LocalDevice)
                }
                .constraintSize({ maxWidth: '76%' })
                .backgroundColor('#0A59F7')
                .borderRadius(14)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              } else {
                Row() {
                  Text(msg.content)
                    .fontSize(16)
                    .fontColor('#1A1A1A')
                    .lineHeight(22)
                    .copyOption(CopyOptions.LocalDevice)
                }
                .constraintSize({ maxWidth: '88%' })
                .backgroundColor('#FFFFFF')
                .borderRadius(14)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              }
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
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      Row({ space: 8 }) {
        Button(this.voiceOn ? '停止' : '语音')
          .height(44)
          .backgroundColor(this.voiceOn ? '#E84026' : '#5B7CFA')
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.toggleVoice();
          })
        Button('识图')
          .height(44)
          .backgroundColor('#10A37F')
          .fontColor('#FFFFFF')
          .enabled(!this.agentRunning)
          .onClick(() => {
            this.onPickAndRecognize();
          })
        TextInput({ placeholder: this.voiceOn ? '聆听中,请说话…' : '输入消息…', text: this.inputText })
          .layoutWeight(1)
          .height(44)
          .fontSize(16)
          .onChange((value: string) => {
            this.inputText = value;
          })
          .onSubmit((enterKey: EnterKeyType) => {
            this.onSend();
          })
        Button(this.loading || this.agentRunning ? '…' : '发送')
          .height(44)
          .enabled(!this.loading && !this.agentRunning)
          .onClick(() => {
            this.onSend();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 12 })
      .backgroundColor('#F1F3F5')
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
          .fontColor('#1A1A1A')
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 6 })
      KnowledgeView({ embedded: true })
        .layoutWeight(1)
    }
    .width('38%')
    .height('100%')
    .border({ width: { left: 1 }, color: '#E2E4E8' })
    .backgroundColor('#F7F8FA')
  }

  build() {
    Column() {
      Row() {
        Text('OpenHarmonyAgent')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .layoutWeight(1)
        Text('知识库')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .padding({ left: 12, right: 4, top: 6, bottom: 6 })
          .onClick(() => {
            this.openKnowledge();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .backgroundColor('#0A59F7')

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
    .backgroundColor('#F1F3F5')
  }
}
