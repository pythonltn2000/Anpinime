import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Standalone: swiftc AIDramaModels.swift PineDramaProvider.swift AIDramaProviderTests.swift.
@main
struct AIDramaProviderTests {
    static let seriesNumber: Int64 = 7_000_000_000_000_000_001
    static let episodeNumber: Int64 = 7_000_000_000_000_000_103
    static let media = "https://media.example/episode-03.mp4"
    static let series = AIDramaSeries(id: String(seriesNumber), title: "Provider fixture", episodeCount: 40)
    static let episode = AIDramaEpisode(id: String(episodeNumber), seriesID: String(seriesNumber), number: 3)

    enum FailureKind { case invalid, incomplete, missing, locked, unavailable }

    static func check(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAIL: " + message) }
        print("PASS: " + message)
    }

    static func matches(_ error: Error, _ kind: FailureKind) -> Bool {
        guard let failure = error as? AIDramaError else { return false }
        switch (failure, kind) {
        case (.invalidResponse, .invalid), (.incompletePlaylist, .incomplete),
             (.missingEpisode, .missing), (.lockedEpisode, .locked), (.unavailable, .unavailable): return true
        default: return false
        }
    }

    static func rejects(_ message: String, kind: FailureKind? = nil, _ action: () throws -> Void) {
        do {
            try action()
            fatalError("FAIL: accepted " + message)
        } catch {
            if let kind { check(matches(error, kind), message + " has the expected error") }
            else { print("PASS: rejects " + message) }
        }
    }

    static func rejectsAsync(_ message: String, kind: FailureKind, _ action: () async throws -> Void) async {
        do {
            try await action()
            fatalError("FAIL: accepted " + message)
        } catch { check(matches(error, kind), message + " has the expected error") }
    }

    static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func catalog(_ rows: [[String: Any]], status: Int = 0) throws -> Data {
        try json(["status_code": status, "collections": rows, "has_more": true, "cursor": "page-two"])
    }

    static func playlist(_ rows: [[String: Any]]) throws -> Data {
        try json(["status_code": 0, "episode_list": rows])
    }

    static func episodeRows() -> [[String: Any]] {
        (1...40).map { number in
            ["video_id": seriesNumber + 99 + Int64(number), "seq_id": number, "num": number,
             "is_paid": true, "is_limited_free": true]
        }
    }

    static func videoRow(id: Int64 = 7_000_000_000_000_000_103, sequence: Int = 3,
                         url: String = "https://media.example/episode-03.mp4",
                         paid: [String: Any]? = nil, token: Bool = false, intro: Bool = false) -> [String: Any] {
        var aweme: [String: Any] = ["aweme_id": String(id), "video": [
            "play_addr": ["url_list": [url]], "need_set_token": token,
        ]]
        if let paid { aweme["paid_content"] = paid }
        return ["paid_video_id": id, "seq_id": sequence, "aweme": aweme, "is_intro": intro]
    }

    static func video(_ rows: [[String: Any]], collection: Int64? = 7_000_000_000_000_000_001) throws -> Data {
        var object: [String: Any] = ["status_code": 0, "paid_videos": rows]
        if let collection { object["collection"] = ["collection_id": collection] }
        return try json(object)
    }

    static func decode(_ data: Data, loopback: Bool = false, selected: AIDramaEpisode = AIDramaProviderTests.episode) throws -> AIDramaStream {
        try PineDramaProvider.decodeVideo(data, contentType: nil, episode: selected, allowLoopbackHTTP: loopback)
    }

    static func testCatalog() throws {
        let row: [String: Any] = ["collection_id": seriesNumber, "title": "  Native fixture  ", "num_videos": 40,
                                  "cover": ["url_list": ["javascript:bad", "https://media.example/cover.jpg"]]]
        let page = try PineDramaProvider.decodeCatalog(catalog([row]))
        check(page.series.count == 1 && page.series[0].id == "7000000000000000001", "Catalog preserves numeric Int64 ID beyond 2^53")
        check(page.series[0].title == "Native fixture" && page.series[0].episodeCount == 40, "Catalog trims title and retains complete-series count")
        check(page.series[0].coverURL?.absoluteString == "https://media.example/cover.jpg", "Catalog filters invalid cover candidates")
        check(page.nextCursor == "page-two", "Catalog exposes the actual next-page cursor")
        var stringRow = row
        stringRow["collection_id"] = String(seriesNumber)
        check(try PineDramaProvider.decodeCatalog(catalog([stringRow])).series[0].id == String(seriesNumber), "String Int64 catalog IDs remain exact")
        rejects("status-zero empty catalog", kind: .invalid) { _ = try PineDramaProvider.decodeCatalog(catalog([])) }
        rejects("duplicate catalog IDs", kind: .invalid) { _ = try PineDramaProvider.decodeCatalog(catalog([row, row])) }
        rejects("catalog nonzero service status", kind: .unavailable) { _ = try PineDramaProvider.decodeCatalog(catalog([row], status: 7)) }
        rejects("catalog nonzero business status", kind: .unavailable) {
            _ = try PineDramaProvider.decodeCatalog(json(["status_code": 0, "biz_code": 11, "collections": [row]]))
        }
        rejects("catalog missing service status", kind: .invalid) { _ = try PineDramaProvider.decodeCatalog(json(["collections": [row]])) }
        let invalidIDs: [Any] = [true, 0, -1, 1.5, "not-an-id", "9223372036854775808"]
        for invalid in invalidIDs {
            var bad = row
            bad["collection_id"] = invalid
            rejects("invalid catalog ID \(invalid)", kind: .invalid) { _ = try PineDramaProvider.decodeCatalog(catalog([bad])) }
        }
    }

    static func testPlaylist() throws {
        let rows = episodeRows()
        let result = try PineDramaProvider.decodePlaylist(playlist(Array(rows.reversed())), series: series)
        check(result.episodes.count == 40 && result.reportedTotal == 40, "Playlist returns all 40 real episode rows")
        check(result.episodes.map(\.number) == Array(1...40), "Playlist sorts actual sequence numbers")
        check(result.episodes.map(\.id) == (1...40).map { String(seriesNumber + 99 + Int64($0)) }, "Every playlist Int64 episode ID remains exact")
        check(result.episodes.allSatisfy { $0.seriesID == series.id }, "Every episode retains its parent series")
        let intro: [String: Any] = ["video_id": seriesNumber + 98, "is_intro": true]
        let withIntro = try PineDramaProvider.decodePlaylist(playlist([intro] + rows), series: series)
        check(withIntro.episodes.count == 40 && !withIntro.episodes.contains { $0.id == String(seriesNumber + 98) }, "Intro is excluded without discarding any real episode")
        rejects("missing real episode", kind: .incomplete) { _ = try PineDramaProvider.decodePlaylist(playlist(Array(rows.dropLast())), series: series) }
        rejects("intro replacing a real episode", kind: .incomplete) { _ = try PineDramaProvider.decodePlaylist(playlist([intro] + Array(rows.dropLast())), series: series) }
        rejects("status-zero empty playlist", kind: .incomplete) { _ = try PineDramaProvider.decodePlaylist(playlist([]), series: series) }
        rejects("playlist without a reported series count", kind: .incomplete) {
            _ = try PineDramaProvider.decodePlaylist(playlist(rows), series: AIDramaSeries(id: series.id, title: series.title))
        }
        var duplicateID = rows
        duplicateID[39]["video_id"] = rows[0]["video_id"]
        rejects("duplicate episode IDs", kind: .incomplete) { _ = try PineDramaProvider.decodePlaylist(playlist(duplicateID), series: series) }
        var duplicateNumber = rows
        duplicateNumber[39]["seq_id"] = 1
        duplicateNumber[39]["num"] = 1
        rejects("duplicate episode numbers", kind: .incomplete) { _ = try PineDramaProvider.decodePlaylist(playlist(duplicateNumber), series: series) }
        var wrongSequence = rows
        wrongSequence[39]["seq_id"] = 41
        rejects("conflicting sequence and displayed number", kind: .incomplete) { _ = try PineDramaProvider.decodePlaylist(playlist(wrongSequence), series: series) }
        wrongSequence[39]["num"] = 41
        rejects("numbering gap despite 40 rows", kind: .incomplete) { _ = try PineDramaProvider.decodePlaylist(playlist(wrongSequence), series: series) }
        var invalidID = rows
        invalidID[0]["video_id"] = true
        rejects("boolean episode ID", kind: .incomplete) { _ = try PineDramaProvider.decodePlaylist(playlist(invalidID), series: series) }
        var locks = rows
        locks[0]["is_limited_free"] = false
        locks[1]["is_limited_free"] = false
        locks[1]["has_purchased"] = true
        let locked = try PineDramaProvider.decodePlaylist(playlist(locks), series: series)
        check(locked.episodes[0].isLocked && !locked.episodes[1].isLocked && !locked.episodes[2].isLocked,
              "Paid unpurchased episodes lock; purchased and limited-free episodes unlock")
        rejects("locked episode stream", kind: .locked) { _ = try decode(video([videoRow()]), selected: locked.episodes[0]) }
    }

    static func testJSONVideo() throws {
        let resolved = try decode(video([videoRow()]))
        check(resolved.url.absoluteString == media, "JSON response preserves selected episode media URL")
        check(resolved.headers["User-Agent"] != nil && resolved.headers["Cookie"] == nil, "Resolved stream uses provider user agent without account cookies")
        let unrelated = videoRow(id: episodeNumber + 1, sequence: 4, url: "https://media.example/wrong-first.mp4")
        check(try decode(video([unrelated, videoRow()])).url.absoluteString == media, "JSON selects the matching row instead of the first row")
        rejects("JSON with no matching episode", kind: .missing) { _ = try decode(video([unrelated])) }
        rejects("JSON with duplicate matching rows", kind: .missing) { _ = try decode(video([videoRow(), videoRow()])) }
        rejects("JSON with wrong series", kind: .missing) { _ = try decode(video([videoRow()], collection: seriesNumber + 1)) }
        rejects("JSON with no series identity", kind: .missing) { _ = try decode(video([videoRow()], collection: nil)) }
        rejects("JSON with wrong sequence", kind: .missing) { _ = try decode(video([videoRow(sequence: 4)])) }
        rejects("JSON intro instead of episode", kind: .missing) { _ = try decode(video([videoRow(intro: true)])) }
        rejects("status-zero empty video rows", kind: .missing) { _ = try decode(video([])) }
        let paidIdentity: [String: Any] = ["paid_collection_id": seriesNumber]
        check(try decode(video([videoRow(paid: paidIdentity)], collection: nil)).url.absoluteString == media, "Aweme paid-content series identity is validated when collection detail is absent")
        rejects("conflicting paid-content series", kind: .missing) {
            _ = try decode(video([videoRow(paid: ["paid_collection_id": seriesNumber + 1])]))
        }
        for key in ["is_partial_preview", "should_show_preview", "is_paid_video_encrypted"] {
            rejects("JSON paid-content \(key)", kind: .locked) {
                _ = try decode(video([videoRow(paid: ["paid_collection_id": seriesNumber, key: true])]))
            }
        }
        rejects("JSON token-required video", kind: .locked) { _ = try decode(video([videoRow(token: true)])) }
        for url in ["https://user:password@media.example/episode.mp4", "javascript:alert(1)",
                    "https://media.example/episode.mp4#fragment", "file:///tmp/episode.mp4",
                    "https://media.example", "https://media.example:0/episode.mp4",
                    "https://media.example/metadata.json", "https://media.example/player.html",
                    "https://media.example/tiktok/md/collection/video/v1/",
                    "http://127.0.0.1:8768/media/episode.mp4"] {
            rejects("unsafe/non-media URL \(url)", kind: .unavailable) { _ = try decode(video([videoRow(url: url)])) }
        }
        let local = "http://127.0.0.1:8768/media/episode-03.mp4"
        check(try decode(video([videoRow(url: local)]), loopback: true).url.absoluteString == local, "Loopback media requires the explicit fixture flag")
        var alternate = videoRow()
        var alternateAweme = alternate["aweme"] as! [String: Any]
        alternateAweme["video"] = ["play_addr": ["url_list": ["javascript:invalid"]],
                                    "play_addr_h264": ["url_list": [media]]]
        alternate["aweme"] = alternateAweme
        check(try decode(video([alternate])).url.absoluteString == media, "JSON filters invalid candidates and supports the H264 address")
        let prefixed = Data(" \n\t".utf8) + (try video([videoRow()]))
        check(try PineDramaProvider.decodeVideo(prefixed, contentType: "application/x-protobuf", episode: episode).url.absoluteString == media,
              "JSON wire signature works even with a protobuf content type")
        rejects("oversized video response", kind: .invalid) { _ = try decode(Data(repeating: 0, count: 2 * 1024 * 1024 + 1)) }
    }

    // Minimal protobuf fixture writer; field numbers are the supplied native schema.
    static func varint(_ value: UInt64) -> Data {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value & 127)
            value >>= 7
            if value != 0 { byte |= 128 }
            bytes.append(byte)
        } while value != 0
        return Data(bytes)
    }

    static func uint(_ field: Int, _ value: UInt64) -> Data { varint(UInt64(field) << 3) + varint(value) }
    static func bytes(_ field: Int, _ value: Data) -> Data { varint(UInt64(field) << 3 | 2) + varint(UInt64(value.count)) + value }
    static func string(_ field: Int, _ value: String) -> Data { bytes(field, Data(value.utf8)) }

    static func pbRow(id: UInt64 = 7_000_000_000_000_000_103, awemeID: String = "7000000000000000103",
                      sequence: UInt64 = 3, url: String = "https://media.example/episode-03.mp4",
                      paid: Data? = nil, token: Bool = false, intro: Bool = false,
                      addressField: Int = 1, extra: Data = Data()) -> Data {
        var video = bytes(addressField, string(2, url))
        if token { video += uint(24, 1) }
        var aweme = string(1, awemeID) + bytes(7, video)
        if let paid { aweme += bytes(317, paid) }
        var row = uint(1, id) + uint(12, sequence) + bytes(4, aweme)
        if intro { row += uint(5, 1) }
        return row + extra
    }

    static func pbResponse(_ rows: [Data], collection: UInt64? = 7_000_000_000_000_000_001,
                           status: UInt64 = 0, extra: Data = Data()) -> Data {
        var response = uint(1, status)
        for row in rows { response += bytes(2, row) }
        if let collection { response += bytes(14, uint(1, collection)) }
        return response + extra
    }

    static func testProtobufVideo() throws {
        // Independently generated from the schema, not serialized by the fixture writer above.
        let golden = Data(base64Encoded: "CAASTQjngPCdmd2/kmFgAyI/ChM3MDAwMDAwMDAwMDAwMDAwMTAzOigKJhIkaHR0cHM6Ly9tZWRpYS5leGFtcGxlL2VwaXNvZGUtMDMubXA0cgoIgYDwnZndv5Jh")!
        check(golden == pbResponse([pbRow()]), "Protobuf fixture matches the independent 93-byte golden")
        check(try decode(golden).url.absoluteString == media, "Protobuf golden resolves exact Int64 episode, series and sequence")
        let unknown = uint(80, 123) + varint(UInt64(81 << 3 | 1)) + Data(repeating: 9, count: 8)
            + bytes(82, Data("ignored".utf8)) + varint(UInt64(83 << 3 | 5)) + Data(repeating: 7, count: 4)
        check(try decode(pbResponse([pbRow(extra: unknown)], extra: unknown)).url.absoluteString == media,
              "Unknown varint, fixed64, bytes and fixed32 fields are skipped at nested and response levels")
        let wrong = pbRow(id: UInt64(episodeNumber + 1), awemeID: String(episodeNumber + 1), sequence: 4, url: "https://media.example/wrong-first.mp4")
        check(try decode(pbResponse([wrong, pbRow()])).url.absoluteString == media, "Protobuf selects the matching row instead of the first row")
        rejects("protobuf wrong episode ID", kind: .missing) { _ = try decode(pbResponse([wrong])) }
        rejects("protobuf wrong series", kind: .missing) { _ = try decode(pbResponse([pbRow()], collection: UInt64(seriesNumber + 1))) }
        rejects("protobuf wrong sequence", kind: .missing) { _ = try decode(pbResponse([pbRow(sequence: 4)])) }
        rejects("protobuf duplicate selected rows", kind: .missing) { _ = try decode(pbResponse([pbRow(), pbRow()])) }
        rejects("protobuf intro row", kind: .missing) { _ = try decode(pbResponse([pbRow(intro: true)])) }
        rejects("protobuf missing series identity", kind: .missing) { _ = try decode(pbResponse([pbRow()], collection: nil)) }
        rejects("protobuf service error", kind: .unavailable) { _ = try decode(pbResponse([pbRow()], status: 9)) }
        rejects("protobuf business error", kind: .unavailable) { _ = try decode(pbResponse([pbRow()], extra: uint(27, 5))) }
        for field in [7, 8, 17] {
            rejects("protobuf paid-content preview/encryption flag \(field)", kind: .locked) {
                _ = try decode(pbResponse([pbRow(paid: uint(1, UInt64(seriesNumber)) + uint(field, 1))]))
            }
        }
        rejects("protobuf token-required video", kind: .locked) { _ = try decode(pbResponse([pbRow(token: true)])) }
        rejects("protobuf conflicting paid-content series", kind: .missing) {
            _ = try decode(pbResponse([pbRow(paid: uint(1, UInt64(seriesNumber + 1)))]))
        }
        check(try decode(pbResponse([pbRow(paid: uint(1, UInt64(seriesNumber)))], collection: nil)).url.absoluteString == media,
              "Protobuf paid-content identity is checked without collection detail")
        check(try decode(pbResponse([pbRow(addressField: 18)])).url.absoluteString == media, "Protobuf H264 address field is supported")
        for url in ["https://user:password@media.example/episode.mp4", "javascript:alert(1)",
                    "https://media.example/episode.mp4#fragment"] {
            rejects("protobuf unsafe media URL \(url)", kind: .unavailable) { _ = try decode(pbResponse([pbRow(url: url)])) }
        }
        let malformed: [(String, Data)] = [
            ("unterminated tag", Data([0x80])),
            ("overflowing varint", Data([0x08]) + Data(repeating: 0x80, count: 9) + Data([0x02])),
            ("truncated nested payload", Data([0x12, 0x05, 0x08])),
            ("truncated fixed64", Data([0x09]) + Data(repeating: 0, count: 7)),
            ("truncated fixed32", Data([0x0d]) + Data(repeating: 0, count: 3)),
            ("zero field tag", Data([0])),
            ("unsupported group wire type", Data([0x0b])),
            ("duplicate known scalar", golden + uint(1, 0)),
            ("wrong known wire type", bytes(1, Data()) + bytes(2, pbRow())),
        ]
        for (name, data) in malformed {
            rejects("protobuf " + name, kind: .invalid) { _ = try decode(data) }
        }
        rejects("status-zero protobuf without video rows", kind: .missing) { _ = try decode(uint(1, 0)) }
    }

    static func testTransportIsolation() async throws {
        let transport = URLSessionConfiguration.ephemeral
        transport.protocolClasses = [AIDramaFixtureProtocol.self]
        transport.httpAdditionalHeaders = ["Cookie": "fixture_account=private", "Authorization": "fixture-account-header"]
        if let cookie = HTTPCookie(properties: [.domain: "127.0.0.1", .path: "/", .name: "fixture_account", .value: "private"]) {
            transport.httpCookieStorage?.setCookie(cookie)
        }
        let supplied = URLSession(configuration: transport)
        defer { supplied.invalidateAndCancel() }
        AIDramaFixtureProtocol.reset()
        let provider = PineDramaProvider(configuration: .init(baseURL: URL(string: "http://127.0.0.1:8768")!,
            commonParameters: ["fixture": "provider-test", "language": "vi"], allowLoopbackHTTP: true,
            userAgent: "AIDramaProviderTests/fixture"), session: supplied)
        let page = try await provider.discover(cursor: nil)
        check(page.series.first?.id == String(seriesNumber), "Injected loopback provider decodes fixture data through URLSession")
        let requests = AIDramaFixtureProtocol.captured()
        check(requests.count == 1 && requests[0].url?.host == "127.0.0.1", "URLProtocol fixture handles the only API request without external networking")
        let request = requests[0]
        check(!request.httpShouldHandleCookies && request.value(forHTTPHeaderField: "Cookie") == nil,
              "API request disables cookie handling and strips inherited account cookies")
        check(request.value(forHTTPHeaderField: "Authorization") == nil, "API request strips inherited account authorization")
        check(request.value(forHTTPHeaderField: "User-Agent") == "AIDramaProviderTests/fixture", "API request uses its configured provider user agent")
        for base in ["http://127.0.0.1:8768", "http://api.fixture.example", "https://user:password@api.fixture.example", "https://api.fixture.example#fragment"] {
            let denied = PineDramaProvider(configuration: .init(baseURL: URL(string: base)!, commonParameters: [:]), session: supplied)
            await rejectsAsync("unpermitted API base \(base)", kind: .invalid) { _ = try await denied.discover(cursor: nil) }
        }
        check(AIDramaFixtureProtocol.captured().count == 1, "Rejected API bases never reach the network transport")
    }

    static func main() async throws {
        try testCatalog()
        try testPlaylist()
        try testJSONVideo()
        try testProtobufVideo()
        try await testTransportIsolation()
        print("All AI drama provider regressions passed")
    }
}

/// Captures all requests; even a transport regression cannot contact a real host.
private final class AIDramaFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        Self.lock.unlock()
        let body = Data(#"{"status_code":0,"collections":[{"collection_id":7000000000000000001,"title":"Transport fixture","num_videos":40}],"has_more":false}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                      headerFields: ["Content-Type": "application/json", "Set-Cookie": "fixture_response=ignored; Path=/"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    static func reset() { lock.lock(); defer { lock.unlock() }; requests = [] }
    static func captured() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
}
