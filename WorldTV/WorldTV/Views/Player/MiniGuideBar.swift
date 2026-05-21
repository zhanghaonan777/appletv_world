import SwiftUI

/// Bottom channel banner shown over the playing video. Left/right scrolls
/// through the current category and switches channel live; up expands to the
/// full guide; down (or 4s of inactivity) dismisses.
struct MiniGuideBar: View {
    let channels: [Channel]
    @Binding var selectedChannel: Channel
    var onExpand: () -> Void = {}
    var onDismiss: () -> Void = {}

    @FocusState private var focused: Bool
    @State private var hideTask: Task<Void, Never>?

    private var selectedIndex: Int {
        channels.firstIndex { $0.id == selectedChannel.id } ?? 0
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Scrim — video shows through the top, banner reads at the bottom.
            LinearGradient(
                colors: [.clear, .black.opacity(0.55), .black.opacity(0.92)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 460)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 18) {
                header
                channelRail
            }
            .padding(.horizontal, 52)
            .padding(.bottom, 52)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($focused)
        .onMoveCommand { direction in
            scheduleHide()
            // All four directions surf channels — keeps ↑/↓ consistent with the
            // player so a second ↑ never unexpectedly opens the full guide.
            switch direction {
            case .left, .up:     move(-1)
            case .right, .down:  move(1)
            @unknown default:    break
            }
        }
        .onExitCommand { onDismiss() }
        .onTapGesture { onExpand() }
        .onAppear {
            focused = true
            scheduleHide()
        }
        .onDisappear { hideTask?.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "tv.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.accentGradient)
            Text(selectedChannel.groupTitle)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Theme.textPrimary)
            Text("·")
                .foregroundColor(Theme.textSecondary)
            Text("\(selectedIndex + 1) / \(channels.count)")
                .font(.system(size: 20, weight: .medium))
                .monospacedDigit()
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
    }

    // MARK: - Channel Rail

    private var channelRail: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(channels, id: \.id) { channel in
                        chip(channel, isCurrent: channel.id == selectedChannel.id)
                            .id(channel.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 24)
            }
            .onAppear { proxy.scrollTo(selectedChannel.id, anchor: .center) }
            .onChange(of: selectedChannel.id) { _, id in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func chip(_ channel: Channel, isCurrent: Bool) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isCurrent ? Color.white.opacity(0.10) : Color.white.opacity(0.05))
                logo(channel)
            }
            .frame(width: 188, height: 108)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCurrent ? Theme.accent : Color.white.opacity(0.08),
                            lineWidth: isCurrent ? 3 : 1)
            )

            Text(channel.name)
                .font(.system(size: 19, weight: isCurrent ? .bold : .medium))
                .foregroundColor(isCurrent ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 188)
        }
        .scaleEffect(isCurrent ? 1.08 : 0.94)
        .shadow(color: isCurrent ? Theme.accent.opacity(0.5) : .clear,
                radius: isCurrent ? 22 : 0, y: 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isCurrent)
    }

    @ViewBuilder
    private func logo(_ channel: Channel) -> some View {
        if let urlString = channel.logoURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit).padding(16)
                } else {
                    initialsBadge(channel)
                }
            }
        } else {
            initialsBadge(channel)
        }
    }

    private func initialsBadge(_ channel: Channel) -> some View {
        Text(String(channel.name.prefix(2)).uppercased())
            .font(.system(size: 30, weight: .bold))
            .foregroundColor(Theme.textPrimary)
    }

    // MARK: - Behavior

    private func move(_ delta: Int) {
        guard !channels.isEmpty else { return }
        let count = channels.count
        let newIndex = (selectedIndex + delta + count) % count
        selectedChannel = channels[newIndex]
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { onDismiss() }
        }
    }
}
