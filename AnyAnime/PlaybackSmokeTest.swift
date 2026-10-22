#if DEBUG
import SwiftUI

enum PlaybackSmokeTest {
    static var enabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--playback-smoke") || webOnly
    }
    static var webOnly: Bool { ProcessInfo.processInfo.arguments.contains("--web-playback-smoke") }
    @MainActor static func record(time: Double, backend: String, size: CGSize) {
        guard enabled, time > 1, size.width > size.height else { return }
        let result: [String: Any] = ["time": time, "backend": backend, "landscape": true,
                                     "width": size.width, "height": size.height]
        if let data = try? JSONSerialization.data(withJSONObject: result),
           let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: directory.appendingPathComponent("playback-\(backend).json"), options: .atomic)
        }
    }
}

struct PlaybackSmokeView: View {
    private let episode = Episode(title: "Tập kiểm thử", url: URL(string: "http://127.0.0.1:8765/episode.html")!, number: 1, season: "Phần 1")
    var body: some View {
        PlayerView(episode: episode, title: "Kiểm thử phát video", artworkURL: nil, episodes: [episode])
    }
}
#endif
