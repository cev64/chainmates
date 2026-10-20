import SwiftUI

/// The iPad menu bar (and keyboard shortcuts on any hardware keyboard): the same actions as the
/// toolbar, for the window in front.
struct AppCommands: Commands {
    @FocusedValue(\.appModel) private var app

    var body: some Commands {
        CommandMenu("Puzzle") {
            Button("Today's Puzzle") { app?.openToday() }
                .keyboardShortcut("t", modifiers: [.command])
            Button("Undo Link") { Task { await app?.session?.undo() } }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!(app?.session?.canUndo ?? false))
            Button("Hint") { Task { await app?.session?.buyHint() } }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(!(app?.session?.isPlaying ?? false))
            Divider()
            Button("Results") { app?.sheet = .results }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!(app?.session?.isOver ?? false))
        }
        CommandGroup(after: .sidebar) {
            Button("Archive") { app?.route = .archive }
                .keyboardShortcut("2", modifiers: [.command])
            Button("Statistics") { app?.route = .stats }
                .keyboardShortcut("3", modifiers: [.command])
        }
        CommandGroup(replacing: .help) {
            Button("How to Play") { app?.sheet = .help }
                .keyboardShortcut("?", modifiers: [.command])
            Button("About Chainmates") { app?.sheet = .about }
        }
    }
}

extension FocusedValues {
    @Entry var appModel: AppModel?
}

extension GameSession {
    var isPlaying: Bool { state?.view.status == .playing }
    var isOver: Bool { state?.view.isOver ?? false }
    var canUndo: Bool { isPlaying && (state?.view.chain.count ?? 0) > 1 }
}
