import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main struct RangeProbeTests {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        guard let port = Int(ProcessInfo.processInfo.environment["ANPINIME_RANGE_PORT"] ?? "8766"), (1...65535).contains(port) else {
            fatalError("Invalid ANPINIME_RANGE_PORT for the local fixture")
        }
        let root = URL(string: "http://127.0.0.1:\(port)")!
        func inspect(_ path: String) async throws -> Phim4KMediaProbe.Result {
            func log(_ message: String) { FileHandle.standardError.write(Data(("RANGE: " + message + "\n").utf8)) }
            log("request path=\(path) port=\(port)")
            do {
                let result = try await Phim4KMediaProbe().inspect(root.appendingPathComponent(path), headers: [:], configuration: config, allowLoopbackHTTP: true)
                log("response path=\(path) status=\(result.response.statusCode) bytes=\(result.prefix.count) truncated=\(result.wasTruncated)")
                return result
            } catch {
                log("failure path=\(path) code=\((error as NSError).code)")
                throw error
            }
        }
        let first = try await inspect("range")
        assert(first.response.statusCode == 206)
        assert(first.response.value(forHTTPHeaderField: "Content-Range") == "bytes 0-2047/12285989889")
        assert(first.prefix.count == 2048 && first.prefix[4...7].elementsEqual(Data("ftyp".utf8)))
        let ignored = try await inspect("ignore")
        assert(ignored.response.statusCode == 200 && ignored.prefix.count == 2048 && ignored.wasTruncated)
        let redirected = try await inspect("redirect")
        assert(redirected.response.statusCode == 206 && redirected.prefix.count == 2048)
        assert(redirected.response.url?.lastPathComponent == "range")
        let denied = try await inspect("denied")
        assert(denied.response.statusCode == 403)
        let json = try await inspect("json")
        assert(json.response.statusCode == 200 && String(data: json.prefix, encoding: .utf8)?.hasPrefix("{") == true)
        print("PASS: bounded GET against virtual 12 GB resource, 206/200/redirect/403/JSON")
    }
}
