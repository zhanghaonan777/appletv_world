import SwiftUI

/// Bottom channel banner over the playing video — a compact two-row guide:
/// top row switches category, bottom row switches channel. A dumb view: it
/// renders from `appModel` and forwards every remote button to it.
struct MiniGuideBar: View {
    let appModel: AppModel
    let channels: [Channel]

    @State private var hideTask: Task<Void, Never>?

    private var categories: [String] {
        ChannelBrowser.categories(from: channels)
    }

    private var rowChannels: [Channel] {
        ChannelBrowser.filter(channels, category: appModel.currentCategory)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.55), .black.opacity(0.94)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 540)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                categoryRow
                    .opacity(appModel.miniRow == .categories ? 1 : 0.5)
                channelRow
                    .opacity(appModel.miniRow == .channels ? 1 : 0.55)
            }
            .padding(.horizontal, 52)
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .onMoveCommand { direction in
            scheduleHide()
            switch direction {
            case .up:            appModel.handle(.up, channels: channels)
            case .down:          appModel.handle(.down, channels: channels)
            case .left:          appModel.handle(.left, channels: channels)
            case .right:         appModel.handle(.right, channels: channels)
            @unknown default:    break
            }
        }
        .onExitCommand { appModel.handle(.menu, channels: channels) }
        .onTapGesture { appModel.handle(.select, channels: channels) }
        .onAppear { scheduleHide() }
        .onDisappear { hideTask?.cancel() }
    }

    // MARK: - Category Row

    private var categoryRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(categories, id: \.self) { category in
                        categoryChip(category)
                            .id(category)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .onAppear { proxy.scrollTo(appModel.currentCategory, anchor: .center) }
            .onChange(of: appModel.currentCategory) { _, value in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }

    private func categoryChip(_ category: String) -> some View {
        let isSelected = category == appModel.currentCategory
        let isActive = appModel.miniRow == .categories
        return Text(category)
            .font(.system(size: 21, weight: isSelected ? .bold : .medium))
            .foregroundColor(isSelected ? .white : Theme.textSecondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                Capsule().fill(isSelected
                    ? AnyShapeStyle(Theme.accentGradient)
                    : AnyShapeStyle(Color.white.opacity(0.07)))
            )
            .overlay(
                Capsule().stroke(isSelected && isActive ? Color.white.opacity(0.7) : .clear,
                                 lineWidth: 2)
            )
            .scaleEffect(isSelected && isActive ? 1.06 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isSelected)
    }

    // MARK: - Channel Row

    private var channelRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(rowChannels, id: \.id) { channel in
                        channelChip(channel, isCurrent: channel.id == appModel.currentChannel?.id)
                            .id(channel.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 22)
            }
            .onAppear {
                if let id = appModel.currentChannel?.id { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: appModel.currentChannel?.id) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    private func channelChip(_ channel: Channel, isCurrent: Bool) -> some View {
        let isActive = appModel.miniRow == .channels
        let highlighted = isCurrent && isActive
        return VStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(isCurrent ? Color.white.opacity(0.10) : Color.white.opacity(0.05))
                logo(channel)
            }
            .frame(width: 168, height: 96)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(isCurrent ? Theme.accent : Color.white.opacity(0.08),
                            lineWidth: isCurrent ? 3 : 1)
            )

            Text(channel.name)
                .font(.system(size: 18, weight: isCurrent ? .bold : .medium))
                .foregroundColor(isCurrent ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 168)
        }
        .scaleEffect(highlighted ? 1.09 : (isCurrent ? 1.0 : 0.94))
        .shadow(color: highlighted ? Theme.accent.opacity(0.5) : .clear,
                radius: highlighted ? 22 : 0, y: 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: highlighted)
    }

    @ViewBuilder
    private func logo(_ channel: Channel) -> some View {
        if let urlString = channel.logoURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit).padding(14)
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
            .font(.system(size: 28, weight: .bold))
            .foregroundColor(Theme.textPrimary)
    }

    // MARK: - Auto-hide

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { appModel.handle(.menu, channels: channels) }
        }
    }
}
