import Foundation

/// Film4k's public player removes a complete PNG envelope before decoding media.
/// This is container normalization, not DRM/key handling.
enum FilmMediaTransform {
    static func unwrap(_ data: Data) -> Data {
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard data.starts(with: signature) else { return data }
        var offset = 8
        while offset + 12 <= data.count {
            let length = (0..<4).reduce(0) { ($0 << 8) | Int(data[offset + $1]) }
            guard length <= data.count - offset - 12 else { return data }
            let end = offset + 12 + length
            if data.subdata(in: offset + 4..<offset + 8) == Data("IEND".utf8) {
                return end < data.count ? data.subdata(in: end..<data.count) : data
            }
            offset = end
        }
        return data
    }

    static func playlist(_ text: String, base: URL, map: (URL) -> URL) -> String {
        let expression = try! NSRegularExpression(pattern: #"URI="([^"]+)""#)
        return text.components(separatedBy: .newlines).map { line in
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty, !clean.hasPrefix("#"), let url = MovieCatalog.url(clean, base: base) {
                return map(url).absoluteString
            }
            var result = line
            for match in expression.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
                guard let range = Range(match.range(at: 1), in: result),
                      let url = MovieCatalog.url(String(result[range]), base: base) else { continue }
                result.replaceSubrange(range, with: map(url).absoluteString)
            }
            return result
        }.joined(separator: "\n")
    }

    static func byteRange(_ header: String, count: Int) -> Range<Int>? {
        guard count > 0, header.hasPrefix("bytes=") else { return nil }
        let parts = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty, let suffix = Int(parts[1]), suffix > 0 { return max(0, count - suffix)..<count }
        guard let start = Int(parts[0]), start >= 0, start < count else { return nil }
        let last: Int
        if parts[1].isEmpty { last = count - 1 }
        else if let parsed = Int(parts[1]), parsed >= start { last = min(parsed, count - 1) }
        else { return nil }
        return start..<(last + 1)
    }
}
