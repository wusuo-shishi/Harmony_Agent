import { RetrievalHit } from '../../model/KnowledgeModels';
import { KnowledgeStore } from '../../knowledge/KnowledgeStore';
import { RetrievalProvider } from './RetrievalProvider';
import { Bm25Ranker } from './Bm25Ranker';

export class Bm25Retrieval implements RetrievalProvider {
  readonly providerName: string = '本地 BM25 检索(ArkTS)';

  available(): boolean {
    return true;
  }

  async retrieve(query: string, topK: number): Promise<RetrievalHit[]> {
    const store: KnowledgeStore = KnowledgeStore.shared;
    const chunks = store.listChunks();
    if (chunks.length === 0) {
      return [];
    }
    return Bm25Ranker.rank(query, topK, chunks, (docId: string): string => store.docTitle(docId));
  }
}
