# WorldTV — Apple TV 全球 IPTV 播放器设计文档

## 1. 项目概述

WorldTV 是一款 tvOS 原生应用，用于播放 IPTV 流媒体（M3U/M3U8 格式），并集成实时语音识别和字幕翻译功能。核心差异化特性：用户可以用任何语言观看任何频道，系统自动生成并翻译字幕。所有处理均在设备本地运行，无云端依赖。

**目标硬件**：Apple TV 4K 2021（A12 Bionic 芯片，3GB 内存）及更新版本
**平台要求**：tvOS 26+

## 2. 核心功能

### 2.1 IPTV 播放器

- **M3U/M3U8 播放列表加载**：支持从 URL 或本地文件加载播放列表
- **频道列表管理**：基于 group-title 标签进行分类（按地区/内容类型）
- **频道搜索与收藏**：快速查找频道、标记收藏、查看最近观看历史
- **EPG 电子节目指南支持**：支持 XMLTV 格式，显示节目时间表和描述
- **多流协议支持**：HLS、HTTP、RTMP 流传输协议
- **频道元数据显示**：支持显示频道 Logo（tvg-logo 标签）、频道名称、描述
- **多播放列表管理**：支持同时管理多个 M3U 播放列表源，自动周期性刷新

### 2.2 实时字幕翻译

- **实时语音识别**：使用 tvOS 26 SpeechAnalyzer 框架的流式识别模式，实时捕获音频并转换为文本
- **本地离线翻译**：采用 SMaLL-100 多语言翻译模型，以 CoreML 格式加载，INT8 量化压缩至约 300MB
- **支持语言范围**：覆盖 100+ 种语言的识别和翻译
- **字幕显示模式**：
  - 仅显示翻译文本
  - 原始文本 + 翻译文本并排显示
  - 仅显示原始识别文本
  - 关闭字幕
- **字幕样式定制**：字体大小、背景透明度、显示位置（屏幕上方/下方）均可自定义
- **自动语言检测**：系统自动检测源语言，或允许用户手动指定源语言
- **灵活开关**：用户可随时启用或禁用字幕翻译功能

### 2.3 预留 AI 入口

- **插件化架构设计**：应用架构采用模块化、插件化设计，为未来 AI 功能扩展预留接口
- **UI 预留空间**：在应用界面中预留专属区域用于 AI 助手入口点
- **协议级接口**：定义 AIPluginProtocol，允许第三方或未来功能通过标准接口集成
- **未来扩展能力**：为声纹识别、频道推荐、个性化内容索引等 AI 功能预留开发空间

## 3. 技术架构

### 3.1 整体架构图

```
┌─────────────────────────────────────────────────┐
│                    WorldTV App                    │
├─────────────┬──────────────┬────────────────────┤
│  频道管理层   │   播放器层    │    字幕翻译层       │
│             │              │                    │
│ PlaylistMgr │ StreamPlayer │ SubtitleEngine     │
│ ChannelStore│ AudioExtract │ SpeechService      │
│ FavoriteMgr │ VideoRender  │ TranslationService │
│ EPGService  │              │ SubtitleRenderer   │
├─────────────┴──────────────┴────────────────────┤
│                  基础服务层                        │
│  NetworkService | StorageService | SettingsService│
│  AIPluginProtocol (预留)                          │
└─────────────────────────────────────────────────┘
```

### 3.2 播放器架构

**设计原则**：不使用 AVPlayer 的 HLS 自动播放，因为 AVPlayer 不允许直接访问音频 PCM 数据用于语音识别。

**选定方案**：自定义 HLS 管道 + 平行音频提取路径

**播放流程**：

1. **HLS 清单解析**
   - 使用 URLSession 下载 .m3u8 清单文件
   - 解析清单获取分段列表、比特率和时间戳信息

2. **分段顺序下载**
   - 按顺序下载 .ts 传输流分段
   - 实现缓冲管理和断点续传

3. **分段处理**
   - 使用 AVAssetReader 对每个 .ts 分段进行 demux 解封装
   - 分离视频轨道和音频轨道

4. **视频渲染**
   - 通过 AVSampleBufferDisplayLayer 实现硬件加速视频解码和显示
   - 支持适应性码率调整（ABR）

5. **音频处理与识别**
   - 使用 AVAudioEngine 将音频 PCM 数据解码
   - 通过 AudioUnit 进行回放输出
   - **同步**：将相同的 PCM 缓冲区同时传送至 SpeechAnalyzer 进行实时语音识别
   - 此设计确保播放和语音识别使用完全相同的音源，避免时序偏差

**备选方案**（快速原型）：
- 初期采用 AVPlayer 实现基础播放功能
- 同时独立启动第二个下载和解码路径，对同一个 HLS 流进行音频提取
- 将提取的 PCM 数据送给 SpeechAnalyzer
- 虽然浪费带宽和 CPU，但实现复杂度较低，便于快速验证

### 3.3 频道管理架构

**M3U 解析模块**
- 解析 #EXTM3U 头标签
- 提取 #EXTINF 扩展信息标签中的：
  - tvg-id：频道唯一标识符
  - tvg-name：频道名称
  - tvg-logo：频道 Logo URL
  - group-title：分组标题（用于分类）
  - duration：时长信息
- 支持注释和属性的灵活解析

**频道数据持久化**
- ChannelStore：基于 SwiftData 框架的本地数据库
- 存储内容：频道列表、用户收藏、观看历史、最后观看时间和位置
- 支持快速查询、全文搜索

**播放列表管理**
- PlaylistManager：管理多个 M3U 播放列表源
- 功能：
  - 添加、删除、编辑播放列表源 URL
  - 周期性自动刷新（可配置周期）
  - 增量更新：仅下载变化部分
  - 版本控制和冲突处理

**EPG 电子节目指南服务**
- EPGService：解析 XMLTV 格式的节目数据
- 匹配策略：通过 tvg-id 关联频道和节目信息
- 缓存管理：使用 SQLite 缓存已解析的 EPG 数据，减少网络请求
- 功能：
  - 显示当前和即将播出节目
  - 节目详情查看（标题、描述、时间）
  - 设定提醒

### 3.4 内存预算分析（A12 处理器，3GB 内存）

| 组件 | 估计内存占用 | 说明 |
|------|-----------|------|
| tvOS + 应用基线 | ~800MB | 操作系统和应用框架 |
| 视频解码 + 显示 | ~500MB | AVSampleBufferDisplayLayer 缓冲区 |
| SpeechAnalyzer 框架 | ~300-500MB | 语音识别模型和缓冲区 |
| SMaLL-100 CoreML 模型 | ~300MB | INT8 量化后的多语言翻译模型 |
| 频道数据 + EPG 缓存 | ~50MB | SwiftData 数据库和临时缓存 |
| 缓冲区预留空间 | ~550-1050MB | 流式处理缓冲、临时对象、系统调度 |
| **总计** | **~2.0-2.15GB / 3GB** | 剩余 ~800MB-1GB 安全余量 |

**内存优化策略**：
- 使用低精度量化模型（INT8）减少模型体积
- 实现流式处理，避免一次性加载整个视频到内存
- 定期释放过期缓存和临时对象
- 监测内存使用，自动降级非关键功能（如 EPG 详情缓存）

## 4. 字幕翻译引擎设计

### 4.1 语音识别 — SpeechAnalyzer

- 使用 tvOS 26 SpeechAnalyzer 框架（SpeechTranscriber）
- 流式模式：持续输入 PCM 音频缓冲区，实时获取部分识别结果
- 通过 SpeechAnalyzer 内置能力实现自动语言检测
- Fallback：用户手动选择源语言
- 延迟目标：部分结果 200-500ms
- 处理：背景噪音、多人说话、音乐干扰
- 优雅降级：识别失败时不显示字幕，不影响播放（不会崩溃）

### 4.2 翻译模型 — SMaLL-100

- 模型：SMaLL-100（HuggingFace: alirezamsh/small100）
- 参数量：300M
- 量化方案：通过 CoreML Tools 进行 INT8 量化（磁盘占用约 300MB）
- 语言支持：100 种语言，10,000+ 翻译语言对
- 架构：Encoder-decoder transformer
- CoreML 转换流程：PyTorch → ONNX → CoreML (.mlpackage)
- ANE 优化：将 nn.Linear 转换为 nn.Conv2d，使用 4D channels-first 张量以利用 Apple Neural Engine 加速
- 推理延迟目标：A12 上每句 <500ms
- 模型加载：首次翻译请求时 lazy load，字幕功能活跃期间保持在内存中
- 模型下载：内置常用语言对，其他按需下载
- Fallback：模型加载失败或 OOM 时，优雅关闭翻译功能

### 4.3 字幕处理管线

```
Audio PCM Buffer (来自播放器)
    ↓ (持续音频流)
SpeechTranscriber (流式模式)
    ↓ (部分文本结果, ~200-500ms 延迟)
句子边界检测
    ↓ (累积至自然句子断点)
SMaLL-100 CoreML Model
    ↓ (翻译句子, <500ms)
Subtitle Renderer
    ↓ (叠加到视频上方, 带动画效果)
显示
```

总管线延迟：从说话到翻译字幕显示约 1-2 秒。

### 4.4 字幕渲染

- SwiftUI overlay 叠加在视频层上方
- 双行模式：原文（较小字体，上方）+ 翻译文本（较大字体，下方）
- 平滑淡入/淡出动画
- 可定制：字体大小（小/中/大）、背景透明度（0-100%）、位置（上/中/下）
- 5 秒无新文本后自动隐藏
- 支持 RTL 语言（阿拉伯语、希伯来语）

## 5. 用户界面设计

### 5.1 主界面 — 频道列表

```
┌──────────────────────────────────────────────┐
│  WorldTV                          🔍 ⚙️      │
├──────────┬───────────────────────────────────┤
│ 全部频道  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐│
│ ⭐ 收藏   │  │CCTV1│ │CCTV2│ │CCTV3│ │CCTV4││
│ 🕐 最近   │  │     │ │     │ │     │ │     ││
│ ────────  │  └─────┘ └─────┘ └─────┘ └─────┘│
│ 央视      │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐│
│ 卫视      │  │CNN  │ │BBC  │ │NHK  │ │KBS  ││
│ 港澳台    │  │     │ │     │ │     │ │     ││
│ 美国      │  └─────┘ └─────┘ └─────┘ └─────┘│
│ 英国      │                                   │
│ 日本      │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐│
│ 韩国      │  │ABC  │ │FOX  │ │ESPN │ │Sky  ││
│ 体育      │  │     │ │     │ │     │ │     ││
│ 新闻      │  └─────┘ └─────┘ └─────┘ └─────┘│
│ ...       │                                   │
└──────────┴───────────────────────────────────┘
```

- 左侧边栏：基于 M3U group-title 的频道分组
- 主区域：频道网格，显示 Logo（tvg-logo）
- 焦点导航（Apple TV 遥控器）
- 顶部搜索栏快速搜索
- 设置齿轮图标

### 5.2 播放界面

```
┌──────────────────────────────────────────────┐
│                                              │
│              VIDEO PLAYBACK                  │
│                                              │
│                                              │
│                                              │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │ The president announced new policy   │    │
│  │ 总统宣布了新政策                       │    │
│  └──────────────────────────────────────┘    │
├──────────────────────────────────────────────┤
│ ◀ CNN News  │ 🔤 字幕:开 │ 🌐 英→中 │ ▶ next │
└──────────────────────────────────────────────┘
```

- 全屏视频播放，字幕叠加显示
- 底部栏（触摸遥控器时显示）：频道名、字幕开关、语言对、下一频道
- 遥控器上划：快捷设置（字幕样式、语言）
- 左右滑动：切换频道
- 按 Menu：返回频道列表

### 5.3 设置界面

- **播放列表管理**：添加/删除/刷新 M3U URL
- **字幕设置**：启用/禁用、源语言（自动/手动）、目标语言、显示模式、字体大小、透明度、位置
- **翻译模型管理**：查看已下载模型、下载新语言支持、模型大小信息
- **通用设置**：自动播放上次频道、EPG 源 URL、缓冲区大小
- **关于**：版本、致谢、开源许可
- **AI 功能（预留）**：灰色显示 "Coming Soon"

## 6. 数据模型

### 6.1 SwiftData 数据模型

```swift
@Model class Playlist {
    var id: UUID
    var name: String
    var url: String
    var lastRefresh: Date
    var channels: [Channel]
}

@Model class Channel {
    var id: String          // tvg-id
    var name: String        // 显示名称
    var logoURL: String?    // tvg-logo
    var groupTitle: String  // group-title
    var streamURL: String
    var isFavorite: Bool
    var lastWatched: Date?
    var playlist: Playlist
}

@Model class SubtitleSettings {
    var isEnabled: Bool
    var sourceLanguage: String     // "auto" 或 ISO 639-1 代码
    var targetLanguage: String     // ISO 639-1 代码，默认 "zh"
    var displayMode: DisplayMode   // .translationOnly, .dual, .originalOnly
    var fontSize: FontSize         // .small, .medium, .large
    var backgroundOpacity: Double  // 0.0 - 1.0
    var position: Position         // .top, .center, .bottom
}

enum DisplayMode: String, Codable {
    case translationOnly, dual, originalOnly
}
```

### 6.2 文件存储

| 项目 | 位置 | 大小 |
|------|------|------|
| SMaLL-100 CoreML 模型 | App bundle 或 Documents/ | ~300MB |
| M3U 播放列表缓存 | Documents/playlists/ | <1MB |
| EPG 缓存 | Caches/epg/ | <10MB |
| 频道 Logo 缓存 | Caches/logos/ | <50MB |
| 用户设置 | UserDefaults + SwiftData | <1MB |

## 7. 开发阶段规划

### Phase 1: 基础播放器 (MVP)

基础阶段专注于构建一个功能完整的 IPTV 播放器核心，无需复杂的语音和翻译功能。

**主要目标:**
- tvOS 项目初始化（Swift, SwiftUI, tvOS 26+）
- M3U/M3U8 解析器实现
- 频道列表 UI，支持 group-title 分类
- 使用 AVPlayer 的基础 HLS 播放
- 频道切换、收藏、搜索功能
- 频道 Logo 显示
- 播放列表 URL 管理的设置页面

**交付物:**
- 可运行的 tvOS 应用，支持导入 M3U 播放列表
- 基础频道管理和播放功能

### Phase 2: 自定义播放管线 + 音频提取

**主要目标:**
- 替换 AVPlayer 的自定义 HLS 管线，或实现并行音频提取
- 独立下载 HLS 分片段
- 使用 AVAssetReader 将音频解码为 PCM
- 将音频缓冲区馈送给 SpeechAnalyzer
- 显示基础的语音转文本字幕（暂不包含翻译）
- 字幕叠层 UI 与自定义选项

**交付物:**
- 功能性的音频提取管线
- 显示实时语音识别结果的字幕覆盖层

### Phase 3: 本地翻译

**主要目标:**
- 将 SMaLL-100 转换为 CoreML 格式（PyTorch → ONNX → CoreML）
- INT8 量化以支持 A12 处理器
- ANE 优化（Conv2d 转换, 4D 张量支持）
- 将翻译集成入字幕管线
- 语言选择 UI
- 双行字幕显示（原文 + 翻译）
- 多语言模型下载管理

**交付物:**
- 集成的翻译字幕系统
- 支持多种语言对的本地翻译功能

### Phase 4: 优化与完善

**主要目标:**
- 在 A12 上进行性能分析和内存优化
- EPG 支持（XMLTV 解析, 节目指南 UI）
- 优化流式语音识别（降低延迟）
- 字幕时序同步精细化
- 处理边界情况（音乐、静音、多人说话）
- 无障碍功能支持

### Phase 5: AI 入口（未来方向）

- AI 插件协议实现
- 语音助手集成
- 智能频道推荐
- 内容总结生成

## 8. 技术风险与缓解

### 8.1 SpeechAnalyzer 在 A12 上的性能

- **风险:** 可能在 A12 上无法流畅运行流式识别，或延迟过大
- **缓解:** 降低音频采样率至 16kHz；fallback 到分段识别（每 3-5 秒一段）；提供用户可调"识别质量"选项；最坏情况标记为 Beta

### 8.2 SMaLL-100 CoreML 转换

- **风险:** PyTorch → ONNX → CoreML 转换可能不完美，某些 op 不支持
- **缓解:** 提前验证转换流程；备选 Opus-MT Tiny（25MB/语言对）；CTranslate2 ARM64 CPU 推理作为 fallback

### 8.3 HLS 音频提取

- **风险:** 自定义 HLS 管线复杂度高，可能有兼容性问题
- **缓解:** Phase 1 先用 AVPlayer；先尝试并行下载方案；隔离设计确保播放功能不受影响

### 8.4 内存压力

- **风险:** 3GB RAM 同时跑视频+ASR+翻译可能触发 OOM
- **缓解:** 翻译模型 lazy load；监控内存水位自动关闭翻译；用户可手动关闭字幕；视频缓冲区大小可调

### 8.5 SpeechAnalyzer 硬件要求不明

- **风险:** Apple 文档未明确是否支持 A12
- **缓解:** 开发初期在真机上测试；备选 WhisperKit CoreML Tiny（约 75MB）

## 9. 技术验证优先级

在正式开发之前，必须先验证以下技术点（按优先级排序）：

| 优先级 | 验证项 | 成功标准 | 失败后备 |
|--------|--------|---------|---------|
| **最高** | SpeechAnalyzer 在 Apple TV 2021 上是否可用 | 延迟 ≤2s，准确率 ≥90% | 切换 WhisperKit CoreML |
| **高** | SMaLL-100 → CoreML 转换 | 转换成功，推理 ≤500ms/句 | 切换 Opus-MT Tiny |
| **高** | HLS 并行音频提取 | 音视频同步偏差 ≤100ms | 继续用 AVPlayer |
| **高** | 内存水位测试 | 峰值 ≤2.5GB，30分钟无 OOM | Lazy loading + 更激进量化 |
| **中** | 端到端延迟 | 总延迟 ≤2s | 优化参数或降级功能 |

```
验证 1 失败 → 切换 WhisperKit CoreML
验证 2 失败 → 切换 Opus-MT Tiny
验证 4 失败 → Lazy Loading + 更激进量化
所有验证通过 → 按原计划开发
```

---

**文档版本**: 1.0
**日期**: 2026-04-06
**适用平台**: tvOS 26+
**目标硬件**: Apple TV 4K 2021 (A12 Bionic, 3GB RAM) 及更新版本
