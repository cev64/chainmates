import Foundation

/// The sport registry, ported from `web/sports.js`: every sport-specific word the app shows comes
/// from here. Teams, labels and colours come from players.json. Keep it in step with the web file.
struct Sport: Sendable {
    let key: String
    let title: String
    let mode: String
    let emoji: String
    let lives: String
    let life: String
    let miss: String
    let lost: String
    let tagline: String
    let rule: String
    let positions: [String: String]
    let hints: [String: [String]]
    let disclaimer: String
    let attributionText: String
    let attributionURL: URL

    static let nfl = Sport(
        key: "nfl",
        title: "Chainmates",
        mode: "Football",
        emoji: "\u{1F3C8}",
        lives: "downs",
        life: "down",
        miss: "incompletion",
        lost: "Turnover on downs",
        tagline: "Connect two players through teammates.",
        rule: "on the same 53-man roster in the same season",
        positions: [
            "QB": "qb", "RB": "rb", "FB": "rb", "HB": "rb", "WR": "wr", "TE": "te",
            "T": "ol", "G": "ol", "C": "ol", "OT": "ol", "OG": "ol", "OL": "ol",
            "DE": "dl", "DT": "dl", "NT": "dl", "DL": "dl",
            "LB": "lb", "ILB": "lb", "MLB": "lb", "OLB": "lb",
            "CB": "db", "S": "db", "FS": "db", "SS": "db", "DB": "db", "SAF": "db",
            "K": "k", "PK": "k", "P": "p", "LS": "ls",
        ],
        hints: [
            "qb": ["Somebody was under center for the {team}. Find the quarterback.",
                   "Check the {team} depth chart, top line: a quarterback is your guy."],
            "rb": ["Hand it off. A running back on the {team} gets you there.",
                   "Feed the running back. He was on the {team}."],
            "wr": ["Go deep: a wide receiver on the {team} is wide open.",
                   "Look for a receiver. He was catching passes for the {team}."],
            "te": ["Check down to the tight end on the {team}.",
                   "Your link is a tight end who played for the {team}."],
            "ol": ["Nobody notices the big guys. An offensive lineman on the {team} is your link.",
                   "Go to the trenches: an offensive lineman blocked for the {team}."],
            "dl": ["Pressure up front: a defensive lineman on the {team}.",
                   "Look for a pass rusher with his hand in the dirt for the {team}."],
            "lb": ["A linebacker on the {team} makes this tackle.",
                   "Find the linebacker who was flying around for the {team}."],
            "db": ["Look to the secondary: a defensive back on the {team}.",
                   "A ball hawk in the {team} secondary is your link."],
            "k": ["Special teams! The {team} kicker is your link."],
            "p": ["Special teams! The {team} punter is your link."],
            "ls": ["Respect the long snapper. The {team} had one, and he is your link."],
            "any": ["Try someone from the {team}."],
        ],
        disclaimer: "Unofficial fan game. Not affiliated with or endorsed by the NFL, NFLPA, or any team.",
        attributionText: "Player data from nflverse (CC-BY 4.0)",
        attributionURL: URL(string: "https://github.com/nflverse")!
    )

    static let current = Sport.nfl

    func shareOptions() -> ShareOptions {
        ShareOptions(url: AppConfig.shareURL, title: title, emoji: emoji, miss: miss, lost: lost, hardLabel: "Hard")
    }

    /// The hint sentence split around its team label, picked like the web's `hintCopy`: FNV-1a
    /// over "{puzzle}.{chain length}", so a puzzle and chain spot always get the same line.
    func hintCopy(_ hint: Hint, puzzle n: Int, chainLength: Int) -> (before: String, after: String) {
        let group = hint.pos.flatMap { positions[$0.uppercased()] } ?? "any"
        let pool = hints[group].flatMap { $0.isEmpty ? nil : $0 } ?? hints["any"] ?? ["Try someone from the {team}."]
        let line = pool[Self.hashPick(n, chainLength, pool.count)]
        guard let range = line.range(of: "{team}") else { return (line + " ", "") }
        return (String(line[..<range.lowerBound]), String(line[range.upperBound...]))
    }

    static func hashPick(_ n: Int, _ length: Int, _ size: Int) -> Int {
        var h: UInt32 = 2_166_136_261
        for unit in "\(n).\(length)".utf16 {
            h ^= UInt32(unit)
            h = h &* 16_777_619
        }
        return Int(h % UInt32(max(size, 1)))
    }
}

/// App-wide constants; the web keeps the same values in `CONFIG` in `web/app.js`.
enum AppConfig {
    /// The site, scheme-less, as share cards print it. The core appends `#n`.
    static let shareURL = "cev64.github.io/chainmates/"
    static let siteURL = URL(string: "https://cev64.github.io/chainmates/")!
    static let privacyURL = URL(string: "https://cev64.github.io/chainmates/privacy.html")!
    static let termsURL = URL(string: "https://cev64.github.io/chainmates/terms.html")!
    static let supportURL = URL(string: "https://cev64.github.io/chainmates/support.html")!
    static let searchLimit = 8
    /// The web debounces autocomplete by 100 ms.
    static let searchDebounce: Duration = .milliseconds(100)
    static let toastDuration: Duration = .milliseconds(3400)
}

/// Small display helpers ported from `web/app.js`. None of them is a game rule.
enum Format {
    private static let shortDays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let shortMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August",
                                 "September", "October", "November", "December"]

    private static func parts(_ ymd: String) -> (y: Int, m: Int, d: Int, weekday: Int)? {
        let p = ymd.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let date = cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return nil }
        return (p[0], p[1], p[2], cal.component(.weekday, from: date) - 1)
    }

    /// "Fri, Oct 16" (`fmtDate`), with ", 2026" when `long`.
    static func date(_ ymd: String, long: Bool = false) -> String {
        guard let p = parts(ymd) else { return ymd }
        return "\(shortDays[p.weekday]), \(shortMonths[p.m - 1]) \(p.d)" + (long ? ", \(p.y)" : "")
    }

    /// "Friday, October 16" (`fmtDateLong`).
    static func dateLong(_ ymd: String) -> String {
        guard let p = parts(ymd) else { return ymd }
        return "\(days[p.weekday]), \(months[p.m - 1]) \(p.d)"
    }

    /// "2011–2023", or "2019" for one season.
    static func years(_ p: CorePlayer) -> String {
        guard let first = p.first else { return "" }
        guard let last = p.last, last != first else { return String(first) }
        // Word joiners keep "2009–2026" on one line.
        return "\(first)\u{2060}\u{2013}\u{2060}\(last)"
    }

    /// "QB · 2011–2023"
    static func meta(_ p: CorePlayer) -> String {
        [p.pos, years(p)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "12–15" for a run of seasons, "2015" for one.
    static func stintYears(_ r: StintRange) -> String {
        r.from == r.to ? String(r.from) : "\(String(r.from).suffix(2))\u{2013}\(String(r.to).suffix(2))"
    }

    /// "05:12:44"
    static func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// "one under par", "two under par"
    static func underText(_ over: Int) -> String {
        let words = ["", "one", "two", "three"]
        let n = -over
        return (n < words.count ? words[n] : String(n)) + " under par"
    }

    /// Chip text colour: whichever of white or near-black has the higher WCAG contrast on `hex`.
    static func chipInkIsLight(_ hex: String) -> Bool {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard let n = UInt32(s, radix: 16) else { return true }
        func lin(_ c: UInt32) -> Double {
            let v = Double(c) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let l = 0.2126 * lin((n >> 16) & 255) + 0.7152 * lin((n >> 8) & 255) + 0.0722 * lin(n & 255)
        return 1.05 / (l + 0.05) >= (l + 0.05) / 0.0582
    }
}
