import SwiftUI

@main
struct AnyAnimeApp: App {
    @StateObject private var service = AnimeService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(service)
                .preferredColorScheme(.dark)
        }
    }
}

