import Foundation
import Observation

/// A directional or action button on the Apple TV remote.
enum RemoteButton {
    case up, down, left, right, select, menu
}

/// Which row of the two-row mini guide bar is active.
enum MiniRow: Equatable {
    case categories, channels
}

/// The app's current interaction surface (also drives which view is shown).
enum AppScreen: Equatable {
    case player
    case miniBar(MiniRow)
    case guide
    case settings
}

/// Coarse focus region — the root view drives a single `@FocusState` from this.
enum FocusZone: Hashable {
    case player, miniBar, guide, settings
}

/// The single source of truth for interaction state: which screen is showing,
/// the current channel/category, and how every remote button maps to a
/// transition. Pure logic with no view dependency — fully unit-testable.
@Observable
final class AppModel {
    var screen: AppScreen
    var currentChannel: Channel?
    var currentCategory: String

    init(screen: AppScreen = .guide,
         currentChannel: Channel? = nil,
         currentCategory: String = ChannelBrowser.allCategory) {
        self.screen = screen
        self.currentChannel = currentChannel
        self.currentCategory = currentCategory
    }

    /// The focus region for the current screen.
    var focusZone: FocusZone {
        switch screen {
        case .player:   return .player
        case .miniBar:  return .miniBar
        case .guide:    return .guide
        case .settings: return .settings
        }
    }

    /// The mini bar's active row (only meaningful while `screen` is `.miniBar`).
    var miniRow: MiniRow {
        if case .miniBar(let row) = screen { return row }
        return .channels
    }

    /// Video must pause while a fullscreen overlay hides it.
    var isVideoCovered: Bool {
        switch screen {
        case .guide, .settings: return true
        case .player, .miniBar: return false
        }
    }

    // MARK: - Bootstrap

    /// On launch: resume the last-watched channel, or stay on the guide so the
    /// user picks one.
    func bootstrap(channels: [Channel]) {
        let lastWatched = channels
            .filter { $0.lastWatched != nil }
            .max { ($0.lastWatched ?? .distantPast) < ($1.lastWatched ?? .distantPast) }
        if let lastWatched {
            currentChannel = lastWatched
            currentCategory = lastWatched.groupTitle
            screen = .player
        } else {
            screen = .guide
        }
    }

    // MARK: - Remote Input

    /// The single entry point for every remote button. `channels` is the full
    /// channel list (from SwiftData) needed to compute channel/category moves.
    func handle(_ button: RemoteButton, channels: [Channel]) {
        switch screen {
        case .player:           handlePlayer(button, channels: channels)
        case .miniBar(let row): handleMiniBar(button, row: row, channels: channels)
        case .guide:            handleGuide(button)
        case .settings:         handleSettings(button)
        }
    }

    /// A channel chosen from the full guide.
    func selectChannelFromGuide(_ channel: Channel) {
        currentChannel = channel
        currentCategory = channel.groupTitle
        screen = .player
    }

    func openSettings() {
        screen = .settings
    }

    // MARK: - Per-screen Handling

    private func handlePlayer(_ button: RemoteButton, channels: [Channel]) {
        switch button {
        case .up:    switchChannel(by: -1, channels: channels)
        case .down:  switchChannel(by: 1, channels: channels)
        case .left, .right, .select: screen = .miniBar(.channels)
        case .menu:  screen = .guide
        }
    }

    private func handleMiniBar(_ button: RemoteButton, row: MiniRow, channels: [Channel]) {
        switch button {
        case .select:
            screen = .guide
        case .menu:
            screen = .player
        case .up:
            screen = .miniBar(.categories)
        case .down:
            screen = .miniBar(.channels)
        case .left:
            if row == .categories { switchCategory(by: -1, channels: channels) }
            else { switchChannel(by: -1, channels: channels) }
        case .right:
            if row == .categories { switchCategory(by: 1, channels: channels) }
            else { switchChannel(by: 1, channels: channels) }
        }
    }

    private func handleGuide(_ button: RemoteButton) {
        // Directional + select inside the guide are handled natively by the
        // sidebar/grid focus engine; only Menu maps to a transition here.
        if button == .menu, currentChannel != nil {
            screen = .player
        }
    }

    private func handleSettings(_ button: RemoteButton) {
        if button == .menu { screen = .guide }
    }

    // MARK: - Navigation Helpers

    private func switchChannel(by delta: Int, channels: [Channel]) {
        guard let current = currentChannel else { return }
        let list = ChannelBrowser.filter(channels, category: currentCategory)
        let target = delta < 0
            ? ChannelBrowser.previous(before: current, in: list)
            : ChannelBrowser.next(after: current, in: list)
        if let target { currentChannel = target }
    }

    private func switchCategory(by delta: Int, channels: [Channel]) {
        let categories = ChannelBrowser.categories(from: channels)
        guard !categories.isEmpty,
              let index = categories.firstIndex(of: currentCategory) else { return }
        let newCategory = categories[(index + delta + categories.count) % categories.count]
        currentCategory = newCategory
        // Keep the player consistent: tune to the new category's first channel.
        if let first = ChannelBrowser.filter(channels, category: newCategory).first {
            currentChannel = first
        }
    }
}
