#if DEBUG
import SwiftUI

/// Deterministic simulator-only screenshots; never included in Release IPA.
struct InterfacePreview: View {
    static var mode: String { ProcessInfo.processInfo.arguments.last ?? "loading" }
    private let episodes = (1...24).map { (number: Int) -> Episode in
        Episode(title: "Tập \(number)", url: URL(string: "https://preview.invalid/phim/tap-\(number)")!, number: number, season: "Phần 1")
    }
    var body: some View {
        if Self.mode == "list" {
            LoadingView(text: "Đang tải danh sách anime…")
        } else if Self.mode == "app-settings" {
            NavigationView { AppSettingsView() }.tint(.anpinimeAccent)
        } else {
            PlayerView(episode: episodes[3], title: "Hành trình dưới bầu trời sao", artworkURL: nil, episodes: episodes)
        }
    }
}
#endif
