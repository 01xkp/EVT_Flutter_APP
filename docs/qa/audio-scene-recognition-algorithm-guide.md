# 开源声音场景识别、声音事件检测与异常声音识别算法库说明

> 本文只整理声音场景识别相关的开源模型、训练与评测工具、核心算法和许可证核查要点。它讨论“所处环境是什么、听到了什么、声音在何时发生”，不讨论将人声转换成文字、分辨人员身份或生成文本结论。项目状态和许可证以 2026-09-15 查阅到的项目主页、发布页和模型页为准；实际使用前仍须以准备采用的代码版本、权重文件和训练数据的原始条款复核。

## 先看结论

声音场景识别不是文字识别。它判断一段声音所处的环境、同时存在的声音类型，以及某个声音出现的时间。办公室、街道和车内属于场景；警报、敲门和车辆鸣笛属于事件；同一段音频可以同时有一个主场景和多个事件。

一套完整方案通常由三层组成：

~~~text
连续声音
  -> 固定长度窗口与声学特征
  -> 场景分类、声音标签或事件检测模型
  -> 连续分数平滑、类别阈值和状态机
  -> 主场景、并发事件、事件起止时间、未知或混合状态
~~~

选择模型时，先确定目标问题，再看模型大小、标签覆盖度、可复现实验和许可，不能只看 GitHub 热度：

| 目标 | 优先选择 | 原因 |
| --- | --- | --- |
| 直接训练办公室、街道、地铁等环境类别 | DCASE Task 1 定义与 CP-Mobile 基线、EfficientAT 微调 | 以 ASC 的类别和跨条件测试为中心，而非把事件标签硬套为场景 |
| 快速获得通用声音标签 | YAMNet、PANNs | AudioSet 预训练成熟，已有大量可复现实例 |
| 资源受限的多标签分类 | EfficientAT、YAMNet | 计算量较低，适合持续窗口推理 |
| 更高上限的封闭标签分类 | AST、HTS-AT | Transformer 表征能力强，适合有标注数据后的微调 |
| 用声音做开放词汇候选召回 | LAION-CLAP | 音频和文本位于同一向量空间，可做零样本排序 |
| 以预训练向量训练自有分类器 | BEATs、PANNs、YAMNet | 可以抽取 embedding，再用较小分类头适配本地标签 |
| 明确回答“哪个声音从何时到何时发生” | DESED/DCASE 基线、HTS-AT 的帧级训练、PANNs DecisionLevel 系列 | 需要帧级或时间分辨率输出，整段分类不够 |
| 发现与正常声音不同的片段 | DCASE 异常声音检测方法、embedding 距离或重建误差 | 先发现异常，再另行识别原因 |
| 评估事件检测分数 | sed_scores_eval | 能计算阈值无关的 SED 指标和 PSDS |

最容易犯的四个错误：

1. 把 AudioSet 的“车辆”“音乐”“人声”等事件标签直接当成“街道”“餐厅”“车内”等场景结论。
2. 用一个全局 0.5 阈值判断所有类别，忽略每个类别的分数分布和误报代价。
3. 先用语音活动检测删除非语音，再识别场景，导致警报、流水、敲门、机械声和音乐全部丢失。
4. 把单声道分类模型宣传为能判断声源方向。方向估计需要多通道空间信息和专门的 SELD 方法。

## 1. 场景、标签、事件和异常的边界

### 1.1 五类任务

| 任务 | 英文缩写 | 输入与输出 | 适合回答的问题 | 不能保证什么 |
| --- | --- | --- | --- | --- |
| 声学场景分类 | ASC | 一段窗口 -> 一个主场景 | “这里更像办公室、街道还是车内？” | 不给单个事件的精确起止时间 |
| 音频标签 | Audio Tagging | 一段窗口 -> 多个声音标签及分数 | “这一段同时有哪些声音？” | 标签存在不等于知道它何时发生 |
| 声音事件检测 | SED | 连续帧 -> 类别、开始、结束 | “警报从第几秒开始，到第几秒结束？” | 不能自动推断更高层的环境语义 |
| 声源定位与检测 | SELD | 连续多通道帧 -> 事件、时间、方向 | “哪个事件在什么方向出现？” | 单声道输入没有方向信息 |
| 异常声音检测 | ASD | 正常基线与待测声音 -> 异常分数 | “它是否偏离已知正常状态？” | 异常分数不会自动命名故障或风险 |

ASC、Audio Tagging 和 SED 经常被混为一件事，实际上输出粒度不同。

~~~text
10 秒声音：键盘声 + 两个人交谈 + 空调底噪

ASC：
  主场景 = 办公室

Audio Tagging：
  人声 0.91，键盘 0.86，空调/风扇 0.68

SED：
  键盘 [0.8s, 2.4s]、[4.1s, 6.0s]
  人声 [1.3s, 9.5s]

ASD：
  相对“该环境平时的键盘、人声、空调”基线，异常分数 = 0.07
~~~

### 1.2 场景和事件不是一对一关系

“车辆”能出现在街道、停车场、车内、公交站和维修区；“人声”能出现在办公室、家庭、餐厅、商场和车站。因此，事件标签应被视为推断场景的证据之一，而不是场景的同义词。

较稳妥的场景判断使用多种证据的时间一致性：

| 候选场景 | 支持它的事件组合 | 不足以单独确认的事件 |
| --- | --- | --- |
| 办公室 | 键盘、近距离交谈、空调/风扇、安静背景持续共现 | 只有人声 |
| 家庭厨房 | 流水、锅具碰撞、抽油烟机、近距离人声 | 只有流水 |
| 街道 | 宽带车流、鸣笛、风声、脚步、远距离人声 | 只有一声鸣笛 |
| 车内 | 发动机/路噪、转向灯、近距离人声、密闭混响 | 只有车辆 |
| 地铁或车站 | 广播、轨道/制动声、多人背景声、脚步 | 只有人群声 |

场景类别应该允许“混合”和“未知”。例如室内播放的街景视频可能同时产生“室内房间的混响”和“车流事件”；强行只输出“街道”会给后续分析带来错误证据。

### 1.3 不应作为总开关的语音活动检测

语音活动检测只能判断一段声音中是否存在人声活动。它不能判断环境是否安静，也不能代表没有值得识别的声音。警报、音乐、流水、敲门和机械异响都可能发生在无人讲话时，因此场景识别应直接分析连续音频窗口，而不是先删除非人声部分。

语音活动检测仍可作为一个辅助特征，例如把“人声占比”加入办公室、会议室或餐厅的场景判断；它不应决定其他声音是否进入模型。

### 1.4 何时需要 SELD

若只需识别环境和事件类型，单声道或混合后的单路音频即可训练 ASC、Audio Tagging 或 SED。若输出还包括“来自左侧、右侧、前方或某个方位”，就需要保留多通道时间差、相位差或阵列特征，并采用 SELD 模型和相应数据集。把左右声道混成单声道后，方向相关信息大多已经消失。

## 2. 选型维度与总览

### 2.1 先回答六个问题

| 问题 | 会影响的选择 |
| --- | --- |
| 需要一个场景，还是多个并发声音？ | 单标签 ASC 或多标签 Audio Tagging |
| 是否要事件的起止时间？ | 需要 SED 的帧级输出与事件后处理 |
| 标签是否已经固定？ | 固定标签适合监督微调；开放标签可先用 CLAP 做候选排序 |
| 是否有目标环境的录音和标注？ | 有数据时微调通常比直接套通用标签可靠 |
| 是否存在“其他”类别？ | 必须设计 unknown、mixed、低信噪比和场景切换状态 |
| 是否有分发或商用要求？ | 分别核对代码、权重、训练数据和依赖项条款 |

### 2.2 候选项目总表

| 项目 | 核心能力 | 典型输出 | 最适合的角色 | 主要限制 | 代码许可证状态 |
| --- | --- | --- | --- | --- | --- |
| YAMNet | AudioSet 事件分类、embedding | 521 个事件分数、1024 维 embedding | 通用基线、快速验证、迁移特征 | 事件多于场景；标签固定 | Apache-2.0 |
| PANNs | 多标签分类、可选帧级检测 | 527 类分数、2048 维 embedding、帧级分数 | 强通用基线、自定义标签微调 | 预训练标签和目标场景不完全一致 | MIT |
| EfficientAT | 高效 AudioSet 分类 | 多标签分数、embedding | 低计算量持续推理 | 仍需本地阈值与验证 | MIT |
| DCASE Task 1 / CP-Mobile | 真正的环境场景分类基线 | 预定义环境类别分数 | ASC 研究、跨录音条件泛化对照 | 基线代码未见明确许可 | 未见明确许可证 |
| AST | 谱图 Transformer 分类 | 类别分数、特征 | 封闭分类和有标注微调 | 原始模型不是事件边界方案 | BSD-3-Clause |
| HTS-AT | 分层音频 Transformer、分类与检测 | clip/帧级分数 | 较高上限分类、SED 训练 | 官方权重条款需逐个确认 | MIT |
| BEATs | 自监督声学表征 | embedding、微调后分类分数 | 少量标注条件下的迁移学习 | 官方 checkpoint 条款需单独确认 | MIT |
| LAION-CLAP | 音频-文本对比表征 | 音频/文本 embedding、相似度 | 零样本候选、检索、标签探索 | 提示词敏感，非原生事件边界模型 | CC0-1.0 |
| PaSST | Patchout 谱图 Transformer | 类别分数、特征 | 高质量重型分类对照、蒸馏教师 | 资源开销较高，权重另核 | Apache-2.0 |
| DCASE/DESED | ASC、SED、异常声音检测任务与基线 | 训练配方、基准定义、预测格式 | 可复现实验和评测依据 | 不是单一可直接部署的模型 | 项目和数据分别核对 |
| sed_scores_eval | SED 分数评测 | F1、PSDS、PR/ROC 等 | 事件检测评测 | 不产生分类结果 | MIT |
| torchaudio | 音频读取、特征、训练组件 | 波形、Mel、变换与数据工具 | PyTorch 训练/推理基础设施 | 不提供完整场景模型 | BSD-2-Clause |
| librosa | 声学特征和分析工具 | STFT、Mel、MFCC、PCEN 等 | 研究、特征分析、传统方法 | 非端到端模型框架 | ISC |

“代码许可证状态”只描述代码仓库。权重与训练数据的条款在第 11 节单独处理，不能把代码开源理解为所有模型资产都可自由使用。

## 3. 主要模型与算法库

### 3.1 YAMNet

项目主页：[tensorflow/models 的 YAMNet](https://github.com/tensorflow/models/tree/master/research/audioset/yamnet)；模型说明：[YAMNet README](https://raw.githubusercontent.com/tensorflow/models/master/research/audioset/yamnet/README.md)；标签来源：[AudioSet](https://research.google.com/audioset/)。

YAMNet 是基于 MobileNet v1 的轻量级音频事件分类模型，使用 AudioSet 的 521 类事件标签。它的输入为 16 kHz 单声道波形，内部使用 25 ms 分帧、10 ms 帧移和 64 维 Mel 特征。一个预测帧覆盖约 0.96 秒，通常每约 0.48 秒产生一次新预测，因此非常适合用滑动窗口形成连续标签轨迹。

| 项目 | 说明 |
| --- | --- |
| 架构 | Log-Mel 频谱图加 MobileNet v1 卷积网络 |
| 输出 | 521 类事件分数、1024 维 embedding、Log-Mel 频谱图 |
| 预训练数据 | AudioSet 弱标签音频片段 |
| 擅长 | 常见环境声、人类活动、交通、音乐、动物、警报等宽泛事件 |
| 适合做场景吗 | 可以作为事件证据和迁移特征；要得到“办公室”等场景，需要事件聚合或场景数据微调 |
| 适合做 SED 吗 | 连续窗口分数可以得到粗略时间轨迹；精确边界仍需帧级模型和后处理 |

可采用的算法路径：

~~~text
YAMNet embedding
  -> 用少量已标注场景训练 Logistic Regression / 小型 MLP / LightGBM
  -> 输出目标场景分数
  -> 与原始事件分数共同进入平滑和场景状态机
~~~

这种路径的优点是，目标场景标签不必完全等于 AudioSet 原有标签；代价是必须保留独立验证集，确认迁移后的分类器没有只记住录音地点或背景底噪。

许可证：tensorflow/models 仓库代码是 [Apache-2.0](https://github.com/tensorflow/models/blob/master/LICENSE)。Google 发布的 [YAMNet TensorFlow2/TFLite 模型页](https://www.kaggle.com/models/google/yamnet/tensorFlow2/yamnet/1)标为 Apache-2.0；采用时仍应保留实际下载版本的页面和校验信息。AudioSet 标签体系和源音频权利并不由代码许可证覆盖。

### 3.2 PANNs

项目主页：[PANNs / audioset_tagging_cnn](https://github.com/qiuqiangkong/audioset_tagging_cnn)；论文：[PANNs: Large-Scale Pretrained Audio Neural Networks](https://arxiv.org/abs/1912.10211)；官方 checkpoint：[Zenodo 3987831](https://zenodo.org/records/3987831)。

PANNs 是一组在 AudioSet 上预训练的卷积音频网络。最常见的 Cnn14 使用 Log-Mel 特征和深层卷积，能输出 527 类 AudioSet 标签及 2048 维 embedding。项目也提供 Wavegram-Logmel 系列，以及 DecisionLevelMax 和 DecisionLevelAvg 等可产生更细时间分数的结构。

| 项目 | 说明 |
| --- | --- |
| 架构 | CNN14、ResNet 系列、Wavegram-Logmel 等多种卷积网络 |
| 输出 | 多标签事件分数、2048 维 embedding；特定模型可输出帧级分数 |
| 典型采样率 | 常见 checkpoint 使用 32 kHz，也提供 16 kHz 变体 |
| 擅长 | 多标签事件识别、特征迁移、小样本分类头训练 |
| SED 能力 | DecisionLevel 模型有帧级预测；弱标签预训练仍会使边界较粗，需要专门评测 |
| 适合场景分类 | 用 embedding 训练目标场景头，或把多事件分数聚合为场景证据 |

PANNs 的一个实用价值是“模型输出与目标标签分离”。例如不必把 “Speech”“Typing”“Air conditioning” 原封不动显示出来，可以在自有训练集中把它们作为输入特征，学习“办公室”这个新的目标类。这样模型更容易适应实际录音距离、混响和环境噪声。

应注意两个限制：

1. 弱标签数据通常只说明整段中出现过某类声音，不说明它在每一帧都出现。把 clip 级分数直接切成事件边界，容易产生前后拖尾。
2. Cnn14 的高分标签也可能是相近声音而非真实类别，例如风扇、空调、发动机和持续噪声之间常有混淆，需要看混淆矩阵而不是只看总体准确率。

许可证：代码仓库采用 [MIT License](https://github.com/qiuqiangkong/audioset_tagging_cnn/blob/master/LICENSE.MIT)。上列官方 Zenodo checkpoint 的元数据标为 CC-BY-4.0，使用或再分发时需保留署名。其预训练来源 AudioSet 和原始媒体的权利仍须单独审查。

### 3.3 EfficientAT

项目主页：[EfficientAT](https://github.com/fschmid56/EfficientAT)；论文：[Efficient Audio Tagging](https://arxiv.org/abs/2211.04772)。

EfficientAT 面向 AudioSet 多标签分类的速度、参数量和精度平衡，提供 MobileNet 和 Dynamic MobileNet 等结构。项目 README 给出了不同模型的参数量、MAC 和 mAP，便于在统一约束下比较候选网络。

| 项目 | 说明 |
| --- | --- |
| 核心思想 | 用高效卷积结构降低计算量，同时保留 AudioSet 多标签能力 |
| 输出 | 事件分数和可用于下游任务的中间表征 |
| 适合 | 高频率滑窗分类、资源预算明确的任务、AudioSet 标签微调 |
| 不适合直接解决 | 精确事件边界、开放词汇标签、没有本地校准的自动决策 |

若目标是“每隔较短时间得到稳定的场景变化提示”，EfficientAT 往往比大 Transformer 更容易满足延迟和资源预算。它仍然只是音频标签模型：应结合标签映射、连续平滑和场景切换规则，不能把一次窗口预测作为最终环境结论。

许可证：仓库为 [MIT License](https://github.com/fschmid56/EfficientAT/blob/main/LICENSE)。不同预训练文件、训练数据和第三方依赖的许可应按下载来源检查。

### 3.4 AST

项目主页：[Audio Spectrogram Transformer](https://github.com/YuanGongND/ast)；论文：[AST: Audio Spectrogram Transformer](https://arxiv.org/abs/2104.01778)。

AST 将频谱图切为 patch，再用 Vision Transformer 风格的自注意力网络建模时间和频率关系。它在 AudioSet、ESC-50 和 Speech Commands 等公开任务上建立了有影响力的 Transformer 基线。

| 项目 | 说明 |
| --- | --- |
| 输入表征 | 将 Log-Mel 频谱图切成时间-频率 patch |
| 核心优势 | 可建模较长范围的频率和时间关系，适合有标注数据时微调 |
| 输出 | 通常为 clip 级单标签或多标签分数，也可抽取特征 |
| 适合 | 场景类别固定、训练数据质量较好、允许较高计算量的分类任务 |
| 主要限制 | 原始 clip 分类输出没有逐帧事件边界；长声音需要明确切窗和合并策略 |

AST 的结果质量高度依赖训练和微调时的裁剪长度、频谱参数和数据增强。若训练集中每个类别都来自固定地点或固定录音器材，Transformer 可能学到地点特征而不是场景语义，因此数据划分必须按地点、时间和来源隔离。

许可证：代码仓库采用 [BSD-3-Clause](https://github.com/YuanGongND/ast/blob/master/LICENSE)。官方发布权重和依赖模型的条款需要依据具体模型页确认。

### 3.5 HTS-AT

项目主页：[HTS-Audio-Transformer](https://github.com/RetroCirce/HTS-Audio-Transformer)；论文：[HTS-AT](https://arxiv.org/abs/2202.00874)。

HTS-AT 是 Hierarchical Token-Semantic Audio Transformer。它以层级 Transformer 处理频谱图，并将 token 语义用于音频分类和事件检测。项目中常见模型规模约 30M 参数，适合需要较高分类上限且可以承担 Transformer 推理成本的任务。

| 项目 | 说明 |
| --- | --- |
| 核心能力 | AudioSet 音频标签、DESED 等事件检测任务的训练路线 |
| 输出粒度 | clip 级分数；按 SED 训练配置可得到帧级或时间分辨率预测 |
| 适合 | 多标签分类、已定义事件类别、需要转向 SED 的统一研究栈 |
| 优点 | 层级结构有利于处理较大频谱输入；项目覆盖分类和检测代码路径 |
| 注意 | SED 质量取决于帧率、损失函数、弱/强标签比例和边界后处理 |

HTS-AT 不是“只要输入长音频就自动给出可靠边界”的模型。事件检测训练需要明确标注每个事件的起止时间，或使用弱标签、合成强标签和伪标签等半监督策略。没有对应监督时，输出应解释为连续置信分数，不应假设为精确事件时间。

许可证：代码仓库为 [MIT License](https://github.com/RetroCirce/HTS-Audio-Transformer/blob/main/LICENSE)。项目提供的 Google Drive checkpoint 未见统一、明确的独立权重许可证，应在采用具体文件前确认。

### 3.6 BEATs

项目主页：[Microsoft BEATs](https://github.com/microsoft/unilm/tree/master/beats)；论文：[BEATs: Audio Pre-Training with Acoustic Tokenizers](https://arxiv.org/abs/2212.09058)。

BEATs 的重点不是先定义一套事件标签，而是通过声学 tokenizer 做自监督预训练，学习可迁移的通用音频表征。下游任务可直接使用 embedding，也可以针对场景或事件标签进行微调。

| 项目 | 说明 |
| --- | --- |
| 核心思想 | 从大量声音中学习离散声学 token，再训练通用表征 |
| 典型输入 | 示例通常使用 16 kHz 音频 |
| 输出 | embedding；加载下游微调权重后可输出任务类别分数 |
| 适合 | 自有标签较少、希望复用预训练声学知识、需要统一特征空间 |
| 主要限制 | 预训练 embedding 本身不是最终场景标签；仍需分类头、阈值和验证集 |

与直接使用 AudioSet 标签模型相比，BEATs 适合“先抽取稳定表征，再训练自己的小型分类器”的路线。例如可对一个窗口取 embedding，使用线性分类器、原型距离或小型 MLP 判断目标场景。数据量很少时，冻结大部分编码器、只训练分类头，通常比从头训练更稳。

许可证：unilm 仓库代码采用 [MIT License](https://github.com/microsoft/unilm/blob/master/LICENSE)。官方 OneDrive checkpoint 没有统一的独立许可证声明，不能把代码的 MIT 条款直接延伸到权重和训练资产。

### 3.7 LAION-CLAP

项目主页：[LAION-CLAP](https://github.com/LAION-AI/CLAP)；论文：[CLAP: Learning Audio Concepts From Natural Language Supervision](https://arxiv.org/abs/2211.06687)；HTSAT fused 权重页：[laion/clap-htsat-fused](https://huggingface.co/laion/clap-htsat-fused)。

CLAP 将音频和文本编码到同一个向量空间。给定一段声音和若干文字候选，例如“繁忙的城市街道”“安静办公室”“水龙头流水”“火灾警报”，模型可计算音频向量与每条文字向量的相似度并排序。

| 项目 | 说明 |
| --- | --- |
| 核心能力 | 音频-文本对比学习、零样本标签排序、音频检索 |
| 输出 | 音频 embedding、文本 embedding、余弦相似度或排序分数 |
| 典型用途 | 冷启动探索、候选召回、开放标签检索、人工标注辅助 |
| 不适合直接承担 | 精确事件边界、高风险自动判断、未经校准的最终分类 |

CLAP 的关键不是“能认识任意文字”，而是“能对候选文字排序”。提示词会显著影响结果。例如“traffic”“sound of city traffic”“a busy street with vehicle noise”可能得到不同排序；因此应把同义提示词作为一个 prompt ensemble，并在目标数据集上验证。

建议的零样本使用方式：

~~~text
为每个业务标签准备多条同义描述
  -> 计算每条文本与窗口音频的相似度
  -> 对同一标签的多条描述求均值或最大值
  -> 只保留候选前 K 类
  -> 用本地标注数据校准阈值，或交给人工确认
~~~

LAION-CLAP 代码仓库目前采用 [CC0-1.0](https://github.com/LAION-AI/CLAP/blob/main/LICENSE)。上述 Hugging Face HTSAT fused 权重页标为 Apache-2.0；但 [LAION-Audio-630K 的 Credits & Licence](https://github.com/LAION-AI/audio-dataset/blob/main/laion-audio-630k/README.md#credits--licence) 明确指出，通过 CSV 下载的音频仅限研究用途，除非取得原始数据源权利人的许可。权重页的 Apache-2.0 不会消除这项上游训练数据限制；商业采用应对具体训练来源进行权利和法务审查，并在需要时取得权利人许可。代码条款、权重页条款和训练数据来源必须分别保留记录。

### 3.8 Microsoft CLAP 与 LAION-CLAP 不能混用许可证结论

“CLAP”是方法名，不代表所有实现和权重使用同一许可证。Microsoft 的 [msclap](https://github.com/microsoft/CLAP) 代码为 MIT，发布的不同 checkpoint 可见 CC-BY-3.0-US 或 MS-PL 等不同条款。LAION-CLAP 代码为 CC0-1.0，部分官方权重为 Apache-2.0。使用时必须记录具体仓库、版本号和权重下载页，不能只写“CLAP 可商用”。

### 3.9 AudioMAE：适合研究，不应列入商用候选

项目主页：[AudioMAE](https://github.com/facebookresearch/AudioMAE)。

AudioMAE 使用掩码自编码器预训练频谱图表征，对少量标注微调和迁移学习有研究价值。它适合作为“无监督或自监督预训练如何帮助声音分类”的对照项目。

该仓库根目录的许可证是 [CC-BY-NC-4.0](https://github.com/facebookresearch/AudioMAE/blob/main/LICENSE)，含非商业限制。项目 README 中的许可表述如与根 LICENSE 不一致，应按更严格的根 LICENSE 处理。因此它不应作为有商用要求的默认候选；可以保留在研究对比中，但不得因为模型效果好而跳过许可限制。

### 3.10 PaSST

项目主页：[PaSST](https://github.com/kkoutini/PaSST)；论文：[Efficient Training of Audio Transformers with Patchout](https://arxiv.org/abs/2110.05069)。

PaSST 是 Patchout Audio Spectrogram Transformer。它在训练阶段按策略省略一部分频谱 patch，以降低标准谱图 Transformer 的训练计算与内存成本。它常用于高质量音频分类比较，也可作为轻量模型蒸馏时的教师网络。

| 项目 | 说明 |
| --- | --- |
| 核心能力 | 以 Transformer 建模谱图 patch，并用 Patchout 降低开销 |
| 适合 | 有较充足计算预算的 AudioSet 标签、场景或事件分类实验 |
| 与 EfficientAT 的关系 | EfficientAT 的方法使用较强 Transformer 表征作为知识蒸馏来源之一 |
| 不适合直接解决 | 精确事件边界、无标注环境的自动场景命名 |

许可证：代码仓库采用 [Apache-2.0](https://github.com/kkoutini/PaSST/blob/main/LICENSE)。预训练权重、训练数据和任何蒸馏来源仍需按具体发布资产审查。

## 4. 事件检测、异常检测和评测项目

### 4.1 DCASE Task 1：环境场景分类基线

[DCASE](https://dcase.community/) 是声音与场景分析公开评测社区，长期维护 ASC、SED、异常声音检测等任务定义、数据集和基线。它不是一个单一模型库，更像一套可复现实验的坐标系。

[DCASE 2024 Task 1](https://dcase.community/challenge2024/task-data-efficient-low-complexity-acoustic-scene-classification) 明确将 ASC 定义为把录音归入地铁站、城市公园、公共广场等环境类别，并且特别考察跨录音条件的泛化。它是“环境场景”而不是“声音事件”的直接公开基准。

官方 [CPJKU 基线](https://github.com/CPJKU/dcase2024_task1_baseline) 使用简化 CP-Mobile、因子化卷积、倒残差结构和 Frequency-MixStyle。公开说明中的基线约为 61,148 个参数、每秒约 29.42 MMAC，显示了真正 ASC 也可以采用很小的网络。

| 项目 | 适合借鉴的内容 | 不能直接假设的内容 |
| --- | --- | --- |
| DCASE Task 1 | 场景定义、数据切分、跨条件验证、低复杂度约束和指标 | 任一赛年数据都可用于任意用途 |
| CP-Mobile 基线 | 轻量 CNN、Frequency-MixStyle、环境场景训练配方 | 该代码仓库已有可直接商用授权 |

CPJKU 基线仓库当前未见明确 LICENSE 文件或 SPDX 许可证声明，因此应把它用作算法和评测参考，不能把它列为已获得商用源代码授权的依赖。

### 4.2 DESED：声音事件检测基准

[DESED](https://project.inria.fr/desed/) 是面向家庭/家居（Domestic）环境声音事件检测的数据集和研究项目，常见任务包含弱标签、未标注数据、合成强标签和真实强标签的组合。它适合研究下列问题：

| 问题 | 常见算法 |
| --- | --- |
| 只有整段标签，没有精确边界 | Multiple Instance Learning、attention pooling、弱标签训练 |
| 部分样本有边界，部分没有 | 半监督训练、伪标签、一致性正则化 |
| 事件可重叠 | 多标签帧级 sigmoid 输出，而不是 softmax 单选 |
| 边界抖动 | 中值滤波、滞回、最短持续时长、短间隙合并 |
| 不同环境差异大 | 数据增强、域自适应、按地点隔离验证 |

使用 DCASE 或 DESED 的价值不是“直接复制一个分数”，而是复用任务定义、数据切分和指标，避免只在容易的随机切分上得到虚高结果。DCASE 数据和各赛题基线的代码、音频和注释文件均可能有独立许可，需分别核对。

### 4.3 异常声音检测

异常声音检测的目标是发现“与已知正常声音不同”的片段。它通常没有足够的异常类别样本，因此不能简单训练“正常/异常”二分类器后期待识别所有未知故障。

常见算法包括：

| 方法 | 核心做法 | 优点 | 风险 |
| --- | --- | --- | --- |
| 重建误差 | 用正常样本训练 autoencoder，重建差异越大分数越高 | 思路直观，正常数据足够时有效 | 模型可能也能重建部分异常，或把环境变化误报为异常 |
| embedding 距离 | 从 BEATs、PANNs、YAMNet 等提取向量，计算到正常原型、kNN 或高斯分布的距离 | 易替换表征，便于分析最近正常样本 | 需要覆盖正常变化，否则新环境会被误报 |
| One-Class / Deep SVDD | 把正常向量压到紧密区域，离中心越远越异常 | 对没有异常样本的情形有用 | 中心与阈值容易过拟合 |
| 密度模型 | 在正常 embedding 上拟合 GMM、Normalizing Flow 等密度 | 能刻画多模态正常状态 | 对数据量、稳定性和校准要求较高 |
| 预测误差 | 从前一段特征预测后一段特征，偏差大则异常 | 可利用时间连续性 | 对场景切换很敏感 |

异常分数只能表达“偏离正常基线的程度”，不能等于“确定存在某种故障”。如果需识别具体异常类型，应在异常发现后增加有标签的事件分类器，或收集对应异常样本训练开放集分类器。

DCASE 的 [2024 Task 2](https://dcase.community/challenge2024/task-first-shot-unsupervised-anomalous-sound-detection-for-machine-condition-monitoring) 提供异常声音检测的任务定义与基线思路。赛题编号、数据和基线会随赛年变化，应按目标赛年复核；其任务数据和具体赛年仓库不能自动视为通用商用素材。

### 4.4 sed_scores_eval

项目主页：[sed_scores_eval](https://github.com/fgnt/sed_scores_eval)；论文：[Threshold-Independent Evaluation of Sound Event Detection Scores](https://arxiv.org/abs/2201.13148)。

SED 模型往往输出每一帧的连续分数。只用一个固定阈值算 F1，容易把阈值选择和模型能力混在一起。sed_scores_eval 可以直接分析连续分数，计算不同定义下的 PR、ROC、F1、PSDS 等指标。

| 能力 | 含义 |
| --- | --- |
| Collar 评测 | 允许开始和结束附近存在一定时间误差 |
| Intersection 评测 | 以预测段和真值段的交集比例判断匹配 |
| Segment 评测 | 按固定时长切段比较，适合粗粒度检测 |
| PSDS | 在不同阈值与误报代价下综合 SED 表现 |
| 阈值扫描 | 为每个类别选取满足误报目标的阈值 |

许可证：代码为 [MIT License](https://github.com/fgnt/sed_scores_eval/blob/main/LICENSE)。

### 4.5 torchaudio、librosa 与执行器

| 项目 | 主页 | 适合承担的工作 | 许可证 |
| --- | --- | --- | --- |
| torchaudio | [pytorch/audio](https://github.com/pytorch/audio) | 音频读取、重采样、Mel 频谱、数据管线、PyTorch 训练组件 | [BSD-2-Clause](https://github.com/pytorch/audio/blob/main/LICENSE) |
| librosa | [librosa/librosa](https://github.com/librosa/librosa) | STFT、Mel、MFCC、PCEN、节奏与频谱分析、研究验证 | [ISC](https://github.com/librosa/librosa/blob/main/LICENSE.md) |
| ONNX Runtime | [microsoft/onnxruntime](https://github.com/microsoft/onnxruntime) | 执行已导出的 ONNX 模型，提供跨平台推理与性能工具 | [MIT](https://github.com/microsoft/onnxruntime/blob/main/LICENSE) |
| sherpa-onnx | [k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | ONNX 音频模型运行库，包含 audio tagging 的示例与绑定 | [Apache-2.0](https://github.com/k2-fsa/sherpa-onnx/blob/master/LICENSE) |

它们是工具或执行库，不是现成的场景模型。它们的价值是确保训练、验证和推理阶段使用相同的采样率、声道处理、特征参数和归一化逻辑。若训练使用 64 维 Mel、特定对数压缩和标准化，而推理改成另一套处理，模型精度会明显下降。sherpa-onnx 的代码许可不覆盖其模型库中每个模型包的权重和数据来源，仍需单独审查。

## 5. 从声音到场景结果的核心算法

### 5.1 统一音频表示

不同预训练模型要求的采样率和声道不同，必须遵照模型说明。常见处理包括：

~~~text
原始波形
  -> 解码为浮点或定点 PCM
  -> 按模型要求重采样
  -> 多通道时决定保留空间信息或下混
  -> 按固定窗口切分
  -> STFT
  -> Mel 滤波组
  -> log-Mel、PCEN 或模型指定归一化
  -> 分类、检测或 embedding 模型
~~~

常用 Log-Mel 表示可写为：

~~~text
X = STFT(x)
P = |X|^2
M = log(max(epsilon, Mel(P)))
~~~

其中 x 是波形，STFT 把波形变为时间-频率图，Mel 把频率轴压缩到接近人耳分辨率的尺度，epsilon 防止对零取对数。模型训练时的窗口长度、帧移、Mel 通道数、频率范围和归一化方式都属于模型定义的一部分。

### 5.2 Log-Mel、MFCC 与 PCEN

| 特征 | 适合情况 | 优点 | 限制 |
| --- | --- | --- | --- |
| Log-Mel | CNN、Transformer 和绝大多数预训练音频模型 | 信息完整、生态成熟 | 对增益变化和持续噪声可能敏感 |
| MFCC | 传统分类器、低维特征基线 | 维度小，易解释 | 丢失部分细粒度频谱信息 |
| PCEN | 音量变化大、背景噪声变化大的连续声音 | 自动增益控制式压缩，增强弱事件 | 参数需要与数据匹配，不能盲目替换预训练模型输入 |
| 波形前端 | Wavegram、端到端模型 | 可学习低层滤波 | 训练成本和复现难度较高 |

预训练模型已固定输入处理时，应优先复用其原始特征管线。把某模型的 Log-Mel 改成 MFCC，通常不是“优化”，而是改变了训练分布。

### 5.3 CNN、CRNN、Transformer 与 embedding

| 算法结构 | 如何工作 | 更适合什么 |
| --- | --- | --- |
| CNN | 在频谱的局部时间-频率区域提取纹理 | 稳定的音色、冲击声、低计算量标签任务 |
| CRNN | CNN 提特征，RNN 沿时间序列建模 | 需要帧级序列输出的 SED |
| Transformer | 注意力直接关联相隔较远的频谱 patch | 长上下文、复杂事件组合、高质量微调 |
| embedding 模型 | 输出固定长度向量，再接分类、距离或检索层 | 小样本迁移、异常检测、标签体系常变的任务 |
| 音频-文本对比模型 | 让音频和文字向量相近 | 零样本候选、开放标签检索和标注辅助 |

分类结构决定上限，标签设计、数据质量、阈值校准和边界规则通常决定最终可用性。一个较小的 CNN 在匹配数据上可能比未校准的大模型更可靠。

### 5.4 单标签与多标签损失

场景类别互斥时，常用 softmax 和交叉熵：

~~~text
p_i = exp(z_i) / sum(exp(z_j))
L = -sum(y_i * log(p_i))
~~~

并发声音通常不互斥，应为每个类别独立使用 sigmoid 与二元交叉熵：

~~~text
p_i = sigmoid(z_i)
L = -sum(y_i * log(p_i) + (1 - y_i) * log(1 - p_i))
~~~

将“键盘”“人声”“音乐”放进 softmax 单选分类，会强迫模型只保留一个声音，天然不适合真实混合环境。

### 5.5 从事件分数聚合为场景分数

有两条常用路线：

| 路线 | 做法 | 优点 | 风险 |
| --- | --- | --- | --- |
| 规则聚合 | 给各事件分数设置场景证据权重和共现条件 | 易解释、便于快速验证 | 权重容易随环境变化失效 |
| 学习聚合 | 以事件分数、embedding、统计量为输入训练场景分类器 | 能学到更复杂的组合关系 | 需要场景标注，并防止数据泄漏 |

规则聚合示例：

~~~text
office_score =
  0.35 * typing
  + 0.25 * near_speech
  + 0.15 * fan_or_air_conditioner
  + 0.15 * quiet_indoor_reverb
  - 0.20 * sustained_traffic
~~~

这只能作为可解释的起点。真正使用前，应依据目标录音数据学习权重或至少验证规则是否在不同地点成立。不能把一套人工权重当成通用事实。

## 6. 连续窗口、稳定结果和事件边界

### 6.1 为什么不能只看一次窗口

单个窗口可能被短促撞击、远处音乐、风噪或录音增益变化影响。更可靠的输出要区分“当前候选”和“稳定状态”：

~~~text
窗口分数
  -> 每类平滑
  -> 进入阈值 / 退出阈值
  -> 连续命中计数
  -> 最短持续时间
  -> 短间隙合并
  -> 稳定场景或事件区间
~~~

这个过程适用于 ASC、Audio Tagging 和 SED，只是各任务的窗口长度和时间精度不同。

### 6.2 滑动窗口

窗口长度决定上下文，步长决定更新频率：

| 场景 | 常见窗口思路 | 步长思路 | 说明 |
| --- | --- | --- | --- |
| 主场景分类 | 2 到 10 秒 | 0.5 到 2 秒 | 场景变化通常较慢，应减少短促干扰 |
| 通用事件标签 | 约 1 到数秒 | 约 0.25 到 1 秒 | 兼顾更新时间和上下文 |
| 短促事件检测 | 数百毫秒到数秒 | 小于窗口长度 | 需要更密时间分辨率 |
| 异常检测 | 依正常基线稳定性决定 | 可与主场景窗口同步 | 先明确“正常变化”尺度 |

YAMNet 的约 0.96 秒窗口和约 0.48 秒更新间隔是一个容易复现的通用事件标签基线，不代表所有任务都应固定采用该参数。

### 6.3 分数平滑

指数滑动平均可减少单帧跳变：

~~~text
s_bar(t) = alpha * s(t) + (1 - alpha) * s_bar(t - 1)
~~~

其中 s(t) 是当前类别分数，s_bar(t) 是平滑分数，alpha 越大越相信当前窗口。也可用中值滤波抑制孤立尖峰：

~~~text
s_bar(t) = median(s(t-k), ..., s(t), ..., s(t+k))
~~~

平滑会带来延迟，因此需同时报告“更新延迟”和“事件边界误差”。对于火警、碰撞等短促重要事件，过长平滑可能错过真实发生时刻。

### 6.4 双阈值滞回

每类事件建议采用进入阈值 T_on 和退出阈值 T_off，且 T_on 大于 T_off：

~~~text
若当前未激活，且 s_bar >= T_on：进入 active
若当前已激活，且 s_bar < T_off：离开 active
其他情况：保持现有状态
~~~

双阈值避免分数在单个阈值附近上下波动时反复开始和结束。不同声音类别需要不同阈值：持续的风扇声和稀有警报声的正负样本比例、分数分布和误报代价都不同。

### 6.5 最短持续时间与短间隙合并

事件边界后处理至少应考虑：

| 规则 | 作用 | 例子 |
| --- | --- | --- |
| 最短事件时长 | 删除短于合理物理时长的孤立命中 | 20 ms 的“持续音乐”通常是噪声 |
| 最短静默间隙 | 合并很短的中断 | 连续警报中间掉一帧低分不应分成两次 |
| 预滚和后滚 | 补偿模型窗口覆盖和滤波延迟 | 预测在 1.0 秒变高，可向前回退少量时间 |
| 最大事件时长 | 发现一直不退出的类别漂移 | 连续数小时高分事件需检查模型或阈值 |
| 结束刷新 | 将尚未关闭的活动事件以最后有效时间闭合 | 保证每个事件都有完整区间 |

这些规则应由验证集选择，不应以感觉设定。尤其“最短时长”必须匹配声音物理特征：敲门可以短，空调和车流可以长。

### 6.6 场景切换状态机

主场景不宜因为一个窗口改变。一个简单状态机可包含：

| 状态 | 转移条件 |
| --- | --- |
| stable_scene | 当前主场景连续领先，且差距超过 margin |
| candidate_scene | 新场景连续若干窗口超过进入阈值 |
| scene_transition | 新旧场景差距小、混合声音增加或预测快速翻转 |
| mixed | 两个以上场景证据同时稳定且无法判定主次 |
| unknown | 最高分低于类别阈值，或超出训练分布 |

场景切换期间输出 transition、mixed 或 unknown 往往比错误地立即给出单一新场景更有价值。

## 7. 标签体系设计

### 7.1 分层标签而不是一张巨大清单

建议将标签分成“环境场景”“声音事件”“质量和状态”三层：

| 层级 | 示例 | 作用 |
| --- | --- | --- |
| 环境场景 | 办公室、家庭、厨房、餐厅、商店、街道、公园、车内、公交、地铁、车站、机场 | 回答整体环境 |
| 声音事件 | 人声、音乐、键盘、脚步、敲门、关门、流水、车辆、鸣笛、警报、犬吠 | 回答具体声音和时间 |
| 质量/状态 | unknown、mixed、low_snr、scene_transition、silence | 表达不确定性和输入质量 |

这样既能回答“现在更像街道”，也能回答“听到车流和鸣笛”，不会把两类语义混成同一个标签。

### 7.2 标签命名原则

1. 同一层级保持粒度相近。不要把“室内”与“厨房”和“水龙头流水”放在同一单选列表。
2. 为每个标签写出正例、反例、边界例和允许共存的标签。
3. 明确标签是否互斥。场景可能主次互斥，事件通常可并发。
4. 保留 unknown 和 other，不要强制每个样本落入已有类别。
5. 对含义相近的标签建立父子关系，例如“交通 -> 轨道交通 -> 地铁”。
6. 版本化标签字典。类别定义变化后，旧模型分数不可与新模型直接比较。

### 7.3 标注例子

| 片段描述 | 主场景 | 事件标签 | 状态 |
| --- | --- | --- | --- |
| 安静房间中持续键盘与近距离交谈 | 办公室 | 键盘、人声、空调/风扇 | stable |
| 路边车流、风声与偶发鸣笛 | 街道 | 车辆、风声、鸣笛、脚步 | stable |
| 地铁进站时的制动和广播 | 地铁或车站 | 轨道车辆、广播、多人背景声 | stable |
| 室内播放街景视频 | 室内 | 车辆、音乐或视频声音 | mixed |
| 强风或失真覆盖大部分频段 | unknown | 风噪 | low_snr |

### 7.4 类别不平衡

警报、敲门、碰撞等重要事件往往稀少；持续噪声或静音往往占大多数。训练和评测时应考虑：

| 手段 | 作用 |
| --- | --- |
| class weight / focal loss | 增大稀有类别的损失权重 |
| 重采样 | 提升少数类出现频率，避免全是背景 |
| 事件级切分 | 避免同一个事件片段跨训练和验证集合 |
| 类别独立阈值 | 不让高频类和稀有类共用一个阈值 |
| macro 指标 | 防止多数类掩盖少数类失败 |

## 8. 模型结果与置信度

### 8.1 推荐的算法结果要素

每一条模型结果至少应保留以下语义信息，便于离线评测、误差分析和版本追踪：

| 字段含义 | 说明 |
| --- | --- |
| 窗口开始和结束时间 | 分数覆盖的声音时间范围 |
| 主场景 | 当前最可能的环境标签或 unknown/mixed |
| Top-K 标签 | 前若干事件或场景候选及各自分数 |
| 分数 | 原始模型分数、平滑后分数或相似度，必须标明来源 |
| 阈值版本 | 该结论使用的类别阈值和后处理版本 |
| 事件开始和结束时间 | SED 形成的事件区间 |
| 状态 | candidate、stable、mixed、unknown、low_snr、scene_transition 等 |
| 模型与类别表版本 | 确保历史结果可解释和可复现 |

“分数”不是天然概率。神经网络的 sigmoid、softmax 或相似度通常只适合作为排序依据；只有在独立校准集上验证后，才可把它解释为接近真实发生概率的数值。

### 8.2 校准

常用校准方法：

| 方法 | 适用情况 | 注意 |
| --- | --- | --- |
| 温度缩放 | 输出为 logits 的单标签或多标签模型 | 简单有效，但需独立校准集 |
| Platt scaling | 二分类或单个事件类别 | 样本少时可能不稳定 |
| Isotonic regression | 分数与真实概率关系明显非线性 | 容易在小数据集过拟合 |
| 每类阈值扫描 | 以漏报、误报或 F1 为目标 | 阈值随场景和数据分布变化 |

高风险规则不能直接使用“分数大于 0.5”。应先定义每类允许的漏报、每小时误报和确认成本，再在独立测试集上选择阈值。

### 8.3 unknown 与开放集问题

通用模型的标签不可能覆盖所有声音。若最高分很低、多个类别接近、embedding 到已知类别距离过远，或音频质量很差，结果应输出 unknown、mixed 或 low_snr。强行选择最高分类会把未知声音伪装成已知类别，且这种错误在真实环境中往往很隐蔽。

可用的 unknown 规则包括：

~~~text
max_score < T_unknown
或 top1_score - top2_score < margin
或 embedding_distance_to_known_prototype > D_unknown
或 quality_score < Q_min
~~~

这些条件应在目标环境数据上联合校准。

## 9. 训练、微调和数据集

### 9.1 可参考的数据集

| 数据集 | 主要能力 | 适合用途 | 注意 |
| --- | --- | --- | --- |
| [AudioSet](https://research.google.com/audioset/) | 527 类通用声音事件 | 通用预训练、标签本体参考 | 弱标签、原始媒体权利复杂 |
| [FSD50K](https://zenodo.org/records/4060432) | 大规模开放声音事件 | 多标签分类、补充训练和评测 | 单条音频可能含 CC-BY-NC 等限制；商用前应逐项核对并联系维护方 |
| [ESC-50](https://github.com/karolpiczak/ESC-50) | 50 类环境声音 | 小规模基准、快速对比 | 类别和真实长时环境有限 |
| [UrbanSound8K](https://urbansounddataset.weebly.com/urbansound8k.html) | 城市声音事件 | 城市噪声和事件实验 | 数据规模有限，许可需核对 |
| [TAU Urban Acoustic Scenes](https://dcase.community/challenge2022/task-acoustic-scene-classification) | 城市场景分类 | ASC 训练和评测 | 不同赛年条款可能不同 |
| [DESED](https://project.inria.fr/desed/) | 家庭/家居环境声音事件与检测 | SED、弱监督和半监督研究 | 数据、合成部分和基线分别核对 |
| [MIMII](https://zenodo.org/records/3384388) | 机器运行声音 | 异常声音检测研究 | 不能直接代替其他领域的正常基线 |

数据集是模型可用性的核心。预训练模型在公开基准上表现优良，不代表它对新的房间、城市、语言背景、混响、话筒距离或噪声源组合仍然准确。

### 9.2 数据切分必须按来源隔离

随机把相邻窗口分到训练集和测试集，会造成严重泄漏：模型可能记住同一地点的混响、相同背景噪声或同一声音源，而不是真正学会标签。

应至少按下列维度之一隔离：

| 隔离维度 | 防止的泄漏 |
| --- | --- |
| 地点 | 记住房间或街区的固定声学特征 |
| 采集日期 | 记住同一天的背景状态 |
| 声音源实例 | 同一辆车、同一台机器或同一段素材同时进入两边 |
| 场景会话 | 相邻重叠窗口泄漏 |
| 录音条件 | 记住固定增益、编码或通道特征 |

### 9.3 训练增强

常见增强包括随机增益、混合背景声、混响、带宽限制、时间平移、SpecAugment 和 Mixup。增强必须符合标签语义：

| 增强 | 通常有帮助的地方 | 可能造成的问题 |
| --- | --- | --- |
| 随机增益 | 对音量变化更稳健 | 会掩盖真实响度特征 |
| 背景混合 | 提升混合环境鲁棒性 | 标签可能变成不完整的弱标签 |
| 混响 | 提升室内距离和房间变化适应性 | 过度混响会变成不现实样本 |
| 时间平移 | 减少模型依赖事件位置 | 对边界标注必须同步平移 |
| SpecAugment | 提升频谱局部缺失鲁棒性 | 过强可能抹掉短事件 |
| Mixup | 改善多标签泛化 | 标签处理必须与混合比例一致 |

### 9.4 微调策略

| 数据量与目标 | 推荐起点 |
| --- | --- |
| 标签很少，类别固定 | 冻结 YAMNet、PANNs 或 BEATs 编码器，只训练线性分类头 |
| 标签中等，环境差异明显 | 解冻高层网络，小学习率微调，严格留出地点验证集 |
| 要精确事件边界 | 使用带强时间标注的 SED 模型，训练帧级多标签输出 |
| 标签还在探索 | CLAP 生成候选，人工复核后形成稳定标签集，再训练监督模型 |
| 正常样本多、异常少 | 先做 embedding 距离或重建误差基线，再收集难例迭代 |

## 10. 评测指标与验收方法

### 10.1 ASC

| 指标 | 解释 | 为什么需要 |
| --- | --- | --- |
| Accuracy | 全部样本中判断正确的比例 | 易理解，但会被大类样本主导 |
| Balanced Accuracy | 每类召回率的平均 | 类别不均衡时更可靠 |
| Macro F1 | 各类别 F1 平均 | 每个场景同等重要时适用 |
| 混淆矩阵 | 真值与预测类别的交叉表 | 能找出“车内/街道”等相近场景的系统性错误 |

### 10.2 Audio Tagging

| 指标 | 解释 |
| --- | --- |
| mAP | 对每个标签的排序质量求平均，适合多标签问题 |
| lwlrap | 按标签频率加权的排序平均精度，常用于 AudioSet 风格多标签任务 |
| micro F1 | 将所有标签整体统计，受高频类影响较大 |
| macro F1 | 先算每个标签 F1 再平均，更能暴露稀有类失败 |
| 每类 PR 曲线 | 展示阈值变化下的精确率和召回率 |
| 每类 AUROC | 评估分数排序能力，但极不平衡时不应单独使用 |

### 10.3 SED

| 指标 | 解释 |
| --- | --- |
| Event-based F1 | 预测事件与真值事件按边界容忍规则匹配 |
| Segment-based F1 | 固定时间块内是否检测到事件 |
| PSDS | 综合不同阈值、误报成本和跨类混淆的曲线面积 |
| IoU | 预测时间段与真值时间段重叠比例 |
| 每小时误报 | 连续声音中虚假事件的实际负担 |
| 漏报率 | 真正事件未被发现的比例 |

### 10.4 可靠性和鲁棒性

除准确率外，还应测量：

| 项目 | 检查方式 |
| --- | --- |
| 置信度校准 | ECE、Brier score、可靠性图 |
| 未知类误触发 | 给模型未训练过的声音，观察是否强行归类 |
| 噪声鲁棒性 | 改变信噪比、混响、增益、编码后测试 |
| 域外泛化 | 用新地点、新日期、新录音条件测试 |
| 长时稳定性 | 统计预测翻转次数、事件碎片数和错误持续时间 |
| 延迟 | 从声音出现到稳定输出的时间，不只看单次模型耗时 |

## 11. 开源许可和商用核查

### 11.1 必须分开看的四层

| 层级 | 必须确认的内容 |
| --- | --- |
| 代码 | 仓库 LICENSE、依赖许可证、修改和分发义务 |
| 权重 | 模型页、release、Zenodo 或对象存储中该文件的明确条款 |
| 训练数据 | 音频、标注、下载方式和衍生使用边界 |
| 输出与内容 | 输入音频的权利、输出结果的使用范围和隐私要求 |

代码是 MIT 或 Apache-2.0，不表示权重和训练音频也使用同样条款。没有明确权重许可时，应把它列为“需取得确认”，而不是默认可商用。

### 11.2 项目许可核查表

| 项目 | 代码 | 权重或数据的已知情况 | 使用结论 |
| --- | --- | --- | --- |
| YAMNet | tensorflow/models 为 Apache-2.0 | 官方 Kaggle YAMNet TensorFlow2/TFLite 页标为 Apache-2.0；AudioSet 源媒体权利另计 | 代码与该权重页条件明确，资产需留存来源记录 |
| PANNs | MIT | 官方 Zenodo 3987831 标为 CC-BY-4.0；AudioSet 来源另核 | 需保留权重署名和数据溯源 |
| EfficientAT | MIT | 每个 checkpoint 的发布页和训练来源需确认 | 代码可用，权重不能一概而论 |
| DCASE Task 1 CP-Mobile | 基线仓库未见明确许可证 | 赛题数据、基线与赛年材料分别核对 | 可借鉴算法和评测，不能默认作为商用源码依赖 |
| AST | BSD-3-Clause | 官方权重与依赖预训练来源须逐项确认 | 代码可用，权重另审 |
| HTS-AT | MIT | Google Drive checkpoint 未见统一独立许可 | 不应把 checkpoint 默认列为可商用 |
| BEATs | MIT | 官方 OneDrive checkpoint 未见统一独立许可 | 不应把 checkpoint 默认列为可商用 |
| LAION-CLAP | CC0-1.0 | 部分官方 Hugging Face 权重为 Apache-2.0；LAION-Audio-630K 的 CSV 音频仅限研究用途，除非获原始权利人许可 | 权重页不消除训练数据限制；商用须专项审查并按需取得许可 |
| Microsoft CLAP | MIT | 具体 checkpoint 可能为 CC-BY-3.0-US 或 MS-PL 等 | 不可与 LAION-CLAP 共用许可结论 |
| PaSST | Apache-2.0 | 权重、训练数据和蒸馏来源按具体资产核查 | 代码条件明确，预训练资产另审 |
| AudioMAE | CC-BY-NC-4.0 | 非商业限制随代码而存在 | 排除出商用默认候选 |
| sed_scores_eval | MIT | 无预训练权重问题 | 可作为评测工具候选 |
| torchaudio | BSD-2-Clause | 预训练管线或下载资产另核 | 工具库本身条款明确 |
| librosa | ISC | 无预训练权重问题 | 工具库本身条款明确 |

### 11.3 AudioSet 的特殊点

AudioSet 的 [下载说明](https://research.google.com/audioset/download.html)将 CSV 和部分特征以 CC-BY-4.0 发布，ontology 为 CC-BY-SA-4.0；原始声音通常来自外部视频平台，版权与可用性不由代码仓库或模型权重自动解决。使用由 AudioSet 预训练得到的模型时，应记录模型发布者对权重的许可说明，并为数据来源保留审计材料。

## 12. 按需求选择的建议

| 需求 | 推荐组合 | 原因 |
| --- | --- | --- |
| 直接判断办公室、地铁、街道等环境 | DCASE Task 1 的标签与数据切分为参照，使用 EfficientAT、PANNs、AST 或 HTS-AT 在目标环境数据上训练 | 环境场景与通用事件标签不是同一问题 |
| 想先看到常见声音类别 | YAMNet + 类别词表 + 连续平滑 | 资料完整，基线容易复现 |
| 希望把多个事件推断成自有场景 | PANNs/YAMNet/BEATs embedding + 自有场景分类头 | 让目标标签由实际数据决定 |
| 需要低计算量的长期分类 | EfficientAT 或 YAMNet + 场景状态机 | 先约束计算量，再做阈值校准 |
| 已有较多精确场景标注 | AST 或 HTS-AT 微调 | Transformer 可学习复杂声学组合 |
| 需要事件发生时间 | DESED/DCASE 训练配方 + 帧级 SED + sed_scores_eval | 从数据、模型到指标都围绕边界 |
| 没有完整标签体系 | LAION-CLAP 做候选探索，再建立监督数据 | 用开放词汇辅助建类，不把零样本分数当最终事实 |
| 只收集到正常声音 | embedding 距离、One-Class 或重建误差 + DCASE 2024 Task 2 评测思路 | 能先发现偏离基线的片段 |
| 需要声音方向 | SELD 数据和多通道模型 | ASC/Tagging 单声道模型无法提供方向 |

## 13. 常见失败模式

### 13.1 把事件标签当场景

“车流”高分不等于“街道”；可能是车内、视频播放或靠近停车场。应同时观察事件组合、声学背景和时间连续性，或在目标场景标注上训练聚合模型。

### 13.2 随机切窗造成虚高分

同一段长声音的重叠窗口若分别出现在训练和测试集，模型只需记住背景纹理即可得高分。必须先按地点、会话或原始声音文件切分，再做窗口化。

### 13.3 一个阈值打天下

每个标签的基线分数、样本比例和误报成本不同。应在独立验证集上为每类选择 T_on、T_off、最短时长和短间隙，而不是统一设为 0.5。

### 13.4 忽略 unknown

封闭集分类器总会选出最高类。若没有 unknown 机制，未知声源会被伪装成已知标签。必须以低分、低差距、距离或质量规则拦截不可靠结果。

### 13.5 使用无时间信息的分类结果充当 SED

给 10 秒声音打上“有警报”标签，只说明这 10 秒内可能存在警报，不能说明它从第几秒发生。需要时间答案时，训练帧级输出、保留连续分数并做事件边界后处理。

### 13.6 将异常分数解释为异常类别

异常检测可说明“偏离正常”，不能说明“具体是什么”。若需要原因分类，应收集该类异常的标注样本，或引入独立的开放集候选与人工复核流程。

## 14. 关键结论段落

声音场景识别关注的是“所处环境是什么、当前有哪些声音、某个声音何时发生”。主场景、并发事件和事件边界是三种不同输出，应该分别训练、评测和解释。

事件标签和场景标签不能混为一谈。车辆、音乐和人声是证据，不是必然的环境结论；要得到办公室、街道或车内等主场景，必须结合多事件共现、持续时间、声学背景或目标场景数据训练。

连续声音的可靠结果来自“固定窗口 + 连续分数 + 平滑 + 双阈值滞回 + 最短时长 + 短间隙合并”。单个窗口的最高分只能算候选，不能直接视为稳定结论。

模型分数是排序依据，不天然等于真实概率。只有在独立验证集上完成校准，并按实际环境选择类别阈值后，才应将它用于自动判断；低分、混合场景和未覆盖类别应保留为 unknown 或待确认。

异常声音检测的含义是“与正常基线不同”，不是“已经知道发生了何种异常”。它适合发现值得进一步检查的片段，具体原因仍需要有标签的分类器、额外证据或人工分析。

## 15. 参考资料

### 模型和项目

- [YAMNet](https://github.com/tensorflow/models/tree/master/research/audioset/yamnet)
- [PANNs](https://github.com/qiuqiangkong/audioset_tagging_cnn)
- [EfficientAT](https://github.com/fschmid56/EfficientAT)
- [AST](https://github.com/YuanGongND/ast)
- [HTS-AT](https://github.com/RetroCirce/HTS-Audio-Transformer)
- [BEATs](https://github.com/microsoft/unilm/tree/master/beats)
- [LAION-CLAP](https://github.com/LAION-AI/CLAP)
- [Microsoft CLAP](https://github.com/microsoft/CLAP)
- [AudioMAE](https://github.com/facebookresearch/AudioMAE)
- [PaSST](https://github.com/kkoutini/PaSST)
- [DCASE Task 1 CP-Mobile 基线](https://github.com/CPJKU/dcase2024_task1_baseline)
- [sed_scores_eval](https://github.com/fgnt/sed_scores_eval)
- [torchaudio](https://github.com/pytorch/audio)
- [librosa](https://github.com/librosa/librosa)
- [ONNX Runtime](https://github.com/microsoft/onnxruntime)
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)

### 数据、任务和论文

- [AudioSet](https://research.google.com/audioset/)
- [DCASE Community](https://dcase.community/)
- [DESED](https://project.inria.fr/desed/)
- [PANNs 论文](https://arxiv.org/abs/1912.10211)
- [EfficientAT 论文](https://arxiv.org/abs/2211.04772)
- [AST 论文](https://arxiv.org/abs/2104.01778)
- [HTS-AT 论文](https://arxiv.org/abs/2202.00874)
- [BEATs 论文](https://arxiv.org/abs/2212.09058)
- [CLAP 论文](https://arxiv.org/abs/2211.06687)
- [sed_scores_eval 论文](https://arxiv.org/abs/2201.13148)
