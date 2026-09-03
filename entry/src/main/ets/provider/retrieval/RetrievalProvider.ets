import { RetrievalHit } from '../../model/KnowledgeModels';

export interface RetrievalProvider {
  readonly providerName: string;
  available(): boolean;
  retrieve(query: string, topK: number): Promise<RetrievalHit[]>;
}
