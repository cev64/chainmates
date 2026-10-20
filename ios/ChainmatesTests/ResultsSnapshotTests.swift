import SwiftUI
import XCTest
@testable import Chainmates

/// Renders the Results sheet, Statistics and Archive screens over seeded saves into PNGs
/// (not assertions: a person reads them). Runs in the app host so the real engine, data and
/// fonts are used.
@MainActor
final class ResultsSnapshotTests: XCTestCase {
    private let outDir = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-charlievonderheid-Desktop-DEV-chainmates/16df9ebd-841c-42e3-a711-eabe2234d733/scratchpad/team/shots", isDirectory: true)
    private let phone = CGSize(width: 393, height: 852)
    private let tall = CGSize(width: 393, height: 2000)
    private let wide = CGSize(width: 1180, height: 820)

    func testScreens() async throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let app = try await ResultsDebug.seededModel()
        try await openSession(app, 8)
        try await shot(ResultsSheet(), app, tall, "results-eagle-full")
        try await shot(ResultsSheet(), app, phone, "results-eagle")
        try await shot(ResultsSheet(), app, tall, "results-eagle-dark-full", dark: true)
        for (n, name) in [(1, "par"), (3, "lost"), (4, "birdie"), (5, "over"), (7, "practice")] {
            try await openSession(app, n)
            try await shot(ResultsSheet(), app, tall, "results-\(name)-full")
        }
        try await shot(StatsScreen(), app, phone, "stats")
        try await shot(StatsScreen(), app, phone, "stats-dark", dark: true)
        try await shot(StatsScreen(), app, wide, "stats-wide")
        try await shot(ArchiveScreen(), app, phone, "archive")
        try await shot(ArchiveScreen(), app, phone, "archive-dark", dark: true)
        try await shot(ArchiveScreen(), app, wide, "archive-wide")

        Store.resetAll()
        Store.seenHelp = true
        let empty = AppModel()
        await empty.start()
        try await shot(StatsScreen(), empty, phone, "stats-empty")
        try await shot(ArchiveScreen(), empty, phone, "archive-empty")
        Store.resetAll()
    }

    private func openSession(_ app: AppModel, _ n: Int) async throws {
        app.open(n)
        for _ in 0..<60 {
            if app.session?.puzzle.n == n, app.session?.state != nil, app.session?.score != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(200))
    }

    private func shot<V: View>(_ view: V, _ app: AppModel, _ size: CGSize, _ name: String, dark: Bool = false) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        let host = UIHostingController(rootView: AnyView(view.environment(app).background(Theme.paper)))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        try await Task.sleep(for: .milliseconds(2200))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: outDir.appendingPathComponent("\(name).png"))
        window.isHidden = true
    }
}
