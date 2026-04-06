import SwiftUI

struct ChannelCardView: View {
    let channel: Channel
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(spacing: 14) {
            // Logo area
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.muted)
                        .frame(height: 130)

                    if let logoURLString = channel.logoURL,
                       let logoURL = URL(string: logoURLString) {
                        AsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 80)
                            case .failure:
                                initialsView
                            case .empty:
                                ProgressView()
                                    .tint(Theme.textSecondary)
                            @unknown default:
                                initialsView
                            }
                        }
                    } else {
                        initialsView
                    }
                }

                // Live indicator - static green dot (no animation to avoid layout thrashing)
                Circle()
                    .fill(Theme.success)
                    .frame(width: 8, height: 8)
                    .shadow(color: Theme.success.opacity(0.6), radius: 3)
                    .padding(10)
            }

            // Channel info
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(channel.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)

                    Text(channel.groupTitle)
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if channel.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(isFocused ? Theme.cardHover : Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .stroke(isFocused ? Theme.accent.opacity(0.6) : Theme.border.opacity(0.3), lineWidth: isFocused ? 2 : 1)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .shadow(color: isFocused ? Theme.accent.opacity(0.3) : Color.clear, radius: 15)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }

    private var initialsView: some View {
        let initials = String(channel.name.prefix(2)).uppercased()
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.secondary, Theme.accent.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)

            Text(initials)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(Theme.textPrimary)
        }
    }
}
