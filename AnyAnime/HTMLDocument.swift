import Foundation

/// Small, non-executing HTML tokenizer. Keeps ancestor context so links from
/// comments, account menus and script strings cannot become episode links.
enum HTMLDocument {
    struct Element {
        let tag: String
        let attributes: [String: String]
        var marker: String { ((attributes["id"] ?? "") + " " + (attributes["class"] ?? "")).lowercased() }
    }
    struct Link {
        let attributes: [String: String]
        let body: String
        let ancestors: [Element]
        var text: String { HTMLDocument.text(body) }
        var marker: String { ((attributes["id"] ?? "") + " " + (attributes["class"] ?? "")).lowercased() }
        var excluded: Bool {
            ancestors.contains { element in
                ["nav", "header", "footer", "form"].contains(element.tag) ||
                element.marker.range(of: #"(?:comment|disqus|reply|user-profile|login|register|dang-nhap)"#, options: .regularExpression) != nil
            }
        }
    }

    static func links(_ html: String) -> [Link] {
        let pattern = #"(?is)<!--.*?-->|<(?:script|style)\b[^>]*>.*?</(?:script|style)\s*>|</?([a-z][a-z0-9:-]*)\b(?:"[^"]*"|'[^']*'|[^'">])*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let string = html as NSString
        var stack: [(Element, Int)] = []
        var output: [Link] = []
        let voids: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
        for match in regex.matches(in: html, range: NSRange(location: 0, length: string.length)) {
            guard match.range(at: 1).location != NSNotFound else { continue }
            let tag = string.substring(with: match.range(at: 1)).lowercased()
            let raw = string.substring(with: match.range)
            if raw.hasPrefix("</") {
                guard let index = stack.lastIndex(where: { $0.0.tag == tag }) else { continue }
                if tag == "a" {
                    let entry = stack[index]
                    let body = string.substring(with: NSRange(location: entry.1, length: max(0, match.range.location - entry.1)))
                    output.append(Link(attributes: entry.0.attributes, body: body, ancestors: stack[..<index].map { $0.0 }))
                }
                stack.removeSubrange(index...)
            } else if !voids.contains(tag) && !raw.hasSuffix("/>") {
                // HTML implicitly closes a prior anchor when another anchor starts.
                if tag == "a", let old = stack.lastIndex(where: { $0.0.tag == "a" }) { stack.removeSubrange(old...) }
                stack.append((Element(tag: tag, attributes: attributes(raw)), match.range.location + match.range.length))
            }
        }
        return output
    }

    static func attributes(_ tag: String) -> [String: String] {
        let pattern = #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let string = tag as NSString
        var values: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(location: 0, length: string.length)) {
            let key = string.substring(with: match.range(at: 1)).lowercased()
            for index in 2...4 where match.range(at: index).location != NSNotFound {
                values[key] = entities(string.substring(with: match.range(at: index)))
                break
            }
        }
        return values
    }

    static func text(_ html: String) -> String {
        entities(html.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func entities(_ value: String) -> String {
        var result = value
        for (from, to) in ["&amp;": "&", "&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&lt;": "<", "&gt;": ">"] {
            result = result.replacingOccurrences(of: from, with: to)
        }
        if let regex = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#) {
            let string = result as NSString
            for match in regex.matches(in: result, range: NSRange(location: 0, length: string.length)).reversed() {
                let raw = string.substring(with: match.range(at: 1))
                if let number = UInt32(raw.hasPrefix("x") ? String(raw.dropFirst()) : raw, radix: raw.hasPrefix("x") ? 16 : 10),
                   let scalar = UnicodeScalar(number), let range = Range(match.range, in: result) {
                    result.replaceSubrange(range, with: String(scalar))
                }
            }
        }
        return result
    }
}
