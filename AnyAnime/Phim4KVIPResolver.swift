import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reference IPA 2.8.4 (65): a Core virtual file handle is exchanged at the
/// directory-announced gateway. Free catalogs never enter this resolver.
actor Phim4KVIPResolver {
    static let shared = Phim4KVIPResolver()

    enum Failure: LocalizedError {
        case invalidInput, missingGateway, invalidResponse, invalidMediaURL, invalidClock
        case http(Int), network(Int)
        var errorDescription: String? {
            switch self {
            case .invalidInput: return "Định danh file Phim4K không hợp lệ."
            case .missingGateway: return "Phim4K chưa công bố địa chỉ resolver CDN hợp lệ."
            case .invalidResponse: return "Resolver Phim4K không trả JSON có URL media hợp lệ."
            case .invalidMediaURL: return "Resolver Phim4K trả địa chỉ media không hợp lệ."
            case .invalidClock: return "Thời gian thiết bị không hợp lệ để mở luồng Phim4K."
            case .http(let status) where status == 401 || status == 403:
                return "AUTH_REQUIRED: Resolver Phim4K từ chối quyền truy cập (HTTP \(status))."
            case .http(let status): return "Resolver Phim4K trả HTTP \(status)."
            case .network(let code): return "Không kết nối được resolver Phim4K (mã \(code))."
            }
        }
    }

    // Shared client protocol material shipped in the supplied IPA, not an
    // account token. Reproduce _Ifb.VRh at 0x5dcac / closure 0x5dd58 using the
    // original pool arrays 0x8558/0x8560; do not use the old guessed seed.
    private static var clientSeed: String {
        let first: [UInt32] = [973531036, 2049478008, 2744133347, 2331385187, 3321919771, 2090140770, 3004897461, 2762958431, 1960326038, 1209635432, 2916860840, 1930508090, 2844629154, 2106941750, 1490125092, 3482642150, 2506695951, 940100851, 1598880512, 1854686846, 158460787, 434153393, 3109243497, 3624414593, 4219931305, 2051994738, 635215951, 2648475381, 1766844830, 1996048643, 1217297480, 3211642661]
        let second: [UInt32] = [973531130, 2049477967, 2744133250, 2331385169, 3321919864, 2090140762, 3004897488, 2762958446, 1960326132, 1209635421, 2916860876, 1930508046, 2844629147, 2106941701, 1490125122, 3482642134, 2506696046, 940100805, 1598880610, 1854686796, 158460695, 434153352, 3109243404, 3624414649, 4219931338, 2051994691, 635215913, 2648475334, 1766844927, 1996048694, 1217297450, 3211642641]
        return String(decoding: zip(first, second).map { pair in UInt8(truncatingIfNeeded: pair.0 ^ pair.1) }, as: UTF8.self)
    }
    static var clientMaterialFingerprint: String { hex(Data(SHA256.hash(data: Data(clientSeed.utf8)))) }

    /// Only the catalog's known virtual CDN handles need this exchange.
    /// Real direct media, Free HLS, embeds and lookalike hosts stay separate.
    nonisolated static func requiresGateway(_ url: URL) -> Bool {
        guard url.host?.lowercased() == "cdn.phim4k.lol", url.user == nil, url.password == nil,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        return url.port == nil || url.port == (scheme == "https" ? 443 : 80)
    }

    nonisolated static func extractFileID(from url: URL) -> String? {
        guard let id = url.path.split(separator: "/").last.map(String.init), id != ".", id != "..",
              id.range(of: #"^[A-Za-z0-9._-]{1,256}$"#, options: .regularExpression) != nil else { return nil }
        // Uri.pathSegments.last in the original app does not remove extensions.
        return id
    }

    nonisolated static func deriveDailySecret(seed: String, dateUTC: String) throws -> String {
        guard !seed.isEmpty else { throw Failure.invalidInput }
        let key = SymmetricKey(data: Data(SHA256.hash(data: Data(seed.utf8))))
        let nonce = try AES.GCM.Nonce(data: Data(SHA256.hash(data: Data(("iv:" + seed).utf8))).prefix(12))
        let box = try AES.GCM.seal(Data((seed + ":" + dateUTC).utf8), using: key, nonce: nonce)
        return seed + ":" + hex(box.ciphertext + box.tag)
    }

    nonisolated static func gatewayURL(fileID: String, gateway: URL, timestamp: UInt32, seed: String,
                                       allowLoopbackHTTP: Bool = false) throws -> URL {
        guard Phim4KTransportPolicy.permitsEndpoint(gateway, allowLoopbackHTTP: allowLoopbackHTTP),
              gateway.query == nil, gateway.fragment == nil else { throw Failure.missingGateway }
        guard fileID != ".", fileID != "..", fileID.range(of: #"^[A-Za-z0-9._-]{1,256}$"#, options: .regularExpression) != nil else { throw Failure.invalidInput }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        let day = formatter.string(from: Date(timeIntervalSince1970: Double(timestamp)))
        let daily = try deriveDailySecret(seed: seed, dateUTC: day)
        let key = SymmetricKey(data: Data(daily.utf8))
        let mask = Array(HMAC<SHA256>.authenticationCode(for: Data("otp-ts-mask".utf8), using: key).prefix(4))
        let packed = [UInt8(truncatingIfNeeded: timestamp >> 24), UInt8(truncatingIfNeeded: timestamp >> 16),
                      UInt8(truncatingIfNeeded: timestamp >> 8), UInt8(truncatingIfNeeded: timestamp)]
        let ts = hex(Data(zip(packed, mask).map { pair in pair.0 ^ pair.1 }))
        let token = hex(Data(HMAC<SHA256>.authenticationCode(for: Data((fileID + ":" + String(timestamp)).utf8), using: key)))
        var components = URLComponents(url: gateway.appendingPathComponent(fileID), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "token", value: token), .init(name: "ts", value: ts)]
        guard let url = components.url else { throw Failure.invalidInput }
        return url
    }

    func resolve(_ source: URL, gateway: URL, session: URLSession, now: Date = Date(),
                 allowLoopbackHTTP: Bool = false) async throws -> URL {
        guard let fileID = Self.extractFileID(from: source) else { throw Failure.invalidInput }
        let seconds = now.timeIntervalSince1970.rounded(.down)
        guard seconds.isFinite, seconds >= 0, seconds <= Double(UInt32.max) else { throw Failure.invalidClock }
        let requestURL = try Self.gatewayURL(fileID: fileID, gateway: gateway, timestamp: UInt32(seconds),
                                             seed: Self.clientSeed, allowLoopbackHTTP: allowLoopbackHTTP)
        let result: Phim4KMediaProbe.Result
        let gatewayConfiguration = session.configuration
        gatewayConfiguration.httpAdditionalHeaders = nil
        gatewayConfiguration.httpCookieStorage = nil
        gatewayConfiguration.httpShouldSetCookies = false
        do {
            result = try await Phim4KMediaProbe(limit: 65_536).inspect(requestURL,
                headers: ["User-Agent": "Dart/3.12 (dart:io)"], configuration: gatewayConfiguration,
                allowLoopbackHTTP: allowLoopbackHTTP, sendRange: false, sameOriginOnly: true)
        } catch is CancellationError { throw CancellationError() }
        catch { throw Failure.network((error as NSError).code) }
        try Task.checkCancellation()
        guard result.response.statusCode == 200 else { throw Failure.http(result.response.statusCode) }
        guard !result.wasTruncated,
              let json = try? JSONSerialization.jsonObject(with: result.prefix) as? [String: Any],
              let raw = json["url"] as? String, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let media = URL(string: raw) else { throw Failure.invalidResponse }
        // The original HTTPS gateway legitimately returns HTTP worker media.
        // Preserve its URL/query verbatim; never upgrade/rewrite or play the
        // signed gateway endpoint itself if the exchange fails.
        guard Phim4KTransportPolicy.permitsMediaEndpoint(media, allowLoopbackHTTP: allowLoopbackHTTP),
              media != requestURL else { throw Failure.invalidMediaURL }
        return media
    }

    nonisolated private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
