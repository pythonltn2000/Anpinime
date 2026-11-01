import Foundation
import CryptoKit

/// The IPA publishes changing provider addresses in an AES-GCM config envelope.
/// Only the public catalog routes are consumed; account tokens, ads and plugins are ignored.
enum MovieSourceDirectory {
    struct CoreAPI {
        let baseURL: URL
        let apiKey: String
    }

    static func coreAPI() -> CoreAPI {
        let saved = UserDefaults.standard.dictionary(forKey: "AnPinime.source2Directory") as? [String: String] ?? [:]
        let host = saved["api"].flatMap(address) ?? URL(string: "https://api.phim4k.space")!
        let token = saved["tokens"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (token?.isEmpty == false) ? token! : "bbbb411dea44849"
        return CoreAPI(baseURL: host, apiKey: key)
    }

    /// Announced gateway for the verified Core JSON exchange. It is not a
    /// playable media URL or a replacement host for the catalog's virtual URL.
    /// No default is supplied when the original app directory omits it.
    static func cdnGateway(defaults: UserDefaults = .standard) -> URL? {
        let saved = defaults.dictionary(forKey: "AnPinime.source2Directory") as? [String: String] ?? [:]
        return saved["cdn"].flatMap(address)
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
            var updated = defaults.dictionary(forKey: "AnPinime.source2Directory") as? [String: String] ?? [:]
            for name in ["free1", "free2", "api", "cdn"] {
                if let value = config[name] as? String, let url = address(value) { updated[name] = url.absoluteString }
            }
            if let token = config["tokens"] as? String, !token.isEmpty {
                updated["tokens"] = token
            }
            if !updated.isEmpty {
                defaults.set(updated, forKey: "AnPinime.source2Directory")
            }
        } catch { /* A last-known directory remains useful during a temporary bootstrap outage. */ }
    }

    // These are catalogs actually announced by the reference app, never substitutes
    // for NguonC/KKPhim. A missing Free2 must not be replaced with phim.nguonc.com.
    static func catalogs() -> [(id: String, url: URL, format: Phim4KFormat)] {
        let saved = UserDefaults.standard.dictionary(forKey: "AnPinime.source2Directory") as? [String: String] ?? [:]
        var result: [(String, URL, Phim4KFormat)] = [
            ("free1", saved["free1"].flatMap(address) ?? Phim4KFormat.free1.defaultURL, .free1)
        ]
        if let url = saved["free2"].flatMap(address) { result.append(("free2", url, .free2)) }
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
