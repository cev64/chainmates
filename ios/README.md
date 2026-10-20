# Chainmates for iPhone and iPad

The daily puzzle as a native SwiftUI app with Liquid Glass. It runs on iPhone, iPad and the
iPhone Duo, inner and outer displays.

Open `ios/Chainmates.xcodeproj` in Xcode 27.1 or later (the iOS 27.1 SDK is what gives the
iPhone Duo its full screen and vertical bars), and run the `Chainmates` scheme. The deployment
target is iOS 26.1. Set your team under Signing & Capabilities to run on a device.

## How it's built

The app doesn't re-implement a single game rule. It runs the site's own core and draws what the
core answers natively.

- **The core:** `core/handoff-core.js` is bundled unchanged and runs in JavaScriptCore
  (`Chainmates/Core/CoreEngine.swift`, an actor). The Swift calls are typed
  (`Core/CoreAPI.swift`). A game state stays the JSON the core returned, so it round-trips untouched.
  - The core handles validation, guess, undo, hints, the mode switch, scoring, share text, stats,
    streaks, the Eastern-time date and the autocomplete ranking, exactly as on the site.
  - `ChainmatesTests/VectorsTests.swift` runs every case in `core/test/vectors.json` through the
    bridge. A rule change lands once, in the core, and the vectors prove both clients.
- **The data:** `data/nfl/players.json` and `puzzles.json` ship in the app.
  - After launch it quietly checks `cev64.github.io/chainmates/data/nfl/` for newer copies and keeps
    them for the next launch (`App/DataStore.swift`). The data bot re-picks future prime-time
    puzzles when games flex, and today's puzzle is frozen, so a refresh never changes a game in
    progress.
  - Only data is downloaded, never code (App Review 2.5.2).
- **Saves** use the web's localStorage keys in UserDefaults (`chainmates.nfl.daily.8`,
  `chainmates.nfl.stats`, `chainmates.mode`, `chainmates.theme`).
- **The look** is the site's, from `web/app.css`: newsprint paper, ink, hairline rules, Zilla Slab
  and Libre Franklin, and the chalk-line green accent (`Design/Theme.swift`).
  - Liquid Glass is only on the system's functional layer: the tab bar and sidebar, toolbars,
    sheets, and the guess bar. It never goes on content (CLAUDE.md: no decorative glass).

## Layout: phones, iPads and the iPhone Duo

One `TabView` (Today, Archive, Stats) with `.sidebarAdaptable`. It's a glass tab bar on compact
widths and a sidebar on regular ones, and it's the same view tree in both, so folding or unfolding
the Duo keeps your place. Layout follows size classes and the measured space only; nothing reads
the device, its idiom or `UIScreen`.

- **iPhone, the folded Duo's outer display, and narrow iPad windows** (compact width): one column,
  max 640 points, the site's width. The guess field is a glass bar at the bottom. On the folded Duo
  the system draws the tab bar and toolbar as a vertical bar down the trailing edge, and Today asks
  it to keep its actions there (`toolbarVerticalCompressionBehavior(.prefersToolbarItems)`).
- **iPad and the unfolded Duo** (regular width):
  - The tabs become a sidebar.
  - In landscape, Today splits into two panes with `ArrangementView` on iOS 27.1, so the panes
    line up with the Duo's fold; a single column is never centred on the fold.
  - In portrait (the Duo's laptop pose has the fold across the middle), the chain is on top and the
    guess bar is at the bottom.
  - The archive grid uses an even number of columns when there's a fold.
- **Orientation:**
  - iPhone is portrait-only.
  - iPad supports all four orientations, because iPadOS 26/27 windows resize freely and
    `UIRequiresFullScreen` no longer opts out. It's designed and screenshotted in landscape.
  - The Duo's inner display ignores the orientation list, by design.
- **The iPad menu bar** (`App/AppCommands.swift`): Puzzle ▸ Undo Link ⌘Z, Hint ⇧⌘H, Results ⇧⌘R;
  Archive ⌘2, Statistics ⌘3; Help ▸ How to Play ⌘?.

## Opening a screen directly

For screenshots, launch settings open the app on a screen (`App/DebugLaunch.swift`, Debug builds
only):

    SIMCTL_CHILD_CM_TAB=archive xcrun simctl launch booted com.cev64.chainmates

The settings are:
- `CM_TAB` (today, archive, stats)
- `CM_SHEET` (help, about, results)
- `CM_PUZZLE` (a number)
- `CM_MOVES` (comma-separated player ids to guess)
- `CM_THEME` (light, dark)
- `CM_RESET=1`

On the iPhone Duo simulator, `xcrun simctl io <udid> screenshot --display=primary` captures the
outer display. Folding and unfolding happen in Xcode 27's Device Hub.

## Tests

    cd ios && xcodebuild test -project Chainmates.xcodeproj -scheme Chainmates \
      -destination 'platform=iOS Simulator,name=iPhone 17'

## The app icon

`tools/make-app-icon.swift` draws it from the site's mark (`web/icon-maskable.svg`), with light,
dark and tinted variants:

    swiftc -o /tmp/make-app-icon ios/tools/make-app-icon.swift && /tmp/make-app-icon

## Submitting to the App Store

`APP_STORE.md` covers what the app does for App Review, the steps outside Xcode, the App Store
Connect answers and the notes for the reviewer.
