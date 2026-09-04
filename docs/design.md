# OpenHarmonyAgent 设计方案(工作版)

版本:v0.1  日期:2026-09-04  状态:评审中
命题:国际大学生创新大赛产业赛道 · 华为企业命题 —— 基于鸿蒙原生智能的多模态个人助理

## 0. 环境与约束(定案)

| 项 | 结论 |
| --- | --- |
| 开发环境 | DevEco Studio + 模拟器(日常迭代) |
| 验收/演示 | 华为手机 + 华为平板(真机,同一华为账号并组网,可连 DevEco 调试) |
| LLM | 华为云 ModelArts Studio(盘古)API;openJiuwen 为可选编排增强 |
| 上传物 | 单个 PDF/Word ≤20MB 的设计文档(无 PPT/视频);工程代码另存 git 仓库 |
| 周期 | 9 天(2026-09-04 起) |

## 1. 命题要求 → 方案对照表

| 命题要求 | 本方案 |
| --- | --- |
| 1 多模态交互(语音/文本/图像,复合指令) | 统一输入条:CoreSpeech 语音(热词)、文本、拍照/相册;Orchestrator 将复合指令拆解为意图+槽位 |
| 2 端侧 RAG 知识库(离线语义检索问答) | DataAugmentationKit 全链路、按官方设备约束分端落地:PC/2in1 用 knowledgeProcessor 知识加工(官方:加工仅 PC/2in1)→ 产物(倒排库+向量库)随应用预置到手机/平板;手机/平板用智慧化数据检索 retrieval(官方:Phone/Tablet 支持)召回+重排 → 自组装"检索→LLM 生成"RAG 问答,带引用溯源;完整官方 rag API(createRagSession/streamRun,官方:仅 PC/2in1)在 PC/2in1 端到端演示,回应答题要求② |
| 3 跨设备协同(手机/平板/PC 流转) | 应用接续 + 分布式数据对象同步会话;真机手机↔平板实测;PC 留 Provider 空位 |
| 4 ≥3 子智能体协作、自主分解任务 | Orchestrator + 学习助手 / 日程管家 / 文档处理;浅层=规则路由+提示词拆解,预留 LLM tool-calling 升级 |
| 适配手机+平板 | 一多:资源限定符 + 平板双栏布局 |
| 冷启动 ≤3s | 懒加载语音引擎/检索会话;启动链最小化;按需初始化 |
| 语音指令响应 ≤2s / 提升识别精度 | ASR 端侧实时 + 会话/系统热词(≤200)预置领域词表;流式呈现 |
| ArkTS+ArkUI | 全 ArkTS 严格模式 |

## 2. 总体架构

```
知识库构建端(PC/2in1):knowledgeProcessor 知识加工 → 倒排库 + 向量库
        │ 产物 RDB 随应用包预置(安装/首启复制)
交互层(手机/平板·一多)
  输入条[语音|文本|拍照/相册] + 会话/任务卡片流式 UI
        │
Agent 编排层  Orchestrator(意图识别·任务分解·路由·记忆)
   ├─ Agent学习助手    ├─ Agent日程管家    ├─ Agent文档处理
        │ (统一 AgentMessage/AgentResult)
──────────────────────────────────────────
能力层  CapabilityManager(设备能力探针:模拟器/真机)
  LLMProvider        ASRProvider        VisionProvider
  RetrievalProvider  ScheduleProvider   TransferProvider
──────────────────────────────────────────
数据层  知识空间(retrieval 检索引擎 + 预置加工产物) · 会话/记忆 · 配置(敏感词自查)
```

### Provider 双实现策略(真机路径 / 模拟器降级)

| Provider | 真机实现 | 模拟器降级(演示可跑) |
| --- | --- | --- |
| LLMProvider | 华为云盘古 API(或 openJiuwen / DeepSeek) | 同(网络可达) / Mock |
| ASRProvider | CoreSpeech 实时语音+热词 | 文本直入 / 音频文件(若引擎不可用) |
| VisionProvider | Core Vision 图文识别(拍照→OCR) | 选图→读内置文本样例(流程完整) |
| RetrievalProvider | **手机/平板**:DataAugmentationKit `retrieval` 智慧化数据检索(倒排通道为主,向量通道作增强);知识库由 PC/2in1 加工后预置 | ArkTS 自研关键词/标题检索(同接口,已在 D4 落地) |
| KnowledgeBuilder(非运行时) | **PC/2in1**:knowledgeProcessor 知识加工,产物(倒排库+向量库)打包预置 | 自研分块+索引(同产物结构) |
| ScheduleProvider | 日历/提醒(真机) | 内存模拟日程 |
| TransferProvider | 应用接续(真机双端) | UI 演示"已发送到对端"(mock) |

切换依据:`deviceInfo.productModel == 'emulator'` + 能力探针(调用结果异常则自动降级)。

## 3. 关键设计

### 3.1 LLM 通道(华为)
- 首选:华为云 ModelArts Studio(盘古),`LLMProvider` 内封装 HTTP(S)+认证,配置可切换模型/温度。
- 备选/增强:openJiuwen 平台 API(adapter 形式,时间富余再接)。
- 注意:加 `ohos.permission.INTERNET`,HTTPS;仿真机经宿主机网络即可访问云端。
- 若华为云侧仅提供 AK/SK 签名鉴权:用 `@kit.CryptoArchitectureKit`(HMAC-SHA256)实现签名器;若提供 API Key/AppCode 直连更简单 —— D1 实测凭证类型后定。

### 3.2 端侧 RAG(DataAugmentationKit,贴合命题的分端架构)

**官方能力边界(本机 SDK 文档核实):**
- 知识加工 `knowledgeProcessor`:仅 PC/2in1 设备(嵌入模型仅部署于 PC/2in1);
- `retrieval` 智慧化数据检索(召回+重排):支持 Phone / PC/2in1 / Tablet;
- 完整 `rag` 模块(createRagSession + streamRun 流式问答):仅 PC/2in1;
- 端侧问答模型 `localChatModel` / AIP 数据向量化:仅 PC/2in1 / 2in1;
- Kit 整体不支持模拟器;知识加工表不支持端端/端云同步。

命题要求"利用鸿蒙 RAG 模块在本地构建知识库 + 离线语义检索问答,并适配手机+平板",故采用**分端落地的 RAG 架构**(既满足命题、也守住官方支持矩阵):

1. **知识构建(PC/2in1 加工端)**:`knowledgeProcessor` 按 `knowledge_schema.json` 加工课程笔记/文献/会议纪要等 → 产物 = 倒排库(原库内建 inverted 表)+ 向量库(`dbName_vector.db`,含 `chunk_id/chunk_source/chunk_text/repr` 等),仅 PC/2in1 可生成。
2. **知识库随包预置(手机/平板)**:加工完成的 RDB 产物**随应用安装包或首启复制**到手机/平板沙箱 database 目录,应用以普通 RDB 打开只读使用,不在端上重新加工(规避手机不可加工的限制)。
3. **检索(手机/平板)**:`retrieval.getRetriever` 建多路召回(VECTOR_DATABASE + INVERTED_INDEX_DATABASE)→ `retrieveRdb` 召回+重排(RRF / 分数融合,BM25 精确/乱序策略)→ 返回 `RdbRecords`(含 chunk 文本、偏移 → 引用溯源)。手机/平板侧向量召回时 `VectorQuery.value` 需**自行提供**查询向量(端上不做嵌入),故可退化为"纯倒排召回 + RRF"兜底。
4. **生成(手机/平板,自组装 RAG)**:因完整 `rag` 模块仅 PC/2in1,手机/平板在 Provider 内自组装:`query → 问题改写(可选) → retrieval 召回 → 云端 LLM(盘古/DeepSeek)→ 流式回答`;LLM 不落地到端上时属端云协同,符合"LLM 接口可自主选择"。
5. **官方 RAG 能力对齐(PC/2in1,加分项)**:在 PC/2in1 上实现 `rag.ChatLLM` 子类 + `createRagSession` + `streamRun`(THOUGHT/REFERENCE/ANSWER 流),用同一知识库演示**官方 RAG API**,证明命题第②答题要求已使用 `@kit.DataAugmentationKit` RAG API,规避"手机无 RAG API"的口径风险。
6. **合规**:输入输出敏感词自查(Kit 不提供风控);引用溯源随 RdbRecords 携带。

> 现状提醒:D5 需真机确认 —— 预置 RDB 在手机/平板上是否可被 `retrieval` 直接打开检索;若不可行则回退 D4 自研检索+云端 LLM(仅影响"端侧离线",不影响整体流程)。

### 3.3 语音
CoreSpeech 端侧离线 ASR(中文;短语音≤60s),系统/会话热词共≤200 条预置领域词(课程、日程、指令词),提升识别精度;`StartParams` 调自动停止参数保证交互体验。

### 3.4 图像(浅层先行)
拍照/相册 → Core Vision OCR → 文本(可入知识库)→ 后续升级:多模态理解。

### 3.5 智能体编排(浅层先行)
- Orchestrator:规则路由(意图关键字+提示词 LLM 分类)→ 选择子 Agent → 步骤卡片流式展示;
- 子 Agent:
  - 学习助手:知识库 RAG 问答/总结(带引用);
  - 日程管家:从自然语言/复合指令抽取日程→日历提醒(真机 CalendarKit;模拟器内存日程);
  - 文档处理:拍照/文档→OCR→总结要点/入知识库(真机 CoreVision OCR;模拟器内置文本样例降级);
- 升级路径:LLM function-calling 自主规划(接口已按工具调用预留)。

D6 落地说明(2026-09-04):
- 意图路由(IntentRouter):规则优先级 文档(拍照/识图)> 日程(时间+提醒词)> 学习(知识库/检索/引用);无命中→通用对话直接走 LLM
- 新增 `agent/`:Orchestrator + LearningAgent/ScheduleAgent/DocumentAgent + ScheduleTextParser(中文时间抽取:周X/明天/下午N点等)+ 步骤回调(StepListener)
- 新增 `provider/vision|schedule` 双实现:真机 OCR(识别像素图→文本,模拟器返回内置样例文本)、系统日历(CalendarKit addEvent,模拟器内存日程)
- 聊天 UI:三类智能体自动路由 + 蓝色步骤面板流式展示 + 【识图】按钮(拍照/相册→OCR→总结→入知识库)

### 3.6 跨端与一多
- 应用接续:会话上下文序列化迁移(小数据走 want 参数/大数据走分布式文件),UI 状态用 `restoreId`;
- 双设备同账号组网实测;PC 暂以 Provider 占位;
- 一多:phone 单栏、tablet 双栏(左会话右详情/知识空间),资源走限定符。

## 4. 目录规划(演进目标)

```
entry/src/main/ets/
  pages/            # 手机/平板入口页
  common/           # UI组件(输入条/气泡/任务卡片/引用卡片)
  core/             # CapabilityManager、类型定义、事件
  agent/            # Orchestrator + 3 子Agent + 记忆
  provider/         # LLM/ASR/Vision/Retrieval/Schedule/Transfer + 双实现
  knowledge/        # 知识空间文件管理、敏感词
  utils/
```

## 5. 性能预算与优化

| 指标 | 预算 | 手段 |
| --- | --- | --- |
| 冷启动 ≤3s | 启动到可交互 | 最小启动链;语音/检索会话懒加载;预热 UI 骨架 |
| 语音→响应 ≤2s | ASR<0.5s+意图/检索<0.6s+首字流式 | 端侧 ASR、热词、检索超时兜底、LLM 流式输出 |
| 真机实测口径 | 文档注明设备/系统/网络 | 每轮测量打点(hilog/性能探针) |

## 6. 9 天里程碑(2026-09-04 起)

- D1 工程分层+Provider 骨架+真机签名环境;用户并行:华为云账号/ModelStudio 凭证
- D2 LLM 文本问答跑通(盘古;凭证未到先 mock 流式)
- D3 语音输入(真机 CoreSpeech+热词;模拟器文本降级)
- D4 知识库浅层:文件导入+RetrievalProvider 双实现+引用溯源
- D5 真机 DataAugmentationKit 分端 RAG:PC/2in1 knowledgeProcessor 加工 → 产物预置手机/平板 → retrieval 检索 + 自组装 RAG;PC/2in1 演示官方 rag API(streamRun)
- D6 Agent 编排:Orchestrator+3 子 Agent+复合指令(拍照→OCR→总结)端到端
- D7 跨端接续(手机↔平板)+一多布局
- D8 指标真机实测优化 + 设计文档撰写
- D9 双真机全流程走查→导出 PDF/Word ≤20MB 上传 + 代码入库

## 7. 交付物

1. 工程代码(ArkTS,提交 git 仓库);
2. 设计文档(PDF/Word ≤20MB):方案/架构图/实现说明/命题逐条对照/真机性能数据/创新点/截图。

## 8. 风险与对策

| 风险 | 对策 |
| --- | --- |
| 华为云盘古凭证类型不明(AK/SK vs Key) | D1 实测;AK/SK 则用 CryptoArchitectureKit 实现签名器 |
| 知识加工/官方 rag 仅 PC/2in1 可用 | 分端架构定案:PC/2in1 加工与演示官方 RAG,手机/平板走 retrieval + 自组装;产物随包预置 |
| 手机/平板打开预置 RDB 可能不被 retrieval 接受或触发重加工 | D5 首项真机验证;失败则回退 D4 自研检索 + 云端 LLM(仅损失端侧离线语义) |
| 手机/平板向量召回需自备 query 向量 | 以倒排召回为主、向量为辅;query 向量由云端 embedding 生成下发,或直接降级倒排+RRF |
| DataAugmentationKit 真机可用性/权限 | 以 retrieval 检索路径为主,知识加工失败有自研检索兜底 |
| 9 天窗口 | 浅层先行;模拟器降级保证全流程可演示;代码仓库随时可回退 |
| 双机接续环境(同账号/组网) | 提前两天联调;失败则 UI+分布式数据对象最小演示 |
| 文档 ≤20MB | 截图压缩;图表矢量/位图混用 |

## 9. 待办/待确认

- [ ] 华为云账号注册 + ModelStudio 开通,确认凭证类型与免费额度(当前:LLM 用 Mock 兜底,可快速切 DeepSeek/盘古)
- [x] 双真机同一华为账号且已组网、可连 DevEco(用户已确认)
- [ ] **准备一台 PC/2in1**:承担知识加工(knowledgeProcessor)与官方 rag API 演示(能力矩阵见 §3.2)
- [ ] 命题上传具体入口/是否要求代码仓库地址(以大赛平台为准)
- [x] 工程兼容版本调整为 6.0.2(22),可在现有 API22 模拟器运行(target 仍 6.1.0(23))

## 10. 团队分工(已确认:1 编码核心 + 5 支撑)

| 角色 | 人 | 任务 |
| --- | --- | --- |
| 编码核心(用户+AI) | 1 | D1–D9 全部代码/构建/集成/真机调试 |
| 真机验收官 | 2 | 按《验收用例清单》装包实测,录屏/截图反馈(D3/D5/D7 真机值班,手机/平板各一) |
| 知识库素材 | 1 | 3 类样例文档(md/txt)+演示语料(复合指令/日程文本)+ 拍照文档纸稿 |
| 资源/规则官 | 1 | 大赛资源包/LLM 凭证/上传与仓库规则/签名信息/组网确认 |
| 文档/文案 | 1 | 将 design.md+实测数据排版为 ≤20MB Word/PDF;命题逐条对照;截图标注 |

约束:支撑人员不直接改代码;如有人执意参与,只能在主线稳定后认领"纯逻辑、无 UI/Kit"模块并走分支合入。

## 11. 进度(Checkpoint 2026-09-04)

- [x] D1:工程分层 + Provider 抽象 + CapabilityManager + Mock/Pangu 占位;模拟器运行环境打通(API22)
- [x] D2:聊天 UI(Index)接入 ProviderHub,Mock LLM 端到端可对话(模拟器已部署可测)
- [x] D3:语音输入代码完成(CoreSpeech+麦克风+VAD,入口为聊天页【语音】按钮);**待真机联调**(手册见 docs/D3语音真机联调手册.md)
- [x] 快照:git 仓库已初始化并首次提交(94caacc),进度可随时回退/同步
- [ ] D4:知识库浅层(文件导入 + RetrievalProvider 双实现 + 引用溯源)
  - [x] D4.1 知识数据模型(KnowledgeDoc/Chunk/RetrievalHit)+ 文本分块 + 敏感词自查
  - [x] D4.2 KnowledgeStore:rawfile 示例导入、文档选择器导入、文件持久化(首次启动自动载入 3 篇示例)
  - [x] D4.3 RetrievalProvider 接口 + 本地关键词检索(LocalKeywordRetrieval,含引用偏移/命中片段)+ DAG 占位(DagRetrievalProvider,待 D5 真机)
  - [x] D4.4 知识库页(KnowledgePage):文档列表/删除、恢复示例、导入文档、检索即引用卡片(模拟器已可演示)
  - [ ] D4.5 真机验证(导入真实文档/检索正确性/引用溯源核对;验收官按 docs/真机验收用例清单.md 第3节执行)
- [ ] D5:真机 DataAugmentationKit 分端 RAG:PC/2in1 加工 → 产物预置 → retrieval 检索 + 自组装 RAG
- [ ] D6:Agent 编排(Orchestrator + 学习/日程/文档 子 Agent + 复合指令)
  - [x] D6.1 agent 层:Orchestrator/IntentRouter + 学习/日程/文档 三子 Agent + 步骤流式回调
  - [x] D6.2 VisionProvider(CoreVision OCR 真机 / 内置样例文本模拟器降级)与 ScheduleProvider(CalendarKit 真机 / 内存模拟器)
  - [x] D6.3 日程解析器 ScheduleTextParser(中文相对时间抽取)+ LLM JSON 兜底
  - [x] D6.4 聊天 UI:意图自动路由 + 步骤卡片面板 + 【识图】按钮(拍照/相册→OCR→总结→入知识库)
  - [x] D6.5 模拟器端到端回归通过(学习助手引用溯源 / 日程安排 / 识图总结 / 通用对话)
  - [ ] D6.6 真机验证:日历写入 CalendarKit、CoreVision OCR、复合指令「拍一下…总结」完整链路
- [ ] D7:跨端接续 + 一多布局
  - [x] D7.1 一多布局:KnowledgePage 逻辑抽取为复用组件 KnowledgeView;Index 大屏(≥840vp)自动双栏(左会话+右知识库),窄屏维持单栏独立页(mediaquery 驱动)
  - [ ] D7.2 双栏宽屏真机/折叠屏截图走查(代码已就绪,待平板/折叠环境)
  - [ ] D7.3 跨端应用接续(手机↔平板)仍待开发
- [ ] D8:指标优化 + 文档撰写
- [ ] D9:双真机走查 + 上传物导出

### 模拟器可测占比(口径:命题核心能力)
约 40–45% 可在模拟器完成;DataAugmentationKit、语音、OCR、跨端(约 55–60%)必须真机。

### LLM 接入现状与后备
- 当前:Mock(全流程可跑);
- 后备1:DeepSeek(OpenAI 兼容 Provider,model 名以平台为准);
- 主目标:华为盘古/大赛资源包(adapter 已预留 PanguLlmProvider)。
