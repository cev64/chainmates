import SwiftUI

/// The status states of web spec 2.1: loading skeleton, "Chain snapped", "Off day".
/// The lead decides when to show it: `StatusView(kind: .loading)`.
struct StatusView: View {
    enum Kind {
        case loading
        case error(String)
        case offDay
    }

    let kind: Kind
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(kind: Kind) { self.kind = kind }

    var body: some View {
        let _ = dynamicTypeSize  // re-run when Dynamic Type changes (Theme fonts scale at call time)
        Group {
            switch kind {
            case .loading: skeleton
            case .error(let message): card(
                title: "Chain snapped", failed: true,
                strong: "We couldn't load the puzzle.",
                plain: "Check your connection and try again.",
                code: message, button: "Try again") {
                    Task { await app.start() }
                }
            case .offDay: card(
                title: "Off day", failed: false,
                strong: "There's no puzzle for today.",
                plain: "New puzzles are on the way. Older ones are in the archive.",
                code: nil, button: "Open the archive") {
                    app.route = .archive
                }
            }
        }
        .contentColumn()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Status card

    private func card(title: String, failed: Bool, strong: String, plain: String, code: String?,
                      button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            StatusArt().padding(.bottom, 4)
            Text(title)
                .font(Theme.display(34, .bold, relativeTo: .largeTitle))
                .foregroundStyle(failed ? Theme.bad : Theme.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(strong)
                .font(Theme.body(16, .semibold)).foregroundStyle(Theme.ink)
            Text(plain)
                .font(Theme.body(15)).foregroundStyle(Theme.ink2)
            if let code, !code.isEmpty {
                Text(code)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.ink3)
                    .textSelection(.enabled)
            }
            Button(button, action: action)
                .buttonStyle(.chain(.ink))
                .padding(.top, 12)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 8)
        .overlay(alignment: .top) { Rule.masthead }
        .overlay(alignment: .bottom) { Rule() }
        .padding(.top, 36)
        .infoRise(delay: 0, distance: 8)
        .accessibilityElement(children: .contain)
    }

    // MARK: Skeleton

    /// The static placeholder shapes (no shimmer, like the web), then the loading note.
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            bar(height: 12, fraction: 0.52)
            HStack(alignment: .top, spacing: 40) {
                column
                column
            }
            .padding(.top, 22).padding(.bottom, 18)
            Rectangle().fill(Theme.rule2).frame(height: 2).padding(.bottom, 18)
            bar(height: 44).padding(.bottom, 14)
            bar(height: 52).padding(.bottom, 14)
            bar(height: 44).padding(.bottom, 14)
            Text("Loading today's puzzle\u{2026}")
                .font(Theme.body(13)).foregroundStyle(Theme.ink3)
                .padding(.top, 6)
        }
        .padding(.top, 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading today's puzzle")
        .accessibilityAddTraits(.updatesFrequently)
        .transition(.opacity)
        .infoRise(delay: 0, distance: 0)
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 10) {
            bar(height: 28)
            bar(height: 12, fraction: 0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private func bar(height: CGFloat, fraction: CGFloat = 1) -> some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { g in
                    RoundedRectangle(cornerRadius: 4).fill(Theme.paper2)
                        .frame(width: g.size.width * fraction, height: height)
                }
            }
    }
}

#Preview("Loading") { StatusView(kind: .loading).environment(AppModel()).paperBackground() }
#Preview("Error") { StatusView(kind: .error("The Internet connection appears to be offline.")).environment(AppModel()).paperBackground() }
#Preview("Off day") { StatusView(kind: .offDay).environment(AppModel()).paperBackground() }
