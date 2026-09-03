import { audio } from '@kit.AudioKit';
import { speechRecognizer } from '@kit.CoreSpeechKit';

export type PartialHandler = (text: string) => void;
export type FinalHandler = (text: string) => void;
export type ErrorHandler = (message: string) => void;

export class AsrService {
  private engine: speechRecognizer.SpeechRecognitionEngine | undefined = undefined;
  private capturer: audio.AudioCapturer | undefined = undefined;
  private sessionId: string = '';
  private running: boolean = false;
  private onPartial: PartialHandler | undefined = undefined;
  private onFinal: FinalHandler | undefined = undefined;
  private onError: ErrorHandler | undefined = undefined;

  async start(onPartial: PartialHandler, onFinal: FinalHandler, onError: ErrorHandler): Promise<void> {
    if (this.running) {
      return;
    }
    this.running = true;
    this.onPartial = onPartial;
    this.onFinal = onFinal;
    this.onError = onError;
    this.sessionId = `asr_${Date.now()}`;
    try {
      if (this.engine === undefined) {
        await this.createEngine();
      }
      if (this.engine === undefined) {
        throw new Error('create engine failed');
      }
      this.attachListener();
      this.beginListening();
      await this.startCapturer();
    } catch (err) {
      this.running = false;
      const handler: ErrorHandler | undefined = this.onError;
      handler?.('语音引擎启动失败:' + JSON.stringify(err));
    }
  }

  async stop(): Promise<void> {
    if (!this.running) {
      return;
    }
    this.running = false;
    try {
      if (this.capturer !== undefined) {
        this.capturer.off('readData');
      }
    } catch (err) {
    }
    try {
      await this.capturer?.stop();
    } catch (err) {
    }
    try {
      this.capturer?.release();
    } catch (err) {
    }
    this.capturer = undefined;
    try {
      this.engine?.finish(this.sessionId);
    } catch (err) {
    }
    try {
      this.engine?.shutdown();
    } catch (err) {
    }
    this.engine = undefined;
    this.onPartial = undefined;
    this.onFinal = undefined;
    this.onError = undefined;
  }

  private async createEngine(): Promise<void> {
    const extra: Record<string, Object> = { 'locate': 'CN', 'recognizerMode': 'short' };
    const params: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 1,
      extraParams: extra
    };
    try {
      const engine = await speechRecognizer.createEngine(params);
      this.engine = engine;
    } catch (err) {
      throw new Error(`createEngine 失败:${JSON.stringify(err)}`);
    }
  }

  private attachListener(): void {
    const listener: speechRecognizer.RecognitionListener = {
      onStart: (sessionId: string, eventMessage: string): void => {
      },
      onEvent: (sessionId: string, eventCode: number, eventMessage: string): void => {
      },
      onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult): void => {
        const text: string = result.result;
        const partialHandler: PartialHandler | undefined = this.onPartial;
        const finalHandler: FinalHandler | undefined = this.onFinal;
        if (result.isFinal) {
          finalHandler?.(text);
        } else if (this.running) {
          partialHandler?.(text);
        }
      },
      onComplete: (sessionId: string, eventMessage: string): void => {
        this.running = false;
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string): void => {
        const handler: ErrorHandler | undefined = this.onError;
        handler?.(`语音识别错误:${errorCode} ${errorMessage}`);
        this.running = false;
      }
    };
    this.engine?.setListener(listener);
  }

  private beginListening(): void {
    const audioParam: speechRecognizer.AudioInfo = {
      audioType: 'pcm',
      sampleRate: 16000,
      soundChannel: 1,
      sampleBit: 16
    };
    const extra: Record<string, Object> = {
      'recognitionMode': 0,
      'vadBegin': 1500,
      'vadEnd': 2000,
      'maxAudioDuration': 60000
    };
    const startParams: speechRecognizer.StartParams = {
      sessionId: this.sessionId,
      audioInfo: audioParam,
      extraParams: extra
    };
    try {
      this.engine?.startListening(startParams);
    } catch (err) {
      throw new Error(`startListening 失败:${JSON.stringify(err)}`);
    }
  }

  private async startCapturer(): Promise<void> {
    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    };
    const capturerInfo: audio.AudioCapturerInfo = {
      source: audio.SourceType.SOURCE_TYPE_MIC,
      capturerFlags: 0
    };
    const options: audio.AudioCapturerOptions = {
      streamInfo: streamInfo,
      capturerInfo: capturerInfo
    };
    const capturer = await audio.createAudioCapturer(options);
    this.capturer = capturer;
    try {
      capturer.on('readData', (buffer: ArrayBuffer) => {
        this.feedAudio(buffer);
      });
    } catch (err) {
      throw new Error(`readData 注册失败:${JSON.stringify(err)}`);
    }
    try {
      await capturer.start();
    } catch (err) {
      throw new Error(`录音启动失败:${JSON.stringify(err)}`);
    }
  }

  private feedAudio(buffer: ArrayBuffer): void {
    const bytes: Uint8Array = new Uint8Array(buffer);
    const chunkSize: number = 1280;
    let offset: number = 0;
    while (offset + chunkSize <= bytes.length) {
      const chunk: Uint8Array = new Uint8Array(bytes.buffer, bytes.byteOffset + offset, chunkSize);
      try {
        this.engine?.writeAudio(this.sessionId, chunk);
      } catch (err) {
      }
      offset += chunkSize;
    }
  }
}
