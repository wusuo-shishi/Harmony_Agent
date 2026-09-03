import { LLMProvider } from './llm/LLMProvider';
import { MockLLMProvider } from './llm/MockLLMProvider';
import { PanguLlmProvider } from './llm/PanguLlmProvider';
import { DeepSeekLlmProvider } from './llm/DeepSeekLlmProvider';
import { LlmConfig } from './llm/LlmConfig';
import { CapabilityManager } from '../core/CapabilityManager';

export enum LlmBackend {
  Mock = 'mock',
  DeepSeek = 'deepseek',
  Pangu = 'pangu'
}

export class ProviderHub {
  static backend: LlmBackend = LlmBackend.Mock;
  private static llm: LLMProvider = new MockLLMProvider();

  static initFromConfig(): void {
    if (LlmConfig.ENABLE_DEEPSEEK && LlmConfig.DEEPSEEK_API_KEY.length > 0) {
      ProviderHub.useDeepSeek(LlmConfig.DEEPSEEK_API_KEY, LlmConfig.DEEPSEEK_BASE_URL, LlmConfig.DEEPSEEK_MODEL);
    }
  }

  static llmProvider(): LLMProvider {
    return ProviderHub.llm;
  }

  static useMock(): void {
    ProviderHub.backend = LlmBackend.Mock;
    ProviderHub.llm = new MockLLMProvider();
  }

  static useDeepSeek(apiKey: string, baseUrl: string, model: string): void {
    ProviderHub.backend = LlmBackend.DeepSeek;
    const provider = new DeepSeekLlmProvider();
    provider.configure(apiKey, baseUrl, model);
    ProviderHub.llm = provider;
  }

  static usePangu(apiKey: string, endpoint: string): void {
    ProviderHub.backend = LlmBackend.Pangu;
    const provider = new PanguLlmProvider();
    provider.configure(apiKey, endpoint);
    ProviderHub.llm = provider;
  }

  static dataAugmentationAvailable(): boolean {
    return CapabilityManager.supportsDataAugmentationKit();
  }
}
