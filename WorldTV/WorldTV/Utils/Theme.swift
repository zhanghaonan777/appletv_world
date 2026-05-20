import SwiftUI

enum Theme {
    static let background = Color(hex: "#000000")
    static let card = Color(hex: "#0C0C0D")
    static let cardHover = Color(hex: "#1B1B30")
    static let primary = Color(hex: "#0F0F23")
    static let secondary = Color(hex: "#1E1B4B")
    static let accent = Color(hex: "#E11D48")
    static let accentBright = Color(hex: "#FB3B6A")
    static let textPrimary = Color(hex: "#F8FAFC")
    static let textSecondary = Color(hex: "#94A3B8")
    static let muted = Color(hex: "#181818")
    static let border = Color(hex: "#312E81")
    static let success = Color(hex: "#22C55E")
    static let destructive = Color(hex: "#EF4444")

    static let cornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 16

    /// Diagonal accent gradient used for selected states and the brand mark.
    static let accentGradient = LinearGradient(
        colors: [accentBright, accent],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Cinematic backdrop: a deep vertical gradient with a faint accent wash
    /// glowing from the top — gives the dark UI depth instead of flat black.
    static var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#14111F"), Color(hex: "#050507")],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [accent.opacity(0.20), .clear],
                center: UnitPoint(x: 0.5, y: -0.05),
                startRadius: 0, endRadius: 1000
            )
        }
        .ignoresSafeArea()
    }
}
