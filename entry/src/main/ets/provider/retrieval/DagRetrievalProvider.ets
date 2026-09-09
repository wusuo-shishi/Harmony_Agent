import { RetrievalHit } from '../../model/KnowledgeModels';
import { CapabilityManager } from '../../core/CapabilityManager';
import { RetrievalProvider } from './RetrievalProvider';

export class DagRetrievalProvider implements RetrievalProvider {
  readonly providerName: string = 'DataAugmentationKit(AIP 智慧检索)';

  available(): boolean {
    return CapabilityManager.supportsDataAugmentationKit();
  }

  async retrieve(query: string, topK: number): Promise<RetrievalHit[]> {
    void query;
    void topK;
    throw new Error('DataAugmentationKit 检索需真机能力(D5 接入),当前请使用本地 BM25 检索。');
  }
}
