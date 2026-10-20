import SwiftUI

/// The web's toast, at the bottom of the screen: solid ink, paper text, radius 6, the lift shadow.
/// It slides up and fades in (a plain fade with Reduce Motion), never takes touches, and
/// VoiceOver announces it. Overlay it on the root: `.overlay { ToastOverlay() }`.
/// `bottomInset` is extra space above the safe area, for a tab bar the overlay can't see.
struct ToastOverlay: View {
    var bottomInset: CGFloat = 0
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if let toast = app.toast {
                ToastCard(toast: toast)
                    .id(toast.id)
                    .transition(reduceMotion
                        ? .opacity
                        : .asymmetric(insertion: .offset(y: 16).combined(with: .opacity),
                                      removal: .offset(y: 10).combined(with: .opacity)))
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12 + bottomInset)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion
                   ? .linear(duration: 0.15)
                   : (app.toast == nil ? .timingCurve(0.5, 0, 0.75, 0, duration: 0.18)
                                       : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)),
                   value: app.toast)
        .allowsHitTesting(false)
        .onChange(of: app.toast) { _, toast in
            guard let toast else { return }
            AccessibilityNotification.Announcement(toast.detail.map { "\(toast.text). \($0)" } ?? toast.text).post()
        }
    }
}

private struct ToastCard: View {
    let toast: AppModel.Toast
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lift = Theme.lift(scheme)
        VStack(alignment: .leading, spacing: 2) {
            Text(toast.text)
                .font(Theme.body(14, .medium, relativeTo: .subheadline))
            if let detail = toast.detail {
                Text(detail)
                    .font(Theme.body(12.5, .regular, relativeTo: .caption))
                    .opacity(0.72)
            }
        }
        .foregroundStyle(Theme.paper)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: 440, alignment: .leading)
        .background(Theme.ink, in: .rect(cornerRadius: Theme.radiusS))
        .shadow(color: lift.color, radius: lift.radius, x: 0, y: lift.y)
        // The announcement carries it to VoiceOver; reading the card as well would say it twice.
        .accessibilityHidden(true)
    }
}

#Preview("Toast") {
    let app = AppModel()
    app.toast = .init(text: "Hint revealed", detail: "2 downs left")
    return Theme.paper.ignoresSafeArea().overlay { ToastOverlay() }.environment(app)
}
