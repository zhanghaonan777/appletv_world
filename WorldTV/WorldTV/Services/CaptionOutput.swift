import Foundation
import AVFoundation

/// Pulls a channel's broadcast closed-caption / subtitle track via
/// `AVPlayerItemLegibleOutput` so the custom `AVPlayerLayer` player can render
/// captions itself.
///
/// AVPlayer only auto-selects a legible track when the viewer has tvOS system
/// captions enabled (Settings → Accessibility → Subtitles & Captioning), so
/// this stays silent unless the user has turned captions on — i.e. it reuses
/// Apple TV's own CC switch instead of adding a custom one.
final class CaptionOutput: NSObject, ObservableObject, AVPlayerItemLegibleOutputPushDelegate {

    /// Current caption text (empty when nothing is showing).
    @Published var text: String = ""

    private var legibleOutput: AVPlayerItemLegibleOutput?
    private weak var attachedItem: AVPlayerItem?

    /// Start delivering captions for `item`. Safe to call on every channel change.
    func attach(to item: AVPlayerItem) {
        detach()
        let output = AVPlayerItemLegibleOutput()
        output.suppressesPlayerRendering = true
        output.setDelegate(self, queue: .main)
        item.add(output)
        legibleOutput = output
        attachedItem = item
    }

    func detach() {
        if let output = legibleOutput, let item = attachedItem {
            item.remove(output)
        }
        legibleOutput = nil
        attachedItem = nil
        text = ""
    }

    /// Collapse a set of caption cues into one displayable string.
    static func joinCues(_ strings: [NSAttributedString]) -> String {
        strings
            .map { $0.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - AVPlayerItemLegibleOutputPushDelegate

    func legibleOutput(_ output: AVPlayerItemLegibleOutput,
                       didOutputAttributedStrings strings: [NSAttributedString],
                       nativeSampleBuffers nativeSamples: [Any],
                       forItemTime itemTime: CMTime) {
        text = CaptionOutput.joinCues(strings)
    }
}
