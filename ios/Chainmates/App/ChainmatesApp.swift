import SwiftUI

@main
struct ChainmatesApp: App {
    var body: some Scene {
        WindowGroup {
            AppWindow()
        }
        .commands { AppCommands() }
    }
}

/// One window. Each has its own model (its own tab, sheet and game on screen), so two windows
/// on an iPad or the unfolded iPhone Duo don't mirror each other; saves are shared through
/// `Store`, and a window reloads stats when it comes to the front.
private struct AppWindow: View {
    @State private var app = AppModel()

    var body: some View {
        RootView()
            .environment(app)
            .focusedSceneValue(\.appModel, app)
            .task {
                if DebugLaunch.resetRequested { Store.resetAll() }
                await app.start()
                await DebugLaunch.apply(to: app)
            }
    }
}
