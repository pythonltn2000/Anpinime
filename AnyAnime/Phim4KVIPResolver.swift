import Foundation
import CryptoKit

/// Resolves Phim4K VIP / 4K / 1080p stream URLs through the time-authenticated CDN gateway.
/// This restores playback for VIP MKV/MP4 servers without relabelling Free1 fallbacks.
actor Phim4KVIPResolver {
    static let shared = Phim4KVIPResolver()

    static let hmacSecret = "5e8d1b4f9c2a6e730b1f8d4a92c5e3d1"
    static let cdnGateway = "https://svatv.cryboiz.workers.dev"

    /// Checks if a media URL requires Phim4K VIP authenticated signing.
    nonisolated func isVIPURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("phim4k.lol") || host.contains("phim4k.space") ||
               host.contains("p4kzz.workers.dev") || host.contains("cryboiz.workers.dev") ||
               url.scheme == "phim4k-vip"
    }

    /// Extracts clean file ID from a Phim4K CDN URL or string.
    nonisolated static func extractFileID(from url: URL) -> String? {
        let clean = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var fileID = clean.split(separator: "/").last.map(String.init) ?? clean
        if let dotIndex = fileID.lastIndex(of: ".") {
            fileID = String(fileID[..<dotIndex])
        }
        return fileID.isEmpty ? nil : fileID
    }

    /// Derives the daily signing key using AES-GCM-256 over secret:dateUtc.
    nonisolated static func deriveDailySecret(secret: String, dateUtc: String) -> String? {
        let keyBytes = SHA256.hash(data: Data(secret.utf8))
        let ivSource = SHA256.hash(data: Data(("iv:" + secret).utf8))
        guard let nonce = try? AES.GCM.Nonce(data: Data(ivSource.prefix(12))) else { return nil }
        let key = SymmetricKey(data: keyBytes)
        let plaintext = Data("\(secret):\(dateUtc)".utf8)
        guard let sealed = try? AES.GCM.seal(plaintext, using: key, nonce: nonce) else { return nil }
        let ciphertextAndTag = sealed.ciphertext + sealed.tag
        let hex = ciphertextAndTag.map { String(format: "%02x", $0) }.joined()
        return "\(secret):\(hex)"
    }

    /// Builds signed CDN gateway URL with OTP timestamp masking and HMAC-SHA256 token.
    nonisolated static func buildGatewayURL(fileID: String, timestamp: UInt32? = nil) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        let dateUtc = formatter.string(from: Date())

        let signingSecret = deriveDailySecret(secret: hmacSecret, dateUtc: dateUtc) ?? hmacSecret
        let nowSec = timestamp ?? UInt32(Date().timeIntervalSince1970)

        let sigKey = SymmetricKey(data: Data(signingSecret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data("otp-ts-mask".utf8), using: sigKey)
        let mask = Array(Data(code).prefix(4))

        var bigEndian = nowSec.bigEndian
        let rawBytes = withUnsafeBytes(of: &bigEndian) { Array($0) }
        let xored = zip(rawBytes, mask).map { $0.0 ^ $0.1 }
        let tsHex = xored.map { String(format: "%02x", $0) }.joined()

        let msg = "\(fileID):\(nowSec)"
        let tokenCode = HMAC<SHA256>.authenticationCode(for: Data(msg.utf8), using: sigKey)
        let token = Data(tokenCode).map { String(format: "%02x", $0) }.joined()

        return URL(string: "\(cdnGateway)/\(fileID)?token=\(token)&ts=\(tsHex)")!
    }

    /// Generates the signed gateway URL with the current daily AES-GCM key and time-dependent OTP token.
    nonisolated func genSignedCDNURL(for urlOrID: String) -> URL? {
        let clean = urlOrID.split(separator: "?").first.map(String.init) ?? urlOrID
        let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var fileID = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        if let dotIndex = fileID.lastIndex(of: ".") {
            fileID = String(fileID[..<dotIndex])
        }
        guard !fileID.isEmpty else { return nil }
        return Self.buildGatewayURL(fileID: fileID)
    }

    /// Resolves the final fast CDN stream URL via the gateway.
    func resolveSecureStreamURL(_ urlOrID: String, session: URLSession = .shared) async -> URL? {
        let trimmed = urlOrID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().contains("sv.p4kzz.workers.dev") {
            return URL(string: trimmed)
        }
        guard let signedURL = genSignedCDNURL(for: trimmed) else {
            return URL(string: trimmed)
        }

        var request = URLRequest(url: signedURL, timeoutInterval: 10)
        request.setValue("okhttp/4.9.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let fastURLString = json["url"] as? String,
               let fastURL = URL(string: fastURLString), !fastURLString.isEmpty {
                #if DEBUG
                print("[Phim4K] Fast CDN URL obtained: \(fastURL.host ?? "")")
                #endif
                return fastURL
            }
        } catch {
            #if DEBUG
            print("[Phim4K] Gateway exchange failed, using signed fallback: \(error.localizedDescription)")
            #endif
        }
        return signedURL
    }
}
