import { ChatMessage, ChatRole } from '../model/ChatModels';
import { LLMProvider } from '../provider/llm/LLMProvider';
import { ProviderHub } from '../provider/ProviderHub';
import { AsrService } from '../provider/asr/AsrService';

@Entry
@Component
struct Index {
  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  @State loading: boolean = false;
  @State voiceOn: boolean = false;
  private scroller: Scroller = new Scroller();
  private maxHistory: number = 20;
  private asr: AsrService = new AsrService();

  aboutToAppear(): void {
    ProviderHub.initFromConfig();
    const greeting: ChatMessage = ChatMessage.of(ChatRole.Assistant,
      '你好,我是 OpenHarmonyAgent(当前后端:' + ProviderHub.llmProvider().providerName + ')。\n' +
      '输入任意文字,我会回复你。后续将接入语音、知识库与智能体编排。');
    this.appendMessage(greeting);
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

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (err) {
    }
  }

  private async toggleVoice(): Promise<void> {
    if (this.voiceOn) {
      this.voiceOn = false;
      await this.asr.stop();
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

  private async onSend(): Promise<void> {
    const text: string = this.inputText.trim();
    if (text.length === 0 || this.loading) {
      return;
    }
    this.inputText = '';
    this.appendMessage(ChatMessage.of(ChatRole.User, text));
    this.loading = true;
    try {
      const provider: LLMProvider = ProviderHub.llmProvider();
      const startIndex: number = Math.max(0, this.messages.length - this.maxHistory);
      const history: ChatMessage[] = this.messages.slice(startIndex);
      const reply: string = await provider.chat(history);
      this.appendMessage(ChatMessage.of(ChatRole.Assistant, reply));
    } catch (err) {
      this.appendMessage(ChatMessage.of(ChatRole.Assistant, '抱歉,获取回复失败,请稍后重试。'));
    } finally {
      this.loading = false;
    }
  }

  build() {
    Column() {
      Row() {
        Text('OpenHarmonyAgent')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .backgroundColor('#0A59F7')

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
                .constraintSize({ maxWidth: '76%' })
                .backgroundColor('#FFFFFF')
                .borderRadius(14)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              }
            }
            .width('100%')
            .justifyContent(msg.role === ChatRole.User ? FlexAlign.End : FlexAlign.Start)
          }
        }, (msg: ChatMessage) => msg.id)
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
        Button(this.loading ? '…' : '发送')
          .height(44)
          .enabled(!this.loading)
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
    .backgroundColor('#F1F3F5')
  }
}
