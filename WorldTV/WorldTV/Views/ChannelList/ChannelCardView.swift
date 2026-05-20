import SwiftUI

struct ChannelCardView: View {
    let channel: Channel
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(spacing: 14) {
            // Logo plate
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isFocused ? Color.white.opacity(0.08) : Theme.muted)
                        .frame(height: 140)

                    logoContent
                }

                // Live indicator
                Circle()
                    .fill(Theme.success)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 2))
                    .shadow(color: Theme.success.opacity(0.9), radius: isFocused ? 6 : 3)
                    .padding(12)
            }

            // Channel info
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(channel.name)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)

                    Text(channel.groupTitle)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isFocused ? Theme.accentBright : Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if channel.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.accentBright)
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
                .stroke(isFocused ? Theme.accent : Color.white.opacity(0.06),
                        lineWidth: isFocused ? 3 : 1)
        )
        .scaleEffect(isFocused ? 1.10 : 1.0)
        .shadow(color: isFocused ? Theme.accent.opacity(0.55) : .clear,
                radius: isFocused ? 28 : 0, y: isFocused ? 12 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isFocused)
    }

    @ViewBuilder
    private var logoContent: some View {
        if let logoURLString = channel.logoURL,
           let logoURL = URL(string: logoURLString) {
            AsyncImage(url: logoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 88)
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

    private var initialsView: some View {
        let initials = String(channel.name.prefix(2)).uppercased()
        return ZStack {
            Circle()
                .fill(Theme.accentGradient)
                .frame(width: 72, height: 72)

            Text(initials)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
        }
    }
}
