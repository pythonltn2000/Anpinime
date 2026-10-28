import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main struct RangeProbeTests {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        let root = URL(string: "http://127.0.0.1:8766")!
        let first = try await Phim4KMediaProbe().inspect(root.appendingPathComponent("range"), headers: [:], configuration: config)
        assert(first.response.statusCode == 206)
        assert(first.response.value(forHTTPHeaderField: "Content-Range") == "bytes 0-2047/12285989889")
        assert(first.prefix.count == 2048 && first.prefix[4...7].elementsEqual(Data("ftyp".utf8)))
        let ignored = try await Phim4KMediaProbe().inspect(root.appendingPathComponent("ignore"), headers: [:], configuration: config)
        assert(ignored.response.statusCode == 200 && ignored.prefix.count == 2048 && ignored.wasTruncated)
        let redirected = try await Phim4KMediaProbe().inspect(root.appendingPathComponent("redirect"), headers: [:], configuration: config)
        assert(redirected.response.statusCode == 206 && redirected.prefix.count == 2048)
        let denied = try await Phim4KMediaProbe().inspect(root.appendingPathComponent("denied"), headers: [:], configuration: config)
        assert(denied.response.statusCode == 403)
        let json = try await Phim4KMediaProbe().inspect(root.appendingPathComponent("json"), headers: [:], configuration: config)
        assert(json.response.statusCode == 200 && String(data: json.prefix, encoding: .utf8)?.hasPrefix("{") == true)
        print("PASS: bounded GET against virtual 12 GB resource, 206/200/redirect/403/JSON")
    }
}
