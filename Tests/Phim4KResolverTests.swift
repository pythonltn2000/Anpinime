import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main struct Phim4KResolverTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        print("PASS: " + message)
    }

    static func main() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/phim4k-protocol-vectors.json"))
        let fixture = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for vector in fixture["vectors"] as! [[String: Any]] {
            let actual = try Phim4KVIPResolver.gatewayURL(fileID: vector["fileID"] as! String,
                gateway: URL(string: vector["gateway"] as! String)!,
                timestamp: (vector["timestamp"] as! NSNumber).uint32Value, seed: vector["seed"] as! String)
            check(actual.absoluteString == vector["expected"] as! String,
                  "Traced AES-GCM/HMAC/uint32BE protocol matches non-secret reference vector")
        }
        check(Phim4KVIPResolver.clientMaterialFingerprint == "dae26b5d01bd01fde70f6d3f5f1a03f32a77da4cc9f38578f1ec92b33405db53",
              "Client material matches the independent original-IPA recovery fingerprint")
        let virtual = URL(string: "https://cdn.phim4k.lol/original-file.mkv?unused=fixture")!
        check(Phim4KVIPResolver.requiresGateway(virtual), "Original virtual Core CDN uses gateway exchange")
        check(Phim4KVIPResolver.extractFileID(from: virtual) == "original-file.mkv", "Original pathSegments.last preserves a file extension")
        for raw in ["https://sf.phim4k.space/api/content/stream/hls", "https://sv.p4kzz.workers.dev/media", "https://cdn.phim4k.lol.attacker.test/id", "https://user:password@cdn.phim4k.lol/id", "https://cdn.phim4k.lol:8443/id"] {
            check(!Phim4KVIPResolver.requiresGateway(URL(string: raw)!), "Free, resolved, credential-bearing and lookalike URLs are not treated as virtual Core handles")
        }
        for raw in ["http://insecure.example", "https://gateway.example/?token=fixture", "https://user:password@gateway.example", "file:///tmp/gateway"] {
            do {
                _ = try Phim4KVIPResolver.gatewayURL(fileID: "fixture", gateway: URL(string: raw)!, timestamp: 1, seed: "fixture-seed")
                fatalError("Invalid gateway accepted")
            } catch { }
        }
        for fileID in ["", ".", "..", "../other", "file?token=fixture", "file#fragment"] {
            do {
                _ = try Phim4KVIPResolver.gatewayURL(fileID: fileID, gateway: URL(string: "https://gateway.example")!, timestamp: 1, seed: "fixture-seed")
                fatalError("Invalid file handle accepted")
            } catch { }
        }
        do {
            _ = try await Phim4KVIPResolver.shared.resolve(virtual, gateway: URL(string: "https://gateway.example")!, session: .shared,
                                                         now: Date(timeIntervalSince1970: -1))
            fatalError("Invalid clock accepted")
        } catch { }
        print("All source-2 protocol regressions passed")
    }
}
