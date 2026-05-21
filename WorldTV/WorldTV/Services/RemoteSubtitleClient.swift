import Foundation

/// Streams 16kHz mono Float32 PCM to the Mac subtitle server over a WebSocket
/// and receives subtitle text back. All AI runs on the Mac; the Apple TV only
/// ships audio and displays the result.
final class RemoteSubtitleClient {

    struct Subtitle {
        let original: String
        let translated: String
    }

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var onSubtitle: ((Subtitle) -> Void)?
    private var onStatus: ((String) -> Void)?
    private(set) var isConnected = false

    func connect(to url: URL,
                 onSubtitle: @escaping (Subtitle) -> Void,
                 onStatus: @escaping (String) -> Void) {
        disconnect()
        self.onSubtitle = onSubtitle
        self.onStatus = onStatus

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        isConnected = true
        task.resume()
        receiveLoop()
        onStatus("已连接 \(url.host ?? "")")
    }

    func disconnect() {
        isConnected = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        onSubtitle = nil
        onStatus = nil
    }

    /// Send a chunk of 16kHz mono Float32 PCM.
    func send(_ pcm: [Float]) {
        guard let task, isConnected, !pcm.isEmpty else { return }
        let data = pcm.withUnsafeBytes { raw in
            Data(bytes: raw.baseAddress!, count: raw.count)
        }
        task.send(.data(data)) { [weak self] error in
            if let error {
                self?.onStatus?("发送失败: \(error.localizedDescription)")
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.handleText(text)
                }
                self.receiveLoop()
            case .failure(let error):
                self.isConnected = false
                self.onStatus?("连接断开: \(error.localizedDescription)")
            }
        }
    }

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        onSubtitle?(Subtitle(
            original: json["original"] as? String ?? "",
            translated: json["translated"] as? String ?? ""
        ))
    }
}
