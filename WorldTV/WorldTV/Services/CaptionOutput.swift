import Foundation
import AVFoundation

/// Renders a channel's own broadcast closed-caption / subtitle track.
///
/// The custom `AVPlayerLayer` player does not draw captions itself, so this
/// pulls the cues via `AVPlayerItemLegibleOutput`. It also auto-selects the
/// channel's legible track, so captions appear automatically whenever the
/// channel carries them — no toggle needed.
final class CaptionOutput: NSObject, ObservableObject, AVPlayerItemLegibleOutputPushDelegate {

    /// Current caption text (empty when nothing is showing).
    @Published var text: String = ""

    private var legibleOutput: AVPlayerItemLegibleOutput?
    private weak var attachedItem: AVPlayerItem?
    private var selectionTask: Task<Void, Never>?

    /// Start delivering captions for `item`. Safe to call on every channel change.
    func attach(to item: AVPlayerItem) {
        detach()
        let output = AVPlayerItemLegibleOutput()
        output.suppressesPlayerRendering = true
        output.setDelegate(self, queue: .main)
        item.add(output)
        legibleOutput = output
        attachedItem = item
        autoEnableCaptions(on: item)
    }

    func detach() {
        selectionTask?.cancel()
        selectionTask = nil
        if let output = legibleOutput, let item = attachedItem {
            item.remove(output)
        }
        legibleOutput = nil
        attachedItem = nil
        text = ""
    }

    /// Auto-select the channel's CC / subtitle track if it has one. HLS exposes
    /// the legible selection group only after playback starts, so retry briefly.
    private func autoEnableCaptions(on item: AVPlayerItem) {
        selectionTask = Task {
            for _ in 0..<20 {
                if Task.isCancelled { return }
                if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible),
                   let option = group.defaultOption ?? group.options.first {
                    item.select(option, in: group)
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
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
