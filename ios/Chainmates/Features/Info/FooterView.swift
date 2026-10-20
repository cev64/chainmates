import SwiftUI

/// The web footer, for the bottom of scrolling pages: the two-link mark, Privacy / Terms /
/// Support / About, the disclaimer and the data credit.
struct FooterView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let _ = dynamicTypeSize  // re-run when Dynamic Type changes (Theme fonts scale at call time)
        VStack(spacing: 4) {
            Rule().padding(.bottom, 18)
            FooterMark().padding(.bottom, 10)
            WrapLayout(hSpacing: 14, vSpacing: 0) {
                link("Privacy", AppConfig.privacyURL)
                link("Terms", AppConfig.termsURL)
                link("Support", AppConfig.supportURL)
                Button { app.sheet = .about } label: {
                    Text("About")
                        .font(Theme.body(13.5, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.ink2)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Text(app.sport.disclaimer)
                .font(Theme.body(12.5, .regular, relativeTo: .caption))
                .foregroundStyle(Theme.ink3)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
            Link(destination: app.sport.attributionURL) {
                Text(app.sport.attributionText)
                    .font(Theme.body(12.5, .regular, relativeTo: .caption))
                    .underline()
                    .foregroundStyle(Theme.ink3)
                    .frame(minHeight: 44)
            }
        }
        .multilineTextAlignment(.center)
        .contentColumn()
        .padding(.top, 22)
        .padding(.bottom, 30)
    }

    private func link(_ title: String, _ url: URL) -> some View {
        Link(destination: url) {
            Text(title)
                .font(Theme.body(13.5, .semibold, relativeTo: .footnote))
                .foregroundStyle(Theme.ink2)
                .frame(minHeight: 44)
        }
    }
}

/// 48 x 20 outlined two-link mark in `rule-2`.
private struct FooterMark: View {
    var body: some View {
        Canvas { ctx, _ in
            let style = StrokeStyle(lineWidth: 3)
            ctx.stroke(Path(roundedRect: CGRect(x: 2, y: 3, width: 26, height: 14), cornerRadius: 7), with: .color(Theme.rule2), style: style)
            ctx.stroke(Path(roundedRect: CGRect(x: 20, y: 3, width: 26, height: 14), cornerRadius: 7), with: .color(Theme.rule2), style: style)
        }
        .frame(width: 48, height: 20)
        .accessibilityHidden(true)
    }
}

#Preview("Footer") {
    ScrollView { FooterView() }.environment(AppModel()).paperBackground()
}
