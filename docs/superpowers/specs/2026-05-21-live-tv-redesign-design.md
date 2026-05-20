# WorldTV 重新设计 —— 直播优先的 tvOS IPTV 播放器

日期:2026-05-21
状态:设计已确认,待 review

## 背景与目标

WorldTV 当前是一个 tvOS IPTV 播放器,叠加了一套实时 AI 字幕(Whisper 语音识别 + Qwen 翻译)。
现阶段决定**关停 AI 字幕、专注把电视 app 的 UI 与交互做好**,并**重新梳理导航与布局**:
从"网格浏览 + 推栈播放"改为**直播优先、像真电视**的交互模型。

AI 字幕代码不删除,用开关保留为关闭状态,以后可随时启用。

## 设计决策(已与用户确认)

1. AI 字幕管线整体关停 —— 现阶段是纯 IPTV 播放器。
2. 重新梳理导航与布局,不局限于现有结构。
3. 核心体验:直播优先,像真电视 / 机顶盒。
4. 播放器:自定义 `AVPlayerLayer` 极简播放器,无进度条 / 传输栏。
5. 频道指南:两层 —— 底部迷你条 + 全屏网格。
6. 首次启动(无上次频道):先开全屏网格选频道。
7. AI 字幕:保留全部代码,用 `@AppStorage("aiSubtitlesEnabled")` 开关控制,默认 `false`。

## 导航模型

不再使用 `TabView`。app 是一个由 `RootView` 持有的状态机:

```
首次启动(无上次频道) ──→ [全屏网格指南] ──选频道──→ [播放]
再次启动(有上次频道) ──────────────────────────→ [播放]

[播放] 全屏自定义播放器(无进度条 / 传输栏)
  ├─ 叠加层 1:迷你条(底部横条)
  └─ 叠加层 2:全屏网格指南 ──→ 子页:[设置]
```

- **播放**是 app 的主屏。
- **迷你条**与**全屏网格指南**是播放屏上的叠加层。
- **设置**是从全屏网格指南进入的子页。
- "上次频道"由 `Channel.lastWatched` 最新的一条决定。

## 遥控器交互

| 状态 | 按键 | 行为 |
|---|---|---|
| **播放(无叠加)** | ↑ / ↓ | 切上 / 下一频道(当前分类内),弹出迷你条横幅 |
| | 点按 / ← / → | 弹出迷你条 |
| | 菜单(Menu) | 退出确认 |
| | 播放暂停 | 暂停 / 恢复(恢复跳回直播边缘) |
| **迷你条** | ← / → | 在当前分类频道间移动并即时切台预览 |
| | ↑ | 展开为全屏网格指南 |
| | ↓ / 菜单 | 收起迷你条 |
| | 点按 | 确认当前选中(已在播),收起 |
| | 4 秒无操作 | 自动收起 |
| **全屏网格指南** | 标准焦点导航 | 分类侧栏 + 频道卡网格 + 搜索框 + 设置入口(齿轮) |
| | 点按频道卡 | 切台并回到播放 |
| | 菜单 | 收起,回到播放 |
| **设置** | 标准焦点导航 | 播放列表管理 + 关于 |
| | 菜单 | 返回全屏网格指南 |

遥控按键在自定义播放器里通过 SwiftUI 的 `.onMoveCommand` / `.onExitCommand` /
`.onPlayPauseCommand`(必要时退回 UIKit `pressesBegan`)处理。自定义播放器不使用
`AVPlayerViewController`,因此不再有系统手势与自定义手势冲突的问题。

## 组件与文件

### 新建 / 重写

- **`RootView`**(替代 `ContentView`)—— app 状态机。启动时按有无 `lastWatched`
  决定初始进全屏网格还是直接进播放;持有"当前频道""当前分类""叠加层状态"。
- **`LivePlayerView`**(重写 `PlayerView`)—— `UIViewRepresentable` 包 `AVPlayerLayer`
  的全屏播放器;处理遥控按键;宿主迷你条与网格指南两个叠加层;含 loading / 错误态
  ("频道无法播放,可继续切台");按 `aiSubtitlesEnabled` 开关决定是否挂载字幕。
- **`MiniGuideBar`**(新)—— 底部快速切台横条,展示当前频道横幅 + 当前分类内相邻频道。
- **`ChannelGuideView`**(由 `ChannelListView` 重构)—— 全屏网格指南:分类侧栏 +
  频道卡网格 + 搜索 + 设置入口。从"独立 tab 页"变为"播放屏上的叠加层 / 首屏选择器"。

### 精简

- **`SettingsView`** —— 删除「翻译模型」(假数据 SMaLL-100)、「AI 功能 即将推出」
  两块;「字幕与翻译」整块精简为单个真实开关:「实时 AI 字幕」`Toggle`,绑定
  `@AppStorage("aiSubtitlesEnabled")`,默认关。保留「播放列表管理」与「关于」。

### 保留不动

- `Channel` / `Playlist` SwiftData 模型、`PlaylistManager`、`M3UParser`、`Theme`、`ChannelCardView`。

### AI 字幕(保留,开关关闭)

- 保留并继续编译:`SubtitleEngine`、`AudioExtractor`、`WhisperService`、
  `TranslationService`、`WhisperDiagnostic`、`SubtitleOverlayView`、`SubtitleDisplayMode`。
- 保留 SPM 依赖 SwiftWhisper、LlamaSwift。
- `@AppStorage("aiSubtitlesEnabled")` 默认 `false` 为唯一真源。
  - `false`(现状):`LivePlayerView` 不创建 `SubtitleEngine`、不加载模型、不显示字幕叠加层。
  - `true`:自定义播放器把 `SubtitleEngine` 挂到自身 `AVPlayer`(`AudioExtractor` 的
    `MTAudioProcessingTap` 对任意 `AVPlayer` 适用),显示 `SubtitleOverlayView`。
- 删除:`SystemPlayerView`(被自定义播放器取代);AI 字幕相关测试按需调整以保持可编译。

### 不在本次范围

- 模型文件(~570MB)是否入 git / 接 Git LFS —— 独立问题,本次不动。
- EPG 节目单、画中画、多语言 UI。

## 数据流

- `RootView` 持有 `currentChannel`、`currentCategory`、`overlayState`(none / miniBar / fullGuide / settings)。
- 切台 = `LivePlayerView` 内 `AVPlayer.replaceCurrentItem`,并写回 `Channel.lastWatched`。
- 频道数据仍来自 SwiftData `@Query [Playlist]`,经分类 / 搜索 / 收藏过滤;过滤逻辑从
  现 `ChannelListView` 迁移到可复用的位置(供网格指南与迷你条共用"当前分类频道序列")。

## 错误与边界处理

- 频道流加载失败 / 超时:播放器显示"频道无法播放"提示,用户可继续 ↑/↓ 切台。
- 无任何播放列表 / 无频道:进入全屏网格指南并显示空态"请前往设置添加播放列表"。
- 切台时旧的 `AVPlayerItem` 正确释放,避免多路流同时下载。

## 测试

- 频道过滤 / 排序逻辑(分类、搜索、收藏、最近)纯函数化后做单元测试。
- "当前分类频道序列 + 上/下切台"的环绕逻辑做单元测试。
- 播放器与叠加层的遥控交互在 tvOS 模拟器手动验证(模拟器对自定义手势支持有限,
  最终手感需真机确认)。
- AI 字幕开关关闭路径:验证 `LivePlayerView` 在 `false` 下不实例化 `SubtitleEngine`。

## 风险

- 自定义 `AVPlayerLayer` 播放器需自建 loading / 错误 / 缓冲态,工作量比系统播放器大。
- tvOS 遥控交互的真实手感(切台节奏、迷你条弹出/收起、焦点流转)需真机迭代。
- IPTV 直播源质量参差,切台到死源时要快速给反馈而不是无限转圈。
