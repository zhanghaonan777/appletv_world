# 直播优先重新设计 实现计划

> 设计见 `docs/superpowers/specs/2026-05-21-live-tv-redesign-design.md`。

**目标:** 把 WorldTV 从"网格+推栈"改为直播优先的纯 IPTV 播放器,AI 字幕用 `@AppStorage("aiSubtitlesEnabled")` 开关(默认 false)保留。

**架构:** 无 TabView;`RootView` 状态机持有 app 状态;自定义 `AVPlayerLayer` 播放器为主屏;迷你条 + 全屏网格为叠加层。

**约束:** 项目用显式文件引用(objectVersion 77,无同步组),每个新增 `.swift` 文件必须加入 `WorldTV.xcodeproj` 的 WorldTV target(PBXFileReference + PBXBuildFile + Sources build phase)。每个任务结束编译验证:`xcodebuild build -project WorldTV/WorldTV.xcodeproj -scheme WorldTV -destination 'generic/platform=tvOS Simulator' -derivedDataPath /tmp/worldtv_dd`。

---

## Task 1:抽出 SubtitleOverlayView

AI 字幕叠加层从 `PlayerView.swift` 移到独立文件,使后续删除 `PlayerView.swift` 不丢失它。

- 创建 `WorldTV/WorldTV/Views/Player/SubtitleOverlayView.swift`,把 `PlayerView.swift` 中的 `SubtitleOverlayView` 整段原样移入。
- 从 `PlayerView.swift` 删除该段。
- 新文件加入 target。
- 验证:编译通过。

## Task 2:精简 SettingsView

- 修改 `WorldTV/WorldTV/Views/Settings/SettingsView.swift`:
  - 删除「翻译模型」「AI 功能」两个 section。
  - 「字幕与翻译」section 精简为单个 `Toggle("实时 AI 字幕", isOn:)`,绑定 `@AppStorage("aiSubtitlesEnabled") var aiSubtitlesEnabled = false`。
  - 删除不再使用的 `@State`:`displayMode`、`subtitleSize`、`backgroundOpacity`、`realtimeSubtitlesEnabled`。
  - 保留「播放列表管理」「关于」。
- 验证:编译通过;模拟器设置 tab 正常。

## Task 3:ChannelBrowser 频道逻辑(TDD)

- 创建 `WorldTV/WorldTV/Services/ChannelBrowser.swift`:
  - `categories(from:)` — 分类列表(全部频道/收藏/最近 在前,再 raw groups)。
  - `channelCount(in:category:)`。
  - `channels(in:category:search:)` — 过滤+排序(收藏、最近按 lastWatched 倒序、按 groupTitle)。
  - `next(after:in:)` / `previous(before:in:)` — 按 `id` 定位,环绕。
- 创建 `WorldTV/WorldTVTests/ChannelBrowserTests.swift` — 覆盖过滤、计数、环绕切台、不在列表的边界。
- TDD:先写测试 → 跑失败 → 实现 → 跑通过。
- 两个新文件加入对应 target。
- 验证:`xcodebuild test ... -only-testing:WorldTVTests/ChannelBrowserTests`。

## Task 4:PlayerLayerView 自定义播放层

- 创建 `WorldTV/WorldTV/Views/Player/PlayerLayerView.swift`:`UIViewRepresentable` 包一个 `layerClass` 为 `AVPlayerLayer` 的 `UIView`,接受 `AVPlayer`。
- 加入 target。
- 验证:编译通过。

## Task 5:LivePlayerView 播放主屏

- 创建 `WorldTV/WorldTV/Views/Player/LivePlayerView.swift`:
  - `LivePlayerModel: ObservableObject` — 持 `AVPlayer`,KVO 观察 `AVPlayerItem.status`,`@Published state: .loading/.playing/.failed`,`play(_ channel:)`。
  - `LivePlayerView` — 宿主 `PlayerLayerView`;`.focusable()` + `.onMoveCommand` 处理 ↑/↓ 切台(回调上层)、`.onExitCommand` 菜单;loading/错误叠加;切台写 `Channel.lastWatched`。
  - 接受 `channel`、当前分类频道序列、切台回调。
  - AI 字幕:`@AppStorage("aiSubtitlesEnabled")`,为 true 时创建 `SubtitleEngine`、`start(player:)`、叠加 `SubtitleOverlayView`;false 时全部跳过。
- 加入 target。
- 验证:编译通过。

## Task 6:MiniGuideBar 迷你条

- 创建 `WorldTV/WorldTV/Views/Player/MiniGuideBar.swift`:底部横条,当前频道横幅 + 当前分类相邻频道;`.onMoveCommand` ←/→ 移动预览、↑ 请求展开全屏、↓ 收起;4 秒自动收起。
- 集成进 `LivePlayerView`(叠加层 1)。
- 加入 target。
- 验证:编译通过。

## Task 7:ChannelGuideView 全屏网格指南

- 创建 `WorldTV/WorldTV/Views/Guide/ChannelGuideView.swift`:由 `ChannelListView` 重构 —— 分类侧栏 + 频道卡网格 + 搜索 + 设置入口齿轮;过滤逻辑改用 `ChannelBrowser`;`PlaylistManagerHolder`、`CardButtonStyle` 一并移入此文件;`.onExitCommand` 菜单回到播放;选频道回调上层。
- 加入 target。
- 验证:编译通过。

## Task 8:RootView 组装 + 切换入口 + 清理

- 创建 `WorldTV/WorldTV/RootView.swift`:状态机 `overlayState`(none/miniBar/fullGuide/settings)、`currentChannel`、`currentCategory`;启动按有无 `lastWatched` 决定初始进网格还是播放;`@Query [Playlist]` 取数据,`ensureDefaultPlaylist`。
- 修改 `WorldTVApp.swift`:`ContentView()` → `RootView()`。
- 删除 `ContentView.swift`、`Views/Player/PlayerView.swift`(剩余 `SystemPlayerView`/`ChannelToastView`/`PlayerView`)、`Views/ChannelList/ChannelListView.swift`;从 pbxproj 移除这三个文件引用。
- RootView 加入 target。
- 验证:编译通过;模拟器跑完整流程 —— 首次进网格选频道 → 播放 → ↑↓ 切台 → 迷你条 → 展开全屏指南 → 设置 → 返回。

## Task 9:收尾

- 全量编译 + 测试 target 编译(AI 字幕相关测试如因 API 变动失败则修到可编译)。
- 模拟器回归一遍。
- 提交。
