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
| 2 端侧 RAG 知识库(离线语义检索问答) | DataAugmentationKit:知识加工 + 智慧化数据检索(AIP)+ 自组装"分解→改写→召回→LLM 生成"RAG 管线;手机/平板不提供 rag API,故自组装(设计亮点);结果带引用溯源 |
| 3 跨设备协同(手机/平板/PC 流转) | 应用接续 + 分布式数据对象同步会话;真机手机↔平板实测;PC 留 Provider 空位 |
| 4 ≥3 子智能体协作、自主分解任务 | Orchestrator + 学习助手 / 日程管家 / 文档处理;浅层=规则路由+提示词拆解,预留 LLM tool-calling 升级 |
| 适配手机+平板 | 一多:资源限定符 + 平板双栏布局 |
| 冷启动 ≤3s | 懒加载语音引擎/检索会话;启动链最小化;按需初始化 |
| 语音指令响应 ≤2s / 提升识别精度 | ASR 端侧实时 + 会话/系统热词(≤200)预置领域词表;流式呈现 |
| ArkTS+ArkUI | 全 ArkTS 严格模式 |

## 2. 总体架构

```
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
数据层  知识空间(导入/加工产物) · 会话/记忆 · 配置(敏感词自查)
```

### Provider 双实现策略(真机路径 / 模拟器降级)

| Provider | 真机实现 | 模拟器降级(演示可跑) |
| --- | --- | --- |
| LLMProvider | 华为云盘古 API(或 openJiuwen) | 同(网络可达) / Mock |
| ASRProvider | CoreSpeech 实时语音+热词 | 文本直入 / 音频文件(若引擎不可用) |
| VisionProvider | Core Vision 图文识别(拍照→OCR) | 选图→读内置文本样例(流程完整) |
| RetrievalProvider | DataAugmentationKit 知识加工+AIP 检索 | ArkTS 自研关键词/标题检索(同接口) |
| ScheduleProvider | 日历/提醒(真机) | 内存模拟日程 |
| TransferProvider | 应用接续(真机双端) | UI 演示"已发送到对端"(mock) |

切换依据:`deviceInfo.productModel == 'emulator'` + 能力探针(调用结果异常则自动降级)。

## 3. 关键设计

### 3.1 LLM 通道(华为)
- 首选:华为云 ModelArts Studio(盘古),`LLMProvider` 内封装 HTTP(S)+认证,配置可切换模型/温度。
- 备选/增强:openJiuwen 平台 API(adapter 形式,时间富余再接)。
- 注意:加 `ohos.permission.INTERNET`,HTTPS;仿真机经宿主机网络即可访问云端。
- 若华为云侧仅提供 AK/SK 签名鉴权:用 `@kit.CryptoArchitectureKit`(HMAC-SHA256)实现签名器;若提供 API Key/AppCode 直连更简单 —— D1 实测凭证类型后定。

### 3.2 端侧 RAG(DataAugmentationKit)
- 入库:知识加工(`knowledgeProcessor`)按 schema 生成向量库/倒排表;
- 检索:智慧化数据检索(AIP,Phone/Tablet 支持)召回+重排;
- 生成:LLM(盘古);RAG 流程"问题分解→查询改写→知识检索→生成"由编排层实现(自组装);
- 溯源:检索记录带回原文位置,UI 以引用卡片呈现;
- 合规:RAG 无敏感词风控,App 侧自做输入输出敏感词检查;
- 现状提醒:RAG `rag`/端侧模型仅 PC/2in1 且 Kit 不支持模拟器 → 手机/平板走 AIP 检索路径,PC 侧留 rag API 可扩展位。

### 3.3 语音
CoreSpeech 端侧离线 ASR(中文;短语音≤60s),系统/会话热词共≤200 条预置领域词(课程、日程、指令词),提升识别精度;`StartParams` 调自动停止参数保证交互体验。

### 3.4 图像(浅层先行)
拍照/相册 → Core Vision OCR → 文本(可入知识库)→ 后续升级:多模态理解。

### 3.5 智能体编排(浅层先行)
- Orchestrator:规则路由(意图关键字+提示词 LLM 分类)→ 选择子 Agent → 步骤卡片流式展示;
- 子 Agent:
  - 学习助手:知识库 RAG 问答/总结(带引用);
  - 日程管家:从自然语言/复合指令抽取日程→日历提醒;
  - 文档处理:拍照/文档→OCR→总结要点/入知识库;
- 升级路径:LLM function-calling 自主规划(接口已按工具调用预留)。

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
- D5 真机 DataAugmentationKit:知识加工+AIP 检索+自组装 RAG 问答
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
| DataAugmentationKit 真机可用性/权限 | 以 AIP 检索路径为主,知识加工失败有自研检索兜底 |
| 9 天窗口 | 浅层先行;模拟器降级保证全流程可演示;代码仓库随时可回退 |
| 双机接续环境(同账号/组网) | 提前两天联调;失败则 UI+分布式数据对象最小演示 |
| 文档 ≤20MB | 截图压缩;图表矢量/位图混用 |

## 9. 待办/待确认

- [ ] 华为云账号注册 + ModelStudio 开通,确认凭证类型与免费额度(当前:LLM 用 Mock 兜底,可快速切 DeepSeek/盘古)
- [x] 双真机同一华为账号且已组网、可连 DevEco(用户已确认)
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
- [ ] D3:语音输入(CoreSpeech,真机)
- [ ] D4:知识库浅层(文件导入 + RetrievalProvider 双实现 + 引用溯源)
- [ ] D5:真机 DataAugmentationKit(AIP 检索自组装 RAG)
- [ ] D6:Agent 编排(Orchestrator + 学习/日程/文档 子 Agent + 复合指令)
- [ ] D7:跨端接续 + 一多布局
- [ ] D8:指标优化 + 文档撰写
- [ ] D9:双真机走查 + 上传物导出

### 模拟器可测占比(口径:命题核心能力)
约 40–45% 可在模拟器完成;DataAugmentationKit、语音、OCR、跨端(约 55–60%)必须真机。

### LLM 接入现状与后备
- 当前:Mock(全流程可跑);
- 后备1:DeepSeek(OpenAI 兼容 Provider,model 名以平台为准);
- 主目标:华为盘古/大赛资源包(adapter 已预留 PanguLlmProvider)。
