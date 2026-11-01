import Foundation
import CryptoKit

/// The IPA publishes changing provider addresses in an AES-GCM config envelope.
/// Only the public catalog routes are consumed; account tokens, ads and plugins are ignored.
enum MovieSourceDirectory {
    struct CoreAPI {
        let baseURL: URL
        let apiKey: String
        let authorization: String?

        init(baseURL: URL, apiKey: String, authorization: String? = nil) {
            self.baseURL = baseURL; self.apiKey = apiKey; self.authorization = authorization
        }
    }

    private struct ClientHeaders {
        let apiKey: String
        let authorization: String
    }

    // Public API-client fallback shipped in the reference IPA (PP0xb2a0/0xb2b0),
    // separate from account logins and the media gateway's signing seed.
    private static let clientDefaults = Data([97, 100, 109, 105, 110, 58, 49, 50, 51, 52])

    static func coreAPI(defaults: UserDefaults = .standard) -> CoreAPI {
        let saved = defaults.dictionary(forKey: "AnPinime.source2Directory") ?? [:]
        let host = (saved["api"] as? String).flatMap(address) ?? URL(string: "https://api.phim4k.space")!
        let client = clientHeaders(saved["tokens"])
        let cachedAuthorization = validAuthorization(saved["clientAuthorization"])
        // Old caches contain only tokens; map/JSON-map caches recover their
        // client fields, while normalized plain-key caches retain their Basic map.
        let isPlainKey = (saved["tokens"] as? String).map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") } ?? false
        return CoreAPI(baseURL: host, apiKey: client?.apiKey ?? "bbbb411dea44849",
                       authorization: isPlainKey && client != nil ? (cachedAuthorization ?? client?.authorization) : (client?.authorization ?? defaultAuthorization()))
    }

    private static func defaultAuthorization() -> String {
        "Basic " + clientDefaults.base64EncodedString()
    }

    private static func validAuthorization(_ raw: Any?) -> String? {
        guard let value = raw as? String, value.hasPrefix("Basic "),
              let bytes = Data(base64Encoded: String(value.dropFirst(6))),
              let pair = String(data: bytes, encoding: .utf8), pair.contains(":") else { return nil }
        return value
    }

    private static func text(_ raw: Any?) -> String? {
        guard let raw = raw as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func firstText(_ object: [String: Any], aliases: [String]) -> String? {
        aliases.lazy.compactMap { text(object[$0]) }.first
    }

    private static func clientHeaders(_ raw: Any?) -> ClientHeaders? {
        let object: [String: Any]?
        let plainKey: String?
        if let value = text(raw) {
            if value.hasPrefix("{") || value.hasPrefix("[") {
                guard let data = value.data(using: .utf8),
                      let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                object = parsed; plainKey = nil
            } else { object = nil; plainKey = value }
        } else { object = raw as? [String: Any]; plainKey = nil }
        guard let key = plainKey ?? object.flatMap({ firstText($0, aliases: ["api_key", "apiKey", "key", "token"]) }),
              key.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        let defaults = String(decoding: clientDefaults, as: UTF8.self).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let user = object.flatMap { firstText($0, aliases: ["username", "user"]) } ?? String(defaults[0])
        let password = object.flatMap { firstText($0, aliases: ["password", "pass"]) } ?? String(defaults[1])
        let authorization = "Basic " + Data((user + ":" + password).utf8).base64EncodedString()
        return ClientHeaders(apiKey: key, authorization: authorization)
    }

    /// Announced gateway for the verified Core JSON exchange. It is not a
    /// playable media URL or a replacement host for the catalog's virtual URL.
    /// No default is supplied when the original app directory omits it.
    static func cdnGateway(defaults: UserDefaults = .standard) -> URL? {
        let saved = defaults.dictionary(forKey: "AnPinime.source2Directory") ?? [:]
        return (saved["cdn"] as? String).flatMap(address)
    }

    static func refresh(session: URLSession, defaults: UserDefaults = .standard) async {
        do {
            var request = URLRequest(url: URL(string: "https://rip.cryboiz.workers.dev/api/add")!)
            request.timeoutInterval = 3.5
            request.setValue("Dart/3.12 (dart:io)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 65_536 else { throw MovieSourceError.invalidData }
            let envelope = try MovieCatalog.object(data)
            guard envelope["alg"] as? String == "AES-GCM-256", envelope["encoding"] as? String == "base64url",
                  let iv = decode(envelope["iv"]), let sealed = decode(envelope["ciphertext"]), sealed.count > 16 else {
                throw MovieSourceError.invalidData
            }
            // Client-side configuration decoding material, not an account/API authorization token.
            let key = SymmetricKey(data: Data([206, 51, 195, 123, 77, 239, 26, 201, 30, 27, 136, 218, 57, 173, 133, 211,
                                               137, 62, 112, 164, 243, 123, 157, 247, 17, 203, 108, 161, 208, 77, 197, 2]))
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: sealed.dropLast(16), tag: sealed.suffix(16))
            let decoded = try MovieCatalog.object(AES.GCM.open(box, using: key))
            guard let config = decoded["data"] as? MovieCatalog.Object else { throw MovieSourceError.invalidData }
            // A partial bootstrap response must not erase an already-known
            // Free2 catalog or a valid Core configuration.
            var updated = defaults.dictionary(forKey: "AnPinime.source2Directory") ?? [:]
            for name in ["free1", "free2", "api", "cdn"] {
                if let value = config[name] as? String, let url = address(value) { updated[name] = url.absoluteString }
            }
            if let client = clientHeaders(config["tokens"]) {
                // Retain the original tokens cache key as a normalized API key
                // for older app versions; never replace valid headers with a
                // missing/invalid partial response or an account session.
                updated["tokens"] = client.apiKey
                updated["clientAuthorization"] = client.authorization
            }
            if !updated.isEmpty {
                defaults.set(updated, forKey: "AnPinime.source2Directory")
            }
        } catch { /* A last-known directory remains useful during a temporary bootstrap outage. */ }
    }

    // These are catalogs actually announced by the reference app, never substitutes
    // for NguonC/KKPhim. A missing Free2 must not be replaced with phim.nguonc.com.
    static func catalogs(defaults: UserDefaults = .standard) -> [(id: String, url: URL, format: Phim4KFormat)] {
        let saved = defaults.dictionary(forKey: "AnPinime.source2Directory") ?? [:]
        var result: [(String, URL, Phim4KFormat)] = [
            ("free1", (saved["free1"] as? String).flatMap(address) ?? Phim4KFormat.free1.defaultURL, .free1)
        ]
        if let url = (saved["free2"] as? String).flatMap(address) { result.append(("free2", url, .free2)) }
        return result
    }

    private static func address(_ value: String) -> URL? {
        let raw = value.contains("://") ? value : "https://" + value
        guard let url = URL(string: raw), url.scheme == "https", let host = url.host, host.contains("."),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              host != "localhost", !host.hasSuffix(".local"), host != "127.0.0.1" else { return nil }
        return url
    }

    private static func decode(_ value: Any?) -> Data? {
        guard let string = value as? String else { return nil }
        let normalized = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4))
    }
}
