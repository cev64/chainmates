import Foundation

/// Launch settings for screenshots and checks, Debug builds only (App Review 2.5.19: nothing
/// hidden ships). For example:
///
///     SIMCTL_CHILD_CM_TAB=archive xcrun simctl launch booted com.cev64.chainmates
///
/// - `CM_TAB`: today, archive or stats.
/// - `CM_SHEET`: help, about or results.
/// - `CM_PUZZLE`: a puzzle number to open (practice unless it's today's).
/// - `CM_MOVES`: comma-separated player ids to guess on launch.
/// - `CM_RESET=1`: erase local data first.
/// - `CM_THEME`: light or dark.
enum DebugLaunch {
    @MainActor
    static func apply(to app: AppModel) async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let n = env["CM_PUZZLE"].flatMap(Int.init) { app.open(n) }
        if let moves = env["CM_MOVES"], let session = app.session {
            // Wait for the session to restore its state.
            for _ in 0..<50 where session.state == nil { try? await Task.sleep(for: .milliseconds(50)) }
            for id in moves.split(separator: ",").map(String.init) {
                await app.loadPlayers([id])
                if let p = app.cachedPlayer(id) { await session.guess(p) }
            }
        }
        if let theme = env["CM_THEME"].flatMap(ThemePreference.init(rawValue:)) { app.theme = theme }
        switch env["CM_TAB"] {
        case "archive": app.route = .archive
        case "stats": app.route = .stats
        default: break
        }
        if let sheet = env["CM_SHEET"].flatMap(AppModel.Sheet.init(rawValue:)) {
            app.sheet = sheet
        } else if env["CM_TAB"] != nil || env["CM_PUZZLE"] != nil {
            // A screenshot run shouldn't be covered by the first-launch help.
            if app.sheet == .help { app.sheet = nil }
        }
        #endif
    }

    static var resetRequested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["CM_RESET"] == "1"
        #else
        false
        #endif
    }
}
