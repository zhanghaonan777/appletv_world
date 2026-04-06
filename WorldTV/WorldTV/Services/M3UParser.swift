import Foundation

struct M3UParserResult {
    let channels: [ParsedChannel]
    let epgURL: String?
}

struct ParsedChannel {
    let id: String
    let name: String
    let logoURL: String?
    let groupTitle: String
    let streamURL: String
}

final class M3UParser {

    // MARK: - Public

    /// Parse M3U content from a remote URL.
    static func parse(from url: URL) async throws -> M3UParserResult {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw M3UParserError.invalidEncoding
        }
        return parse(content: content)
    }

    /// Parse M3U content from a raw string.
    static func parse(content: String) -> M3UParserResult {
        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else {
            return M3UParserResult(channels: [], epgURL: nil)
        }

        var epgURL: String?
        var channels: [ParsedChannel] = []
        var currentExtInf: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Header line
            if trimmed.hasPrefix("#EXTM3U") {
                epgURL = extractAttribute(from: trimmed, key: "x-tvg-url")
                    ?? extractAttribute(from: trimmed, key: "url-tvg")
                continue
            }

            // EXTINF line
            if trimmed.hasPrefix("#EXTINF:") {
                currentExtInf = trimmed
                continue
            }

            // Skip other directives or empty lines
            if trimmed.hasPrefix("#") || trimmed.isEmpty {
                continue
            }

            // This should be a URL line following an #EXTINF
            guard let extInf = currentExtInf else {
                // URL without EXTINF - skip
                continue
            }

            if let channel = parseEntry(extInf: extInf, streamURL: trimmed) {
                channels.append(channel)
            }
            currentExtInf = nil
        }

        return M3UParserResult(channels: channels, epgURL: epgURL)
    }

    // MARK: - Private

    private static func parseEntry(extInf: String, streamURL: String) -> ParsedChannel? {
        // Validate stream URL minimally
        guard streamURL.hasPrefix("http://") || streamURL.hasPrefix("https://") || streamURL.hasPrefix("rtmp://") else {
            return nil
        }

        let tvgId = extractAttribute(from: extInf, key: "tvg-id") ?? ""
        let tvgName = extractAttribute(from: extInf, key: "tvg-name")
        let tvgLogo = extractAttribute(from: extInf, key: "tvg-logo")
        let groupTitle = extractAttribute(from: extInf, key: "group-title") ?? "Uncategorized"

        // Channel display name is after the last comma in the EXTINF line
        let displayName: String
        if let commaRange = extInf.range(of: ",", options: .backwards) {
            let afterComma = String(extInf[commaRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            displayName = afterComma.isEmpty ? (tvgName ?? "Unknown") : afterComma
        } else {
            displayName = tvgName ?? "Unknown"
        }

        let channelId = tvgId.isEmpty ? UUID().uuidString : tvgId

        return ParsedChannel(
            id: channelId,
            name: displayName,
            logoURL: tvgLogo,
            groupTitle: groupTitle,
            streamURL: streamURL
        )
    }

    /// Extract a quoted attribute value from an EXTINF or EXTM3U line.
    /// Handles patterns like: key="value"
    private static func extractAttribute(from line: String, key: String) -> String? {
        let pattern = "\(key)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        let value = String(line[valueRange])
        return value.isEmpty ? nil : value
    }
}

enum M3UParserError: LocalizedError {
    case invalidEncoding
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Failed to decode M3U content as UTF-8."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
