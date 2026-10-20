#if DEBUG
import SwiftUI
import UIKit

/// Debug-only: a stand-in root that shows the game screen before the shell is wired, and
/// launch-environment hooks that set up a board for screenshots:
///
///     SIMCTL_CHILD_CM_RESET=1          forget saved games and stats first
///     SIMCTL_CHILD_CM_MODE=easy        the preferred mode for new games
///     SIMCTL_CHILD_CM_MOVES="Puka Nacua;Tom Brady"   guesses, each the top search match
///     SIMCTL_CHILD_CM_HINT=1           buy a hint after the moves
///     SIMCTL_CHILD_CM_QUERY=ga         type into the guess field (and focus it)
///     SIMCTL_CHILD_CM_FOCUS=1          focus the guess field
///     SIMCTL_CHILD_CM_LANDSCAPE=1      ask the window scene for landscape (refused in iPadOS windowing)
///     SIMCTL_CHILD_CM_FRAME_H=760      confine the screen to this height (a landscape-shaped box)
enum GameDebug {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }
    static var frameHeight: CGFloat? { env["CM_FRAME_H"].flatMap(Double.init).map { CGFloat($0) } }
    static var focusField: Bool { env["CM_FOCUS"] == "1" || env["CM_QUERY"] != nil }

    /// Runs before `AppModel.start()`.
    static func prepare() {
        let defaults = UserDefaults.standard
        if env["CM_RESET"] == "1" {
            for k in defaults.dictionaryRepresentation().keys where k.hasPrefix("chainmates.") && k != "chainmates.theme" {
                defaults.removeObject(forKey: k)
            }
        }
        if let m = env["CM_MODE"].flatMap(GameMode.init(rawValue:)) { Store.preferredMode = m }
        Store.seenHelp = true
    }

    /// Runs after `AppModel.start()`: plays the scripted moves on today's game.
    @MainActor
    static func play(_ app: AppModel) async {
        for _ in 0..<100 where app.session?.state == nil { try? await Task.sleep(for: .milliseconds(50)) }
        guard let session = app.session, session.state != nil else { return }
        let moves = (env["CM_MOVES"] ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        for name in moves where !name.isEmpty {
            try? await Task.sleep(for: .milliseconds(900))
            guard let p = await session.search(name).first else { continue }
            await session.guess(p)
        }
        if env["CM_HINT"] == "1" {
            try? await Task.sleep(for: .milliseconds(900))
            await session.buyHint()
        }
        if let q = env["CM_QUERY"] {
            try? await Task.sleep(for: .milliseconds(700))
            session.draft = q
        }
        app.sheet = nil
    }

    @MainActor
    static func orient() {
        guard env["CM_LANDSCAPE"] == "1" else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
                print("CM_LANDSCAPE refused:", error.localizedDescription)
            }
        }
    }
}

/// The temporary root: today's game in a navigation stack, like the shell will host it.
struct GameDebugRoot: View {
    @State private var app = AppModel()

    var body: some View {
        NavigationStack {
            GameScreen()
                .paperBackground()
                .navigationTitle("chainmates")
                .navigationBarTitleDisplayMode(.inline)
        }
        .overlay { ToastOverlay() }
        .frame(height: GameDebug.frameHeight)
        .overlay(alignment: .bottom) {
            if GameDebug.frameHeight != nil { Rectangle().fill(.red).frame(height: 1) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .environment(app)
        .preferredColorScheme(app.theme.colorScheme)
        .task {
            GameDebug.prepare()
            await app.start()
            GameDebug.orient()
            app.sheet = nil
            await GameDebug.play(app)
        }
    }
}
#endif
