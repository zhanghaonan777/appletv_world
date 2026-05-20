import SwiftUI

// MARK: - Subtitle Overlay

struct SubtitleOverlayView: View {
    @ObservedObject var engine: SubtitleEngine

    var body: some View {
        VStack {
            #if DEBUG
            // Pipeline status indicator (debug builds only)
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.pink)
                Text(engine.pipelineStatus)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.pink.opacity(0.6))
            .cornerRadius(20)
            .padding(.top, 40)
            #endif

            Spacer()

            if engine.displayMode != .off, hasText {
                VStack(spacing: 6) {
                    if showOriginal, !engine.currentOriginalText.isEmpty {
                        Text(engine.currentOriginalText)
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    if showTranslation, !engine.currentTranslatedText.isEmpty {
                        Text(engine.currentTranslatedText)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    Color(red: 236/255, green: 72/255, blue: 153/255)
                        .opacity(0.55)
                )
                .cornerRadius(Theme.cornerRadius)
                .padding(.bottom, 120)
            }
        }
        .allowsHitTesting(false)
    }

    private var showOriginal: Bool {
        engine.displayMode == .originalOnly || engine.displayMode == .both
    }

    private var showTranslation: Bool {
        engine.displayMode == .translationOnly || engine.displayMode == .both
    }

    private var hasText: Bool {
        !engine.currentOriginalText.isEmpty || !engine.currentTranslatedText.isEmpty
    }
}
