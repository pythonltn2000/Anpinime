import SwiftUI

@main
struct AnyAnimeApp: App {
    @UIApplicationDelegateAdaptor(AnPinimeAppDelegate.self) private var appDelegate
    @StateObject private var service = AnimeService()

    var body: some Scene {
        WindowGroup {
            appContent.environmentObject(service).preferredColorScheme(.dark)
        }
    }

    @ViewBuilder private var appContent: some View {
        #if DEBUG
        if PlaybackSmokeTest.enabled {
            PlaybackSmokeView()
        } else if ProcessInfo.processInfo.arguments.contains("--ui-preview") {
            InterfacePreview()
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}
