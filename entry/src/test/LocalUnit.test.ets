import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { KnowledgeChunk } from '../main/ets/model/KnowledgeModels';
import { TextChunker } from '../main/ets/knowledge/TextChunker';
import { SensitiveWordFilter, SensitiveHit } from '../main/ets/knowledge/SensitiveWordFilter';
import { Bm25Ranker } from '../main/ets/provider/retrieval/Bm25Ranker';
import { RetrievalHit } from '../main/ets/model/KnowledgeModels';

export default function localUnitTest() {
  describe('TextChunker', () => {
    beforeEach(() => {
    });

    it('normalize_convertsCrlfToLf', 0, () => {
      const raw: string = '第一行\r\n第二行\r第三行';
      expect(TextChunker.normalize(raw)).assertEqual('第一行\n第二行\n第三行');
    });

    it('normalize_keepsPlainTextUnchanged', 0, () => {
      const raw: string = 'a\nb';
      expect(TextChunker.normalize(raw)).assertEqual(raw);
    });

    it('emptyContent_yieldsNoChunks', 0, () => {
      const chunks: KnowledgeChunk[] = TextChunker.buildChunks('d1', '');
      expect(chunks.length).assertEqual(0);
    });

    it('blankOnlyContent_yieldsNoChunks', 0, () => {
      const chunks: KnowledgeChunk[] = TextChunker.buildChunks('d1', '  \n \n\t\n');
      expect(chunks.length).assertEqual(0);
    });

    it('paragraphs_splitIntoChunks_withOffsets', 0, () => {
      const chunks: KnowledgeChunk[] = TextChunker.buildChunks('d1', '第一段\n\n第二段内容');
      expect(chunks.length).assertEqual(2);
      expect(chunks[0].docId).assertEqual('d1');
      expect(chunks[0].chunkIndex).assertEqual(0);
      expect(chunks[0].charStart).assertEqual(0);
      expect(chunks[0].text).assertEqual('第一段');
      expect(chunks[1].chunkIndex).assertEqual(1);
      // "第一段\n\n" 共 5 个字符(3 个中文 + 2 个换行),第二段从索引 5 开始
      expect(chunks[1].charStart).assertEqual(5);
      expect(chunks[1].text).assertEqual('第二段内容');
    });

    it('longAdjacentLines_areSplitByMaxChars', 0, () => {
      const lineA: string = 'x'.repeat(400);
      const lineB: string = 'y'.repeat(400);
      const chunks: KnowledgeChunk[] = TextChunker.buildChunks('d1', `${lineA}\n${lineB}`);
      expect(chunks.length).assertEqual(2);
      expect(chunks[0].text.length).assertEqual(400);
      expect(chunks[1].text.length).assertEqual(400);
      expect(chunks[1].charStart).assertEqual(401);
    });

    it('shortLines_mergeIntoSingleChunk', 0, () => {
      const content: string = '第一行\n第二行\n第三行';
      const chunks: KnowledgeChunk[] = TextChunker.buildChunks('d1', content);
      expect(chunks.length).assertEqual(1);
      expect(chunks[0].text).assertEqual(content);
      expect(chunks[0].charStart).assertEqual(0);
    });

    it('carriesDocIdAcrossChunks', 0, () => {
      const chunks: KnowledgeChunk[] = TextChunker.buildChunks('doc-abc', '甲\n\n乙\n\n丙');
      expect(chunks.length).assertEqual(3);
      expect(chunks[2].docId).assertEqual('doc-abc');
    });
  });

  describe('SensitiveWordFilter', () => {
    beforeEach(() => {
      SensitiveWordFilter.resetDefault();
    });

    it('defaultWordCount_isStable', 0, () => {
      expect(SensitiveWordFilter.wordCount()).assertEqual(14);
    });

    it('cleanText_hasNoHit', 0, () => {
      expect(SensitiveWordFilter.hasSensitive('明天天气怎么样')).assertFalse();
      expect(SensitiveWordFilter.firstHit('天气预报')).assertUndefined();
    });

    it('detectsDefaultWord_atCorrectIndex', 0, () => {
      const hit: SensitiveHit | undefined = SensitiveWordFilter.firstHit('帮我刷单赚钱');
      expect(hit !== undefined).assertTrue();
      if (hit !== undefined) {
        expect(hit.word).assertEqual('刷单');
        expect(hit.index).assertEqual(2);
      }
    });

    it('multiWordHit_picksEarliestPosition', 0, () => {
      const hit: SensitiveHit | undefined = SensitiveWordFilter.firstHit('赌博诈骗');
      expect(hit !== undefined).assertTrue();
      if (hit !== undefined) {
        expect(hit.word).assertEqual('赌博');
        expect(hit.index).assertEqual(0);
      }
    });

    it('multiWordHit_priorityByPositionNotOrder', 0, () => {
      // "刷单"出现位置晚于"诈骗",应返回位置更靠前的"诈骗"
      const hit: SensitiveHit | undefined = SensitiveWordFilter.firstHit('有人诈骗还要刷单吗');
      expect(hit !== undefined).assertTrue();
      if (hit !== undefined) {
        expect(hit.word).assertEqual('诈骗');
        expect(hit.index).assertEqual(2);
      }
    });

    it('addWord_extendAndReset_works', 0, () => {
      const before: number = SensitiveWordFilter.wordCount();
      SensitiveWordFilter.addWord('自定义敏感词');
      expect(SensitiveWordFilter.wordCount()).assertEqual(before + 1);
      expect(SensitiveWordFilter.hasSensitive('这是一条自定义敏感词内容')).assertTrue();
      SensitiveWordFilter.resetDefault();
      expect(SensitiveWordFilter.wordCount()).assertEqual(14);
      expect(SensitiveWordFilter.hasSensitive('这是一条自定义敏感词内容')).assertFalse();
    });

    it('addWord_ignoresBlank', 0, () => {
      const before: number = SensitiveWordFilter.wordCount();
      SensitiveWordFilter.addWord('   ');
      SensitiveWordFilter.addWord('');
      expect(SensitiveWordFilter.wordCount()).assertEqual(before);
    });
  });

  describe('Bm25Ranker', () => {
    const titleOf = (map: Map<string, string>, id: string): string => {
      return map.get(id) ?? '';
    };

    it('queryHits_relevantDoc_ranksFirst', 0, () => {
      const docA: string = '检索增强生成与引用溯源:RAG 回答必须标注使用了哪些资料,并在文末附上引用来源。';
      const docB: string = '日程管家可以把自然语言里的时间抽出来,写入系统日历并设置提前提醒。';
      const chunks: KnowledgeChunk[] = [];
      const docAChunks: KnowledgeChunk[] = TextChunker.buildChunks('docA', docA);
      const docBChunks: KnowledgeChunk[] = TextChunker.buildChunks('docB', docB);
      for (let i = 0; i < docAChunks.length; i++) {
        chunks.push(docAChunks[i]);
      }
      for (let i = 0; i < docBChunks.length; i++) {
        chunks.push(docBChunks[i]);
      }
      const titles: Map<string, string> = new Map<string, string>();
      titles.set('docA', '文档A-引用溯源');
      titles.set('docB', '文档B-日程');
      const hits: RetrievalHit[] = Bm25Ranker.rank('什么是引用溯源', 3, chunks,
        (docId: string): string => titleOf(titles, docId));
      expect(hits.length > 0).assertTrue();
      expect(hits[0].docTitle).assertEqual('文档A-引用溯源');
    });

    it('termFrequency_ranksDenseDocFirst', 0, () => {
      const base: string = '栈是一种先进后出的数据结构,支持压栈与弹栈操作。';
      const docA: string = '今天课程提到一种叫栈的数据结构,仅此一句。';
      const docB: string = `${base}${base}${base}${base}${base}`;
      const chunks: KnowledgeChunk[] = [];
      const docAChunks: KnowledgeChunk[] = TextChunker.buildChunks('docA', docA);
      const docBChunks: KnowledgeChunk[] = TextChunker.buildChunks('docB', docB);
      for (let i = 0; i < docAChunks.length; i++) {
        chunks.push(docAChunks[i]);
      }
      for (let i = 0; i < docBChunks.length; i++) {
        chunks.push(docBChunks[i]);
      }
      const titles: Map<string, string> = new Map<string, string>();
      titles.set('docA', '文档A');
      titles.set('docB', '文档B');
      const hits: RetrievalHit[] = Bm25Ranker.rank('栈', 5, chunks,
        (docId: string): string => titleOf(titles, docId));
      expect(hits.length).assertEqual(2);
      expect(hits[0].docTitle).assertEqual('文档B');
    });

    it('topK_limitsResults', 0, () => {
      const text: string = '学习助手会检索知识库并回答。';
      const chunks: KnowledgeChunk[] = [];
      for (let i = 0; i < 3; i++) {
        const docChunks: KnowledgeChunk[] = TextChunker.buildChunks(`doc${i}`, text);
        for (let j = 0; j < docChunks.length; j++) {
          chunks.push(docChunks[j]);
        }
      }
      const titles: Map<string, string> = new Map<string, string>();
      titles.set('doc0', '文档0');
      titles.set('doc1', '文档1');
      titles.set('doc2', '文档2');
      const hits: RetrievalHit[] = Bm25Ranker.rank('知识库', 2, chunks,
        (docId: string): string => titleOf(titles, docId));
      expect(hits.length).assertEqual(2);
      expect(hits[0].score >= hits[1].score).assertTrue();
    });

    it('emptyChunks_returnsEmpty', 0, () => {
      const titles: Map<string, string> = new Map<string, string>();
      const hits: RetrievalHit[] = Bm25Ranker.rank('检索', 3, [],
        (docId: string): string => titleOf(titles, docId));
      expect(hits.length).assertEqual(0);
    });

    it('snippet_anchorsInsideMatchedChunk_withDocOffset', 0, () => {
      const content: string = '第一段内容。\n\n第二段讲到了量子计算的优势与原理。';
      const chunks: KnowledgeChunk[] = TextChunker.buildChunks('docQ', content);
      expect(chunks.length).assertEqual(2);
      const titles: Map<string, string> = new Map<string, string>();
      titles.set('docQ', '文档Q');
      const hits: RetrievalHit[] = Bm25Ranker.rank('量子计算', 3, chunks,
        (docId: string): string => titleOf(titles, docId));
      expect(hits.length).assertEqual(1);
      expect(hits[0].chunkIndex).assertEqual(1);
      expect(hits[0].charStart >= chunks[1].charStart).assertTrue();
      expect(hits[0].snippet.indexOf('量子') >= 0).assertTrue();
    });

    it('numericTimestampTitle_notBoostedOverPlainTitle', 0, () => {
      // 回归:纯数字时间戳标题("识别文档_20260910")不得因标题含数字子串拿到加分,
      // 与同名内容文档并列时应保持插入顺序,而非被"标题含1"顶到前面
      const shared: string = '课程编号 1 表示入门内容。';
      const chunks: KnowledgeChunk[] = [];
      const plainChunks: KnowledgeChunk[] = TextChunker.buildChunks('docB', shared);
      const numChunks: KnowledgeChunk[] = TextChunker.buildChunks('docA', shared);
      for (let i = 0; i < plainChunks.length; i++) {
        chunks.push(plainChunks[i]);
      }
      for (let i = 0; i < numChunks.length; i++) {
        chunks.push(numChunks[i]);
      }
      const titles: Map<string, string> = new Map<string, string>();
      titles.set('docA', '识别文档_20260910');
      titles.set('docB', '普通文档');
      const hits: RetrievalHit[] = Bm25Ranker.rank('1', 3, chunks,
        (docId: string): string => titleOf(titles, docId));
      expect(hits.length).assertEqual(2);
      expect(hits[0].docTitle).assertEqual('普通文档');
    });
  });
}
