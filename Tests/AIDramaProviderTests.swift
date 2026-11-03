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
        check(page.hasMore, "Catalog retains native has_more independently of the cursor")
        let home = try PineDramaProvider.decodeCatalog(json(["status_code": 0, "collections": [row], "has_more": true, "cursor": ""]))
        check(home.hasMore && home.nextCursor == nil, "Home recommendation continuation does not fabricate a cursor")
        let terminal = try PineDramaProvider.decodeCatalog(json(["status_code": 0, "collections": [], "has_more": false]))
        check(terminal.series.isEmpty && !terminal.hasMore && terminal.nextCursor == nil, "Empty terminal catalog page is valid")
        rejects("empty catalog without explicit pagination envelope", kind: .invalid) {
            _ = try PineDramaProvider.decodeCatalog(json(["status_code": 0, "collections": []]))
        }
        var enriched = row
        enriched["num_watched"] = 17_206_503
        enriched["categories"] = "Truy thê, Tình thân"
        let rich = try PineDramaProvider.decodeCatalog(catalog([enriched])).series[0]
        check(rich.viewCount == 17_206_503 && rich.genreText == "Truy thê, Tình thân", "Card metadata comes from native view count and category text")
        let oldHistory = Data(#"{"id":"7000000000000000001","title":"Existing history","summary":"","episodeCount":40}"#.utf8)
        let restored = try JSONDecoder().decode(AIDramaSeries.self, from: oldHistory)
        check(restored.genreText.isEmpty && restored.viewCount == nil, "Existing saved series decode when newer card metadata is absent")
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

    static func filterLists() -> [[String: Any]] {
        [
            ["category_filters": [["filter_type": 1, "category_id": "0", "name": "Tất cả bối cảnh", "name_en": "all_settings"],
                                   ["filter_type": 2, "category_id": "7628991192537158672", "name": "Kỳ ảo", "name_en": "fantasy"]]],
            ["category_filters": [["filter_type": 1, "category_id": "0", "name": "Tất cả nhân vật", "name_en": "all_characters"],
                                   ["filter_type": 2, "category_id": "7628991193891820560", "name": "Phục thù", "name_en": "revenge"]]],
            ["category_filters": [["filter_type": 1, "category_id": "0", "name": "Tất cả câu chuyện", "name_en": "all_stories"],
                                   ["filter_type": 2, "category_id": "7628991193543840769", "name": "Cơ hội thứ hai", "name_en": "second_chance"]]],
            ["category_filters": [["filter_type": 1, "category_id": "0", "name": "Tất cả tác phẩm", "name_en": "all_releases"],
                                   ["filter_type": 3, "category_id": "", "name": "Trong 7 ngày", "name_en": "in_7_days", "recent_days": 7],
                                   ["filter_type": 3, "category_id": "", "name": "Trong 30 ngày", "name_en": "in_30_days", "recent_days": 30]]]
        ]
    }

    static func testLibraryContracts() throws {
        for (query, scene) in [(AIDramaCatalogQuery.trending(.hot), "6"), (.trending(.latest), "7"), (.newWorks, "8")] {
            let plan = try PineDramaProvider.catalogRequest(query: query, cursor: "1:16:12")
            check(plan.path == "mini_drama_center/v1/" && plan.body == nil && plan.parameters["scene"] == scene,
                  "Library route uses original scene \(scene) through GET")
            check(plan.parameters["cursor"] == "1:16:12", "Library scene \(scene) forwards the server cursor unchanged")
        }
        let loaded = (1...35).map { String(seriesNumber + Int64($0)) }
        let home = try PineDramaProvider.catalogRequest(query: .home, cursor: nil, loadedSeriesIDs: loaded)
        check(home.parameters["drama_request_type"] == "load_more" && home.parameters["drama_current_collections"] == loaded.suffix(20).joined(separator: ","),
              "Home continuation carries the last 20 actual loaded collection identities")
        check(home.parameters["collection_count_in_session"] == "35" && home.parameters["cursor"] == "" && home.parameters["request_count_in_session"] == nil,
              "Home uses actual loaded count without fabricating a session ID or cursor")
        let initial = try PineDramaProvider.catalogRequest(query: .home, cursor: nil)
        check(initial.parameters["drama_request_type"] == "init_fetch" && initial.parameters["collection_count_in_session"] == "0", "Home refresh starts a new actual recommendation state")
        let selection = AIDramaCategorySelection(backgroundID: "7628991192537158672", characterID: "7628991193891820560",
                                                 storyID: "7628991193543840769", recentDays: 7)
        let filtered = try PineDramaProvider.catalogRequest(query: .categories(selection), cursor: "1:14")
        let object = try JSONSerialization.jsonObject(with: filtered.body!) as! [String: Any]
        let filters = object["category_filters"] as! [[String: Any]]
        check(filtered.path == "mini_drama/category_filter/v1/" && filtered.parameters.isEmpty && filters.count == 4,
              "Four selected groups use original POST JSON category endpoint")
        check(filters.prefix(3).map { $0["category_id"] as! String } == [selection.backgroundID!, selection.characterID!, selection.storyID!] &&
              filters.prefix(3).allSatisfy { ($0["filter_type"] as? Int) == 2 }, "All three exact native category IDs remain separate filters")
        check((filters[3]["filter_type"] as? Int) == 3 && (filters[3]["recent_days"] as? Int) == 7 && object["cursor"] as? String == "1:14",
              "Time window uses native recent_days filter and exact next cursor")
        let metadata = try PineDramaProvider.decodeCatalogMetadata(json(["status_code": 0, "category_filter_lists": filterLists()]))
        check(metadata.filterGroups.map(\.kind) == [.background, .character, .story, .releaseTime], "Service metadata supplies all four filter groups in order")
        check(metadata.filterGroups[0].options[1].categoryID == selection.backgroundID && metadata.filterGroups[3].options.map(\.recentDays) == [nil, 7, 30],
              "Metadata preserves the server category IDs and release windows")
        check(metadata.filterGroups.allSatisfy { $0.options.first?.id == "all" && $0.options.first?.categoryID == nil }, "All choices clear their group without inventing a category ID")
        rejects("incomplete four-group metadata", kind: .invalid) {
            _ = try PineDramaProvider.decodeCatalogMetadata(json(["status_code": 0, "category_filter_lists": Array(filterLists().dropLast())]))
        }
        rejects("unsupported time window", kind: .invalid) {
            _ = try PineDramaProvider.catalogRequest(query: .categories(.init(recentDays: 365)), cursor: nil)
        }
        rejects("invalid loaded home identity", kind: .invalid) {
            _ = try PineDramaProvider.catalogRequest(query: .home, cursor: nil, loadedSeriesIDs: ["invented"])
        }
        rejects("duplicate loaded home identity", kind: .invalid) {
            _ = try PineDramaProvider.catalogRequest(query: .home, cursor: nil, loadedSeriesIDs: [series.id, series.id])
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
        var contradictory = videoRow()
        var contradictoryAweme = contradictory["aweme"] as! [String: Any]
        contradictoryAweme["aweme_id"] = String(episodeNumber + 1)
        contradictory["aweme"] = contradictoryAweme
        rejects("JSON contradictory paid-video and aweme identities", kind: .missing) { _ = try decode(video([contradictory])) }
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
        rejects("protobuf contradictory paid-video and aweme identities", kind: .missing) {
            _ = try decode(pbResponse([pbRow(awemeID: String(episodeNumber + 1))]))
        }
        rejects("protobuf paid-content episode differs from selected video", kind: .missing) {
            _ = try decode(pbResponse([pbRow(paid: uint(1, UInt64(seriesNumber)) + uint(6, UInt64(episodeNumber + 1)))]))
        }
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
        _ = try await provider.catalog(query: .trending(.hot), cursor: "1:16:12")
        _ = try await provider.catalog(query: .trending(.latest), cursor: nil)
        _ = try await provider.catalog(query: .newWorks, cursor: nil)
        _ = try await provider.catalog(query: .categories(.init(recentDays: 7)), cursor: "1:14")
        let metadata = try await provider.catalogMetadata()
        check(metadata.filterGroups.count == 4 && AIDramaFixtureProtocol.captured().count == 6, "Category reply caches native metadata without another request")
        let library = Array(AIDramaFixtureProtocol.captured().dropFirst())
        check(library.prefix(3).allSatisfy { $0.httpMethod == "GET" }, "Both ranking lists and new works use GET transport")
        let category = library[4]
        check(category.httpMethod == "POST" && category.value(forHTTPHeaderField: "Content-Type") == "application/json" && category.value(forHTTPHeaderField: "Agw-Js-Conv") == "str",
              "Category transport uses original JSON POST and conversion header")
        guard let categoryBody = category.httpBody else { throw URLError(.requestBodyStreamExhausted) }
        let body = try JSONSerialization.jsonObject(with: categoryBody) as! [String: Any]
        let rawFilters = body["category_filters"] as! [[String: Any]]
        check(rawFilters.count == 4 && rawFilters[0]["name_en"] as? String == "all_settings" &&
              rawFilters[3]["name_en"] as? String == "in_7_days", "Category requests preserve whole native selected objects and each unselected All object")
        check(library.allSatisfy { !$0.httpShouldHandleCookies && $0.value(forHTTPHeaderField: "Cookie") == nil && $0.value(forHTTPHeaderField: "Authorization") == nil },
              "All new library routes preserve account-free transport isolation")
    }

    static func testShortFeed() throws {
        let paid = uint(1, 7_000_000_000_000_000_001) + uint(3, 3)
            + bytes(13, Data("Phim ngắn thật".utf8)) + bytes(26, Data("Kỳ ảo".utf8))
            + bytes(31, Data("{\"video_total_nums\":40}".utf8))
        let aweme = bytes(1, Data(episode.id.utf8)) + bytes(317, paid) + bytes(7, uint(4, 1280) + uint(3, 720))
        let page = try PineDramaProvider.decodeShortFeed(uint(1, 0) + uint(3, 1) + bytes(4, aweme) + bytes(4, aweme) + bytes(4, bytes(1, Data("999".utf8))))
        check(page.videos.count == 1 && page.hasMore, "Native feed skips non-series rows and duplicate video IDs")
        check(page.videos[0].series.id == series.id && page.videos[0].series.episodeCount == 40 && page.videos[0].episode.id == episode.id,
              "Feed keeps exact series/video identities and native total independently of ranking catalogs")
        check(page.videos[0].episode.number == 3 && page.videos[0].isLandscape, "Landscape recommendation keeps the actual episode number")
        let intro = bytes(1, Data(episode.id.utf8)) + bytes(317, paid + uint(5, 1))
        check(try PineDramaProvider.decodeShortFeed(uint(1, 0) + uint(3, 0) + bytes(4, intro)).videos.isEmpty,
              "Feed introduction is not substituted for a numbered episode")
        rejects("feed service refusal", kind: .unavailable) { _ = try PineDramaProvider.decodeShortFeed(uint(1, 9)) }
        rejects("truncated feed protobuf", kind: .invalid) { _ = try PineDramaProvider.decodeShortFeed(Data([0x22, 0xff])) }
    }

    static func main() async throws {
        try testShortFeed()
        try testCatalog()
        try testLibraryContracts()
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
        // URLSession can expose a Data POST body as a stream to URLProtocol.
        // Snapshot those actual bytes before inspecting the captured request.
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count == 0 { break }
                guard count > 0, data.count + count <= 2 * 1024 * 1024 else {
                    client?.urlProtocol(self, didFailWithError: URLError(.requestBodyStreamExhausted))
                    return
                }
                data.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBodyStream = nil
            captured.httpBody = data
        }
        Self.lock.lock()
        Self.requests.append(captured)
        Self.lock.unlock()
        var object: [String: Any] = ["status_code": 0, "collections": [["collection_id": AIDramaProviderTests.seriesNumber, "title": "Transport fixture", "num_videos": 40]], "has_more": false]
        if request.url?.path.contains("category_filter") == true { object["category_filter_lists"] = AIDramaProviderTests.filterLists() }
        let body = try! JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                      headerFields: ["Content-Type": "application/json", "Set-Cookie": "fixture_response=ignored; Path=/"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    static func reset() { lock.lock(); defer { lock.unlock() }; requests = [] }
    static func captured() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
}
