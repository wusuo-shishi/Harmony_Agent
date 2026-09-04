import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { KnowledgeChunk } from '../main/ets/model/KnowledgeModels';
import { TextChunker } from '../main/ets/knowledge/TextChunker';
import { SensitiveWordFilter, SensitiveHit } from '../main/ets/knowledge/SensitiveWordFilter';

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
}
