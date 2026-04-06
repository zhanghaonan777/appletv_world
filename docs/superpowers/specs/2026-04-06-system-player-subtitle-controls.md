# System Player Subtitle Controls

Replace custom menu overlay with native tvOS AVPlayerViewController controls.

## Changes

### 1. Replace VideoPlayer with AVPlayerViewController wrapper

Create `SystemPlayerView` using `UIViewControllerRepresentable` wrapping `AVPlayerViewController`. This gives us:
- Native transport bar with CC button
- Standard remote behavior (play/pause, menu = back, swipe to scrub)
- System-standard info overlay on touch

### 2. Subtitle options via CC button

Use `transportBarCustomMenuItems` to add a menu to the CC button area:
- Off (关闭字幕)
- Original only (仅原文)
- Translation only (仅翻译)  
- Original + Translation (原文+翻译) — default

SubtitleEngine gets a new `displayMode` enum to control which text is shown.

### 3. Subtitle overlay

Overlay a SwiftUI subtitle view on top of AVPlayerViewController's view. Same styling as current (black semi-transparent background, white/gray text). Visibility controlled by `displayMode`.

### 4. Remove custom menu

Delete: `menuOverlay`, `menuButton`, `menuInfoRow`, `showMenu` state, `@Namespace menuFocus`, Play/Pause menu toggle logic.

### 5. Channel switching

Swipe up/down on remote to switch channels. Brief channel name toast on switch.

## Files affected

- `PlayerView.swift` — major rewrite
- `SubtitleEngine.swift` — add `displayMode` enum

## Not changed

- SubtitleEngine pipeline (audio extraction, Whisper, translation)
- WhisperService, TranslationService, AudioExtractor
- Subtitle text styling
