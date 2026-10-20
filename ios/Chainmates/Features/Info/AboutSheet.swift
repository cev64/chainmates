import SwiftUI

/// About (web `aboutHTML`) plus what App Review and iOS users expect in settings: theme choice,
/// legal links that open in Safari, the version, font credit and "Reset all data".
/// Present with `app.sheet == .about`.
struct AboutSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmReset = false
    @State private var resetting = false

    private var sport: Sport { app.sport }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    private var seasonsRange: String? {
        guard let first = app.seasons.min(), let last = app.seasons.max() else { return nil }
        return first == last ? String(first) : "\(first)\u{2013}\(last)"
    }

    var body: some View {
        let _ = dynamicTypeSize  // re-run when Dynamic Type changes (Theme fonts scale at call time)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("About")
                        .font(Theme.display(28, .bold, relativeTo: .title))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 12)
                    Rule()
                    VStack(alignment: .leading, spacing: 12) {
                        InfoText.rich("**\(sport.title)** is a free daily teammate-chain puzzle. \(sport.tagline) You're playing the \(sport.mode) mode.", size: 15, color: Theme.ink2)
                        Text(sport.disclaimer)
                            .font(Theme.body(15)).foregroundStyle(Theme.ink2)
                        VStack(alignment: .leading, spacing: 0) {
                            Link(destination: sport.attributionURL) {
                                Text(sport.attributionText)
                                    .font(Theme.body(15, .semibold))
                                    .underline()
                                    .foregroundStyle(Theme.accentInk)
                                    .multilineTextAlignment(.leading)
                                    .frame(minHeight: 44, alignment: .leading)
                            }
                            Text("Teams appear as plain colour chips with their abbreviation; there are no logos or photos.")
                                .font(Theme.body(15)).foregroundStyle(Theme.ink2)
                        }
                        Text("No accounts, no ads, no tracking. Your games and stats are kept only on this device.")
                            .font(Theme.body(15)).foregroundStyle(Theme.ink2)
                    }
                    .lineSpacing(5)
                    .padding(.vertical, 14)
                    .infoRise(delay: 0.04)

                    appearance
                    legalLinks
                    finePrint
                    resetButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
        }
        .tint(Theme.accentInk)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .alert("Reset all data?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset all data", role: .destructive) {
                guard !resetting else { return }
                resetting = true
                Task {
                    await app.resetAllData()
                    dismiss()
                }
            }
        } message: {
            Text("This erases your games, stats and settings on this device. It can't be undone.")
        }
    }

    // MARK: Sections

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rule()
            Text("Appearance")
                .font(Theme.display(18, .bold, relativeTo: .headline))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 10)
            Picker("Appearance", selection: Binding(
                get: { app.theme },
                set: { new in withAnimation(.easeInOut(duration: 0.25)) { app.theme = new } }
            )) {
                ForEach(ThemePreference.allCases, id: \.self) { pref in
                    Text(label(pref)).tag(pref)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(minHeight: 44)
            .sensoryFeedback(.selection, trigger: app.theme)
            Text("Automatic follows your device.")
                .font(Theme.body(13)).foregroundStyle(Theme.ink3)
                .padding(.bottom, 14)
        }
    }

    private func label(_ pref: ThemePreference) -> String {
        switch pref {
        case .automatic: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    private var legalLinks: some View {
        VStack(spacing: 0) {
            legalRow("Privacy Policy", AppConfig.privacyURL)
            legalRow("Terms of Service", AppConfig.termsURL)
            legalRow("Support", AppConfig.supportURL)
            Rule()
        }
    }

    private func legalRow(_ title: String, _ url: URL) -> some View {
        VStack(spacing: 0) {
            Rule()
            Link(destination: url) {
                HStack(spacing: 12) {
                    Text(title).font(Theme.body(16, .semibold)).foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 48)
                .contentShape(.rect)
            }
            .accessibilityHint("Opens in Safari")
        }
    }

    private var finePrint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Version \(version)" + (seasonsRange.map { " \u{00B7} seasons \($0)" } ?? ""))
            Text("Zilla Slab and Libre Franklin, SIL Open Font License 1.1")
        }
        .font(Theme.body(13))
        .foregroundStyle(Theme.ink3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
    }

    private var resetButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(role: .destructive) { confirmReset = true } label: {
                Label("Reset all data", systemImage: "trash")
            }
            .buttonStyle(DestructiveOutlineStyle())
            Text("Erases your games, stats and settings on this device.")
                .font(Theme.body(13)).foregroundStyle(Theme.ink3)
        }
        .padding(.top, 4)
    }
}

/// The outline button in the red of a miss: a destructive action that still reads as the site's button.
private struct DestructiveOutlineStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(14.5, .bold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Theme.bad)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .overlay { RoundedRectangle(cornerRadius: Theme.radiusS).strokeBorder(Theme.bad, lineWidth: 1.5) }
            .contentShape(.rect(cornerRadius: Theme.radiusS))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview("About") {
    AboutSheet().environment(AppModel())
}
