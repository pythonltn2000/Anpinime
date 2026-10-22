import SwiftUI

@main
struct AnyAnimeApp: App {
    @StateObject private var browser = AnimeBrowserModel()

    var body: some Scene {
        WindowGroup {
            BrowserScreen()
                .environmentObject(browser)
        }
    }
}
