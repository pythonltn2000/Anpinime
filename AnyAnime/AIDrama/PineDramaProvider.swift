import Foundation
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The supplied PineDrama client's catalog transport, independent of movie sources.
actor PineDramaProvider: AIDramaProviding {
    struct Configuration: Sendable {
        let baseURL: URL
        let commonParameters: [String: String]
        var allowLoopbackHTTP = false
        var userAgent = "PineDrama/466003 CFNetwork/Darwin"

        init(baseURL: URL, commonParameters: [String: String], allowLoopbackHTTP: Bool = false,
             userAgent: String = "PineDrama/466003 CFNetwork/Darwin") {
            self.baseURL = baseURL
            self.commonParameters = commonParameters
            self.allowLoopbackHTTP = allowLoopbackHTTP
            self.userAgent = userAgent
        }

        static var production: Configuration {
            var machine = utsname()
            uname(&machine)
            let hardware = withUnsafeBytes(of: &machine.machine) { bytes in
                String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            let profile = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? hardware
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let version = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            return Configuration(baseURL: URL(string: "https://api-va.tiktokv.com")!, commonParameters: [
                "aid": "845221", "app_name": "tiktok_drama", "app_package": "com.ss.iphone.ttmd.video",
                "channel": "App Store", "version_code": "46.6.0", "app_version": "46.6.0", "build_number": "466003",
                "device_platform": profile.hasPrefix("iPad") ? "ipad" : "iphone", "device_type": profile,
                "os_version": version, "os_api": String(os.majorVersion), "language": "vi", "app_language": "vi",
                "locale": "vi_VN", "sys_region": "VN", "region": "VN", "content_language": "vi",
                "tz_name": TimeZone.current.identifier, "tz_offset": String(TimeZone.current.secondsFromGMT())
            ])
        }
    }

    private let configuration: Configuration
    private let session: URLSession
    private static let bodyLimit = 2 * 1024 * 1024

    init(configuration: Configuration = .production, session suppliedSession: URLSession? = nil) {
        self.configuration = configuration
        let transport = suppliedSession?.configuration ?? .ephemeral
        transport.httpCookieStorage = nil
        transport.httpShouldSetCookies = false
        transport.httpAdditionalHeaders = nil
        transport.urlCache = nil
        transport.requestCachePolicy = .reloadIgnoringLocalCacheData
        transport.timeoutIntervalForRequest = 12
        transport.timeoutIntervalForResource = 15
        session = URLSession(configuration: transport, delegate: PineDramaAPIRedirectPolicy(configuration: configuration), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func discover(cursor: String?) async throws -> AIDramaCatalogPage {
        let (data, _) = try await request("mini_drama_center/v1/", parameters: [
            "scene": "1", "category_id": "", "cursor": cursor ?? "", "count": "12", "is_mixed_column_page": "0"
        ])
        return try Self.decodeCatalog(data)
    }

    func playlist(for series: AIDramaSeries) async throws -> AIDramaPlaylist {
        guard Self.identifier(series.id) != nil else { throw AIDramaError.invalidResponse }
        let (data, _) = try await request("collection/episode_panel/v1/", parameters: ["collection_id": series.id])
        return try Self.decodePlaylist(data, series: series)
    }

    func resolve(_ episode: AIDramaEpisode) async throws -> AIDramaStream {
        guard !episode.isLocked else { throw AIDramaError.lockedEpisode }
        guard Self.identifier(episode.id) != nil, Self.identifier(episode.seriesID) != nil, episode.number > 0 else {
            throw AIDramaError.missingEpisode
        }
        let (data, response) = try await request("collection/video/v1/", parameters: [
            "collection_id": episode.seriesID, "query_type": "seq_id", "current_seq_id": String(episode.number),
            "count": "10", "direction": "1", "root_scene": "2", "query_scene": "mini_drama_container",
            "enter_from": "series_discover", "is_trailer_paginated": "0", "need_collection_detail": "0",
            "drama_request_type": "load_more", "iap_country_code": "", "request_source": ""
        ])
        return try Self.decodeVideo(data, contentType: response.value(forHTTPHeaderField: "Content-Type"), episode: episode,
                                    allowLoopbackHTTP: configuration.allowLoopbackHTTP, userAgent: configuration.userAgent)
    }

    private func request(_ path: String, parameters: [String: String]) async throws -> (Data, HTTPURLResponse) {
        guard Self.permitsAPI(configuration.baseURL, allowLoopbackHTTP: configuration.allowLoopbackHTTP),
              var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw AIDramaError.invalidResponse
        }
        components.path = configuration.baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = (components.path.isEmpty ? "" : "/" + components.path) + "/tiktok/md/" + path
        var query = configuration.commonParameters
        for (key, value) in parameters { query[key] = value }
        components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        guard let url = components.url else { throw AIDramaError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, application/x-protobuf", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AIDramaError.invalidResponse }
        guard http.statusCode == 200 else {
            throw AIDramaError.unavailable("Nguồn Phim AI trả HTTP \(http.statusCode). Hãy thử lại sau.")
        }
        guard !data.isEmpty, data.count <= Self.bodyLimit else { throw AIDramaError.invalidResponse }
        return (data, http)
    }

    // Internal pure decoders allow fixture tests to exercise the exact wire contracts.
    static func decodeCatalog(_ data: Data) throws -> AIDramaCatalogPage {
        let object = try jsonObject(data)
        try checkStatus(object)
        guard let rows = object["collections"] as? [[String: Any]], !rows.isEmpty else { throw AIDramaError.invalidResponse }
        var seen = Set<String>()
        let series: [AIDramaSeries] = try rows.map { row in
            guard let id = identifier(row["collection_id_str"]) ?? identifier(row["collection_id"]),
                  let title = text(row["title"]), seen.insert(id).inserted else { throw AIDramaError.invalidResponse }
            let total = integer(row["num_videos"])
            guard total == nil || total! > 0 else { throw AIDramaError.invalidResponse }
            return AIDramaSeries(id: id, title: title, coverURL: cover(row["cover"]),
                                 summary: text(row["description"]) ?? "", episodeCount: total)
        }
        let cursor = try flag(object, "has_more") ? text(object["cursor"]) : nil
        return AIDramaCatalogPage(series: series, nextCursor: cursor)
    }

    static func decodePlaylist(_ data: Data, series: AIDramaSeries) throws -> AIDramaPlaylist {
        let object = try jsonObject(data)
        try checkStatus(object)
        guard let rows = object["episode_list"] as? [[String: Any]],
              let expected = series.episodeCount, expected > 0 else { throw AIDramaError.incompletePlaylist }
        var seenIDs = Set<String>(), seenNumbers = Set<Int>()
        var episodes: [AIDramaEpisode] = []
        for row in rows {
            if try flag(row, "is_intro") { continue }
            guard let id = identifier(row["video_id_str"]) ?? identifier(row["video_id"]),
                  let sequence = integer(row["seq_id"]), sequence > 0,
                  let number = integer(row["num"]), number > 0, number == sequence,
                  seenIDs.insert(id).inserted, seenNumbers.insert(sequence).inserted else { throw AIDramaError.incompletePlaylist }
            let locked = try flag(row, "is_paid") && !flag(row, "has_purchased") && !flag(row, "is_limited_free")
            episodes.append(AIDramaEpisode(id: id, seriesID: series.id, number: sequence,
                                           title: text(row["title"]) ?? "", coverURL: series.coverURL, isLocked: locked))
        }
        guard episodes.count == expected else { throw AIDramaError.incompletePlaylist }
        episodes.sort { $0.number < $1.number }
        guard episodes.map(\.number) == Array(1...expected) else { throw AIDramaError.incompletePlaylist }
        return AIDramaPlaylist(series: series, episodes: episodes, reportedTotal: expected)
    }

    static func decodeVideo(_ data: Data, contentType: String?, episode: AIDramaEpisode,
                            allowLoopbackHTTP: Bool = false, userAgent: String = "PineDrama/466003 CFNetwork/Darwin") throws -> AIDramaStream {
        guard !episode.isLocked else { throw AIDramaError.lockedEpisode }
        guard data.count <= bodyLimit else { throw AIDramaError.invalidResponse }
        let startsWithJSON = data.first(where: { ![9, 10, 13, 32].contains($0) }) == 123
        let candidates: [String]
        if startsWithJSON || contentType?.lowercased().contains("json") == true {
            candidates = try jsonVideoURLs(jsonObject(data), episode: episode)
        } else {
            candidates = try protobufVideoURLs(data, episode: episode)
        }
        guard let url = candidates.lazy.compactMap({ mediaURL($0, allowLoopbackHTTP: allowLoopbackHTTP) }).first else {
            throw AIDramaError.unavailable("Nguồn phim chưa trả URL video hợp lệ cho tập đã chọn.")
        }
        return AIDramaStream(url: url, headers: ["User-Agent": userAgent])
    }

    private static func jsonVideoURLs(_ object: [String: Any], episode: AIDramaEpisode) throws -> [String] {
        try checkStatus(object)
        guard let rows = object["paid_videos"] as? [[String: Any]] else { throw AIDramaError.invalidResponse }
        let matching = rows.filter { row in
            let aweme = row["aweme"] as? [String: Any]
            return identifier(row["paid_video_id"]) == episode.id || identifier(aweme?["aweme_id"]) == episode.id
        }
        guard matching.count == 1, let row = matching.first, integer(row["seq_id"]) == episode.number,
              let aweme = row["aweme"] as? [String: Any], let video = aweme["video"] as? [String: Any] else {
            throw AIDramaError.missingEpisode
        }
        guard !(try flag(row, "is_intro")) else { throw AIDramaError.missingEpisode }
        var seriesIDs: [String] = []
        if let collection = object["collection"] as? [String: Any], let id = identifier(collection["collection_id"]) { seriesIDs.append(id) }
        if let paid = (aweme["paid_content_info"] ?? aweme["paid_content"]) as? [String: Any] {
            if let id = identifier(paid["paid_collection_id"]) { seriesIDs.append(id) }
            if try flag(paid, "is_partial_preview") || flag(paid, "should_show_preview") || flag(paid, "is_paid_video_encrypted") {
                throw AIDramaError.lockedEpisode
            }
        }
        guard !seriesIDs.isEmpty, seriesIDs.allSatisfy({ $0 == episode.seriesID }) else { throw AIDramaError.missingEpisode }
        guard !(try flag(video, "need_set_token")) else { throw AIDramaError.lockedEpisode }
        var urls = (video["play_addr"] as? [String: Any])?["url_list"] as? [String] ?? []
        urls += (video["play_addr_h264"] as? [String: Any])?["url_list"] as? [String] ?? []
        return urls
    }

    private static func protobufVideoURLs(_ data: Data, episode: AIDramaEpisode) throws -> [String] {
        let response = try PineDramaPBMessage(data)
        let status = try response.uint(1) ?? 0
        guard status == 0 else { throw serviceError(status) }
        guard try response.uint(27) ?? 0 == 0 else { throw serviceError(try response.uint(27) ?? 0) }
        let rows = try response.messages(2)
        var matching: [(PineDramaPBMessage, PineDramaPBMessage)] = []
        for row in rows {
            guard let aweme = try row.message(4) else { continue }
            if try row.identifier(1) == episode.id || aweme.string(1) == episode.id { matching.append((row, aweme)) }
        }
        guard matching.count == 1, let (row, aweme) = matching.first,
              try row.uint(12) == UInt64(episode.number), let video = try aweme.message(7) else { throw AIDramaError.missingEpisode }
        guard try row.uint(5) ?? 0 == 0 else { throw AIDramaError.missingEpisode }
        var seriesIDs: [String] = []
        if let collection = try response.message(14), let id = try collection.identifier(1) { seriesIDs.append(id) }
        if let paid = try aweme.message(317) {
            if let id = try paid.identifier(1) { seriesIDs.append(id) }
            if try paid.uint(7) ?? 0 != 0 || paid.uint(8) ?? 0 != 0 || paid.uint(17) ?? 0 != 0 { throw AIDramaError.lockedEpisode }
        }
        guard !seriesIDs.isEmpty, seriesIDs.allSatisfy({ $0 == episode.seriesID }) else { throw AIDramaError.missingEpisode }
        guard try video.uint(24) ?? 0 == 0 else { throw AIDramaError.lockedEpisode }
        var urls: [String] = []
        for field in [1, 18] {
            if let address = try video.message(field) { urls += try address.strings(2) }
        }
        return urls
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= bodyLimit,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIDramaError.invalidResponse }
        return object
    }

    private static func checkStatus(_ object: [String: Any]) throws {
        guard let status = integer(object["status_code"]) else { throw AIDramaError.invalidResponse }
        guard status == 0 else { throw serviceError(UInt64(max(0, status))) }
        if let raw = object["biz_code"], !(raw is NSNull) {
            guard let code = integer(raw) else { throw AIDramaError.invalidResponse }
            guard code == 0 else { throw serviceError(UInt64(max(0, code))) }
        }
    }

    private static func serviceError(_ code: UInt64) -> AIDramaError {
        .unavailable("Nguồn Phim AI chưa cho phép lấy video (mã \(code)).")
    }

    private static func text(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    private static func identifier(_ raw: Any?) -> String? {
        let value: String
        if let string = raw as? String { value = string }
        else if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                !["f", "d"].contains(String(cString: number.objCType)) { value = number.stringValue }
        else { return nil }
        guard !value.isEmpty, value.utf8.count <= 19, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = UInt64(value), number > 0, number <= UInt64(Int64.max) else { return nil }
        return value
    }

    private static func integer(_ raw: Any?) -> Int? {
        if let string = raw as? String { return Int(string) }
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)) else { return nil }
        return Int(number.stringValue)
    }

    private static func flag(_ object: [String: Any], _ key: String) throws -> Bool {
        guard let value = object[key], !(value is NSNull) else { return false }
        if let number = value as? NSNumber {
            guard number == 0 || number == 1 else { throw AIDramaError.invalidResponse }
            return number == 1
        }
        if let string = value as? String {
            if ["true", "1"].contains(string.lowercased()) { return true }
            if ["false", "0"].contains(string.lowercased()) { return false }
        }
        throw AIDramaError.invalidResponse
    }

    private static func cover(_ raw: Any?) -> URL? {
        let values = (raw as? [String: Any])?["url_list"] as? [String] ?? (raw as? String).map { [$0] } ?? []
        return values.lazy.compactMap { value -> URL? in
            guard let url = mediaURL(value, allowLoopbackHTTP: false), url.scheme?.lowercased() == "https" else { return nil }
            return url
        }.first
    }

    fileprivate static func permitsAPI(_ url: URL, allowLoopbackHTTP: Bool) -> Bool {
        guard url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              let host = url.host, !host.isEmpty, let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "https" { return true }
        return scheme == "http" && allowLoopbackHTTP && loopback(host)
    }

    private static func mediaURL(_ raw: String, allowLoopbackHTTP: Bool) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || (1...65535).contains(url.port!), !url.path.isEmpty,
              !loopback(host) || allowLoopbackHTTP,
              !url.path.hasPrefix("/tiktok/md/"), !["json", "html", "htm"].contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }

    private static func loopback(_ host: String) -> Bool { ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased()) }
}

/// Only this provider's API requests use this policy; it owns no account cookies.
private final class PineDramaAPIRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let configuration: PineDramaProvider.Configuration
    init(configuration: PineDramaProvider.Configuration) { self.configuration = configuration }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let destination = request.url, let source = response.url,
              destination.scheme?.lowercased() == source.scheme?.lowercased(),
              destination.host?.lowercased() == source.host?.lowercased(), destination.port == source.port,
              destination.user == nil, destination.password == nil,
              destination.path.hasPrefix("/tiktok/md/") else { completionHandler(nil); return }
        var next = request
        next.httpShouldHandleCookies = false
        completionHandler(next)
    }
}

/// A bounded reader for the supplied app's known protobuf fields. Unknown fields
/// are retained/skipped by wire type; malformed lengths/varints never reach a URL.
private struct PineDramaPBMessage {
    enum Value { case uint(UInt64), bytes(Data), fixed }
    private let fields: [Int: [Value]]

    init(_ data: Data) throws {
        guard data.count <= 2 * 1024 * 1024 else { throw AIDramaError.invalidResponse }
        let bytes = [UInt8](data)
        var offset = 0
        var result: [Int: [Value]] = [:]
        var count = 0
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<10 {
                guard offset < bytes.count else { throw AIDramaError.invalidResponse }
                let byte = bytes[offset]; offset += 1
                guard index < 9 || byte <= 1 else { throw AIDramaError.invalidResponse }
                value |= UInt64(byte & 127) << (index * 7)
                if byte & 128 == 0 { return value }
            }
            throw AIDramaError.invalidResponse
        }
        while offset < bytes.count {
            count += 1
            guard count <= 50_000 else { throw AIDramaError.invalidResponse }
            let tag = try varint(), field = tag >> 3, wire = tag & 7
            guard field > 0, field <= 536_870_911 else { throw AIDramaError.invalidResponse }
            let value: Value
            switch wire {
            case 0: value = .uint(try varint())
            case 1, 5:
                let size = wire == 1 ? 8 : 4
                guard size <= bytes.count - offset else { throw AIDramaError.invalidResponse }
                offset += size; value = .fixed
            case 2:
                let length = try varint()
                guard length <= UInt64(bytes.count - offset) else { throw AIDramaError.invalidResponse }
                let end = offset + Int(length)
                value = .bytes(Data(bytes[offset..<end])); offset = end
            default: throw AIDramaError.invalidResponse
            }
            result[Int(field), default: []].append(value)
        }
        fields = result
    }

    func uint(_ field: Int) throws -> UInt64? {
        guard let values = fields[field] else { return nil }
        guard values.count == 1, case .uint(let value) = values[0] else { throw AIDramaError.invalidResponse }
        return value
    }

    func identifier(_ field: Int) throws -> String? {
        guard let value = try uint(field) else { return nil }
        guard value > 0, value <= UInt64(Int64.max) else { throw AIDramaError.invalidResponse }
        return String(value)
    }

    func string(_ field: Int) throws -> String? {
        guard let values = fields[field] else { return nil }
        guard values.count == 1, case .bytes(let data) = values[0], let value = String(data: data, encoding: .utf8) else {
            throw AIDramaError.invalidResponse
        }
        return value
    }

    func strings(_ field: Int) throws -> [String] {
        try (fields[field] ?? []).map { value in
            guard case .bytes(let data) = value, let text = String(data: data, encoding: .utf8) else { throw AIDramaError.invalidResponse }
            return text
        }
    }

    func message(_ field: Int) throws -> PineDramaPBMessage? {
        guard let values = fields[field] else { return nil }
        guard values.count == 1, case .bytes(let data) = values[0] else { throw AIDramaError.invalidResponse }
        return try PineDramaPBMessage(data)
    }

    func messages(_ field: Int) throws -> [PineDramaPBMessage] {
        try (fields[field] ?? []).map { value in
            guard case .bytes(let data) = value else { throw AIDramaError.invalidResponse }
            return try PineDramaPBMessage(data)
        }
    }
}
