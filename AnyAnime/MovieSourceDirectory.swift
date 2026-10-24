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
        let host = saved["api"].flatMap(address) ?? URL(string: "https://api.phim4k.online")!
        let token = saved["tokens"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (token?.isEmpty == false) ? token! : "bbbb411dea44849"
        return CoreAPI(baseURL: host, apiKey: key)
    }

    static func candidates(session: URLSession) async -> [(URL, Phim4KFormat)] {
        var addresses = UserDefaults.standard.dictionary(forKey: "AnPinime.source2Directory") as? [String: String] ?? [:]
        do {
            var request = URLRequest(url: URL(string: "https://rip.cryboiz.workers.dev/api/add")!)
            request.timeoutInterval = 3.5
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
            var updated: [String: String] = [:]
            for name in ["free1", "free2", "api"] {
                if let value = config[name] as? String, let url = address(value) { updated[name] = url.absoluteString }
            }
            if let token = config["tokens"] as? String, !token.isEmpty {
                updated["tokens"] = token
            }
            if !updated.isEmpty {
                addresses = updated
                UserDefaults.standard.set(updated, forKey: "AnPinime.source2Directory")
            }
        } catch { /* A last-known directory remains useful during a temporary bootstrap outage. */ }
        var result: [(URL, Phim4KFormat)] = []
        if let raw = addresses["free1"], let url = address(raw) {
            result.append((url, .free1))
        }
        let defaultFree1 = Phim4KFormat.free1.defaultURL
        if !result.contains(where: { $0.0 == defaultFree1 }) {
            result.append((defaultFree1, .free1))
        }
        if let phimAPI = URL(string: "https://phimapi.com"), !result.contains(where: { $0.0 == phimAPI }) {
            result.append((phimAPI, .free1))
        }
        let defaultFree2 = Phim4KFormat.free2.defaultURL
        if !result.contains(where: { $0.0 == defaultFree2 }) {
            result.append((defaultFree2, .free2))
        }
        if let raw = addresses["free2"], let url = address(raw), !result.contains(where: { $0.0 == url }) {
            result.append((url, .free2))
        }
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
