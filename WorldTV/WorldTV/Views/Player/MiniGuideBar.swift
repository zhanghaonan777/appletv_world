import SwiftUI

/// Bottom quick-switch strip shown over the playing video. Left/right scrolls
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
        VStack {
            Spacer()
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(channels, id: \.id) { channel in
                            chip(channel, isCurrent: channel.id == selectedChannel.id)
                                .id(channel.id)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 18)
                }
                .onAppear { proxy.scrollTo(selectedChannel.id, anchor: .center) }
                .onChange(of: selectedChannel.id) { _, id in
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .background(.black.opacity(0.8))
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($focused)
        .onMoveCommand { direction in
            scheduleHide()
            switch direction {
            case .left:  move(-1)
            case .right: move(1)
            case .up:    onExpand()
            case .down:  onDismiss()
            @unknown default: break
            }
        }
        .onExitCommand { onDismiss() }
        .onAppear {
            focused = true
            scheduleHide()
        }
        .onDisappear { hideTask?.cancel() }
    }

    private func chip(_ channel: Channel, isCurrent: Bool) -> some View {
        VStack(spacing: 6) {
            Text(channel.name)
                .font(.callout)
                .fontWeight(isCurrent ? .bold : .regular)
                .foregroundColor(isCurrent ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
            Text(channel.groupTitle)
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 200)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(isCurrent ? Theme.accent.opacity(0.85) : Theme.card)
        )
    }

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
