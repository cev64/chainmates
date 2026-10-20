import SwiftUI
import UIKit
import XCTest
@testable import Chainmates

/// Renders the Info feature's views to PNGs so they can be looked at. The sheets are drawn from a real
/// window (so the navigation bar, close button and sheet chrome are the system's); the rest
/// through `ImageRenderer`'s sibling `drawHierarchy`. PNGs go to the team's shots folder.
@MainActor
final class InfoSnapshotTests: XCTestCase {
    private static let outDir = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-charlievonderheid-Desktop-DEV-chainmates/16df9ebd-841c-42e3-a711-eabe2234d733/scratchpad/team/shots", isDirectory: true)

    private var windows: [UIWindow] = []

    override func setUp() async throws {
        try FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        windows.forEach { $0.isHidden = true }
        windows = []
    }

    private func loadedApp() async -> AppModel {
        let app = AppModel()
        await app.start()
        app.sheet = nil
        for _ in 0..<50 where app.session?.state == nil { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(400))
        return app
    }

    private func snapshot<V: View>(_ name: String, _ view: V, size: CGSize = CGSize(width: 393, height: 852),
                                   dark: Bool = false, category: UIContentSizeCategory? = nil,
                                   wait: Duration = .milliseconds(1500)) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        if let category { window.traitOverrides.preferredContentSizeCategory = category }
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        windows.append(window)
        try await Task.sleep(for: wait)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let url = Self.outDir.appendingPathComponent("info-\(name).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        window.isHidden = true
    }

    /// A paper page that presents `sheet` the way the app does.
    private struct SheetHost<Sheet: View>: View {
        @State private var shown = false
        let sheet: Sheet
        var body: some View {
            Theme.paper.ignoresSafeArea()
                .sheet(isPresented: $shown) { sheet }
                .onAppear { shown = true }
        }
    }

    func testHelp() async throws {
        let app = await loadedApp()
        try await snapshot("help-light", SheetHost(sheet: HelpSheet().environment(app)).environment(app), wait: .seconds(2))
        try await snapshot("help-dark", SheetHost(sheet: HelpSheet().environment(app)).environment(app), dark: true, wait: .seconds(2))
        try await snapshot("help-xxxl", SheetHost(sheet: HelpSheet().environment(app)).environment(app),
                           category: .accessibilityExtraExtraLarge, wait: .seconds(2))
        try await snapshot("help-ipad", SheetHost(sheet: HelpSheet().environment(app)).environment(app),
                           size: CGSize(width: 900, height: 1100), wait: .seconds(2))
    }

    func testAbout() async throws {
        let app = await loadedApp()
        try await snapshot("about-light", SheetHost(sheet: AboutSheet().environment(app)).environment(app), wait: .seconds(2))
        try await snapshot("about-dark", SheetHost(sheet: AboutSheet().environment(app)).environment(app), dark: true, wait: .seconds(2))
        try await snapshot("about-xxxl", SheetHost(sheet: AboutSheet().environment(app)).environment(app),
                           category: .accessibilityExtraExtraLarge, wait: .seconds(2))
    }

    func testAboutFull() async throws {
        let app = await loadedApp()
        try await snapshot("about-full", AboutSheet().environment(app).paperBackground(), size: CGSize(width: 393, height: 1100), wait: .seconds(1))
        try await snapshot("about-full-dark", AboutSheet().environment(app).paperBackground(), size: CGSize(width: 393, height: 1100), dark: true, wait: .seconds(1))
        try await snapshot("about-full-xxxl", AboutSheet().environment(app).paperBackground(), size: CGSize(width: 393, height: 2600), category: .accessibilityExtraExtraLarge, wait: .seconds(1))
    }

    func testStatus() async throws {
        let app = AppModel()
        func page<V: View>(_ v: V) -> some View { v.environment(app).paperBackground() }
        try await snapshot("status-loading", page(StatusView(kind: .loading)))
        try await snapshot("status-error", page(StatusView(kind: .error("The Internet connection appears to be offline."))))
        try await snapshot("status-error-dark", page(StatusView(kind: .error("The Internet connection appears to be offline."))), dark: true)
        try await snapshot("status-offday", page(StatusView(kind: .offDay)))
    }

    func testToastAndFooter() async throws {
        let app = AppModel()
        app.toast = .init(text: "Hint revealed", detail: "2 downs left")
        try await snapshot("toast", Theme.paper.ignoresSafeArea().overlay { ToastOverlay() }.environment(app), wait: .seconds(1))
        try await snapshot("toast-dark", Theme.paper.ignoresSafeArea().overlay { ToastOverlay() }.environment(app), dark: true, wait: .seconds(1))
        try await snapshot("footer", VStack { Spacer(); FooterView() }.environment(app).paperBackground())
        try await snapshot("footer-xxxl", VStack { Spacer(); FooterView() }.environment(app).paperBackground(),
                           category: .accessibilityExtraExtraLarge)
    }
}
