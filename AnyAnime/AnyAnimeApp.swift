import SwiftUI

@main
struct AnyAnimeApp: App {
    @StateObject private var service = AnimeService()

    var body: some Scene {
        WindowGroup {
            appContent.environmentObject(service).preferredColorScheme(.dark)
        }
    }

    @ViewBuilder private var appContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-preview") {
            InterfacePreview()
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}
