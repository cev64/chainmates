import SwiftUI

/// The app's frame: one `TabView` (Today, Archive, Stats) as a Liquid Glass tab bar everywhere,
/// never a sidebar. It sits along the bottom on iPhone and across the top on an iPad or the
/// unfolded iPhone Duo, so the game always has the full width (on the unfolded Duo its two panes
/// meet at the fold). It's one view tree on every display, so folding or unfolding the Duo keeps
/// your place. Built with the iOS 27.1 SDK, the system moves the tab bar and toolbar into a
/// vertical bar on the folded Duo by itself.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.route) {
            Tab("Today", systemImage: "link", value: AppModel.Route.today) {
                NavigationStack { TodayTab() }
            }
            Tab("Archive", systemImage: "calendar", value: AppModel.Route.archive) {
                NavigationStack {
                    ready { ArchiveScreen() }
                        .navigationTitle("Archive")
                        .toolbarTitleDisplayMode(.inline)
                        // The page's own masthead carries the title, as on the site.
                        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
                        .modifier(CommonToolbar())
                }
            }
            Tab("Stats", systemImage: "chart.bar", value: AppModel.Route.stats) {
                NavigationStack {
                    ready { StatsScreen() }
                        .navigationTitle("Statistics")
                        .toolbarTitleDisplayMode(.inline)
                        // The page's own masthead carries the title, as on the site.
                        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
                        .modifier(CommonToolbar())
                }
            }
        }
        .tabViewStyle(.tabBarOnly)
        // Pinned across the top on an iPad or the unfolded Duo; on iPhone it tucks away while
        // you scroll, as system apps do.
        .tabBarMinimizeBehavior(sizeClass == .regular ? .never : .onScrollDown)
        .tint(Theme.accent)
        .sensoryFeedback(.selection, trigger: app.route)
        .sheet(item: $app.sheet) { sheet in
            switch sheet {
            case .help: HelpSheet()
            case .about: AboutSheet()
            case .results: ResultsSheet()
            }
        }
        // Above the tab bar, and on Today above the guess bar too.
        .overlay(alignment: .bottom) { ToastOverlay(bottomInset: app.route == .today ? 132 : 64) }
        .preferredColorScheme(app.theme.colorScheme)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await app.becameActive() } }
        }
    }

    /// The screen once data is loaded, or the loading / error status.
    @ViewBuilder
    private func ready(@ViewBuilder _ content: () -> some View) -> some View {
        switch app.phase {
        case .loading: StatusView(kind: .loading).paperBackground()
        case .failed(let message): StatusView(kind: .error(message)).paperBackground()
        case .ready: content()
        }
    }
}

/// Today: the game, or "Off day" when there's no puzzle for today's date.
private struct TodayTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            switch app.phase {
            case .loading: StatusView(kind: .loading)
            case .failed(let message): StatusView(kind: .error(message))
            case .ready:
                if app.session != nil { GameScreen() } else { StatusView(kind: .offDay) }
            }
        }
        .paperBackground()
        .toolbar {
            ToolbarItem(placement: .principal) { Masthead() }
        }
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle("Today")
        .modifier(CommonToolbar())
        .modifier(TaskOrientedBars())
    }
}

/// The site's brand block, as the Today bar's title: the mark, "chainmates", and
/// "Football · No. 8" (or "Practice, No. 5").
private struct Masthead: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        // Full brand block when the bar has room, then the wordmark alone, then the mark.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                BrandMark(size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    wordmark
                    HStack(spacing: 0) {
                        Text(app.sport.mode).fontWeight(.bold).foregroundStyle(Theme.accentInk)
                        Text(" · ").foregroundStyle(Theme.ink3)
                        Text(kicker).foregroundStyle(Theme.ink2)
                    }
                    .font(Theme.body(11, .medium, relativeTo: .caption))
                    .monospacedDigit()
                    .lineLimit(1)
                }
                .fixedSize()
            }
            HStack(spacing: 8) { BrandMark(size: 26); wordmark.fixedSize() }
            BrandMark(size: 26)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chainmates, \(app.sport.mode), \(kicker)")
        .accessibilityAddTraits(.isHeader)
    }

    private var wordmark: some View {
        Text("chainmates")
            .font(Theme.display(19, .bold, relativeTo: .headline))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
    }

    private var kicker: String {
        if let s = app.session { return s.isPractice ? "Practice, No. \(s.puzzle.n)" : "No. \(s.puzzle.n)" }
        return app.todayNumber > 0 ? "No. \(app.todayNumber)" : "Daily"
    }
}

/// Help, theme and About on every tab, each with a title and a symbol: the iPhone Duo's
/// vertical bar shows the symbol, and overflow shows the title.
private struct CommonToolbar: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("How to play", systemImage: "questionmark.circle") { app.sheet = .help }
            }
            ToolbarItem(placement: .topBarLeading) {
                // Theme and About share one menu so the bar keeps room for the masthead.
                Menu("Settings", systemImage: "gearshape") {
                    Picker(selection: themeBinding) {
                        Label("Automatic", systemImage: "circle.lefthalf.filled").tag(ThemePreference.automatic)
                        Label("Light", systemImage: "sun.max").tag(ThemePreference.light)
                        Label("Dark", systemImage: "moon").tag(ThemePreference.dark)
                    } label: {
                        Label("Theme", systemImage: themeSymbol)
                    }
                    .pickerStyle(.menu)
                    Button("About Chainmates", systemImage: "info.circle") { app.sheet = .about }
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    private var themeBinding: Binding<ThemePreference> {
        Binding(get: { app.theme }, set: { new in
            withAnimation(.easeInOut(duration: 0.25)) { app.theme = new }
            app.showToast(themeToast)
        })
    }

    private var themeSymbol: String {
        switch app.theme {
        case .automatic: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    private var themeToast: String {
        switch app.theme {
        case .automatic: "Theme follows your device"
        case .light: "Light theme"
        case .dark: "Dark theme"
        }
    }
}

/// On the folded iPhone Duo, Today is a task: keep its actions (Undo, Hint) in the vertical bar
/// and compress the tab bar instead (HIG, "Designing for iPhone Duo").
private struct TaskOrientedBars: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            content.toolbarVerticalCompressionBehavior(.prefersToolbarItems)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
