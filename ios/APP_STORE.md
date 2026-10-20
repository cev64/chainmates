# App Store submission

What the app must do for App Review, what still has to happen outside Xcode,
and what to type into App Store Connect. Researched on 2026-10-19 against the
App Review Guidelines page, which prints "Last Updated: October 16, 2026"
(the sister app was checked against June 8, 2026). Apple's own summary of the
Oct 16 changes: new 2.3.14 (creative assets) and 2.5.19 (hidden or undocumented
features, moved out of 2.3.1), clarified 1.2, 3.1.1(a) and Section 5
(<https://developer.apple.com/news/?id=92th7e5i>). None of them changes the
plan below. The June 8 changes were 4.3(a)/(b) (spam, more examples), 1.2,
4.5.3 and the kid/teen intro (<https://developer.apple.com/news/?id=a233fmpw>).

Marked **(unverified)** where I could not read Apple's page and am going from
memory or secondary sources.

## In the app

| Guideline | What the app must do |
| --- | --- |
| 2.1 completeness | No placeholder text, no dead links, no "coming soon" (also no "Pro"/prices, see 3.1.1). Handle running out of bundled puzzles: `puzzles.json` currently ends 2027-10-16 (No. 370); if the device date is past the last puzzle, show the archive and practice mode with a plain message, never an empty screen or a crash. Same for a device date before No. 1 (2026-10-12) |
| 2.1 / 4.2 offline | Works with airplane mode on, first launch included: the data ships in the app. The only network use is a quiet check for newer puzzle data (`players.json`, `puzzles.json` from cev64.github.io, `App/DataStore.swift`), kept for the next launch; a failure is silent. No account, no analytics |
| 4.2 minimum functionality (not a web wrapper) | No `WKWebView`, `SFSafariViewController`-as-app-body or bundled `web/` folder in the binary. UI is SwiftUI. Autocomplete calls the core's `search` through JavaScriptCore so its ranking matches the site exactly. `JSContext` only evaluates the rules (no DOM, no view). Ship the native features a reviewer can see: haptics on link/incomplete, Dynamic Type, VoiceOver, share sheet, archive, stats, offline play |
| 5.1.1(i) privacy policy | Settings/About screen has Privacy Policy, Terms and Support rows that open <https://cev64.github.io/chainmates/privacy.html>, `terms.html`, `support.html` with `Link`/`openURL` (system Safari, not an in-app browser). All three return 200 today. The same URLs go in App Store Connect |
| 5.1.1 data | Stats and streaks live only in `UserDefaults`. Settings has "Reset all data" (clears the `chainmates.` keys) so deletion and withdrawal of data is in the app. No account, so 5.1.1(v) account deletion does not apply |
| 5.1.1 privacy manifest | `PrivacyInfo.xcprivacy` in the app target: `NSPrivacyTracking` false, `NSPrivacyTrackingDomains` empty array, `NSPrivacyCollectedDataTypes` empty array, `NSPrivacyAccessedAPITypes` = UserDefaults with `CA92.1`. Full file below |
| Required-reason APIs | Do not call anything else on Apple's list unless you add its reason: file timestamps (`attributesOfItem`, `creationDate`/`contentModificationDate` resource values, `stat`), system boot time (`ProcessInfo.systemUptime`, `mach_absolute_time`), disk space (`volumeAvailableCapacity*`, `statfs`), active keyboards. Loading the bundled JSON with `Data(contentsOf:)`/`Bundle.url` and using `JSContext`, `Date`, `ShareLink` and SwiftUI needs none. Use `Date()` and `Task.sleep`/SwiftUI animation for timing. If a countdown or animation clock ever needs uptime, add `NSPrivacyAccessedAPICategorySystemBootTime` `35F9.1`; for container file dates add `FileTimestamp` `C617.1` (reason codes **unverified live**: Apple's page would not load, these are from memory) |
| 5.1.2 third parties | No third-party SDKs, no analytics, no crash reporters, no ATT prompt, no `NSUserTrackingUsageDescription`. Adding any of these changes the privacy label and the manifest |
| 2.5.2 executing code | `core/handoff-core.js` is bundled in the app and loaded from `Bundle.main` only. Never fetch, cache or update JS from the network. Data JSON may be updated over the air later (data, not code); JS may not. Review notes say so |
| 5.2.1 / 5.2.2 IP | Teams are abbreviation chips on team colour (ClubChip). No logos, no photos, no league marks, no helmets. About screen and footer carry "Unofficial fan game. Not affiliated with or endorsed by the NFL, NFLPA, or any team." Acknowledgements credit nflverse with a link and "CC-BY 4.0" (attribution is the licence condition) |
| 2.3.8 / 5.2.1 text in the app | Do not show "NFL" or "Super Bowl" as game names, badges or share text. The disclaimer is the only place "NFL" appears. Review `theme` strings in `puzzles.json` ("Monday Night: Bills at Rams", slot `MNF`): fine as plain text, but do not style them like a broadcast or league brand |
| 4.1 / 4.3(b) copycat, spam | Own look (see `docs/design-notes.md`), no Wordle-style 5x6 tile grid or green/yellow/grey tiles in the UI. Keep one bundle ID, one app |
| 1.2 UGC | None. No names, notes, comments, usernames or user-entered text shown to others. The only text out is the share card |
| Share sheet | `ShareLink` with plain text only: puzzle number, emoji squares, score, link. Spoiler-free, no player names. No `NSPhotoLibraryAddUsageDescription` (no image saving). If you ever add a share image, add that key |
| 4.8 login | No sign-in anywhere, so Sign in with Apple is not needed and must not be added with other logins |
| Info.plist encryption | `ITSAppUsesNonExemptEncryption` = `NO` (only standard HTTPS through `URLSession`, no custom crypto: exempt). Skips the export questions on every upload |
| Info.plist permissions | None. Do not add any `NS...UsageDescription`. If a daily reminder is added later: ask only after the user taps "Remind me", never at launch, never required (5.1.2) |
| iPad / orientation | `UIDeviceFamily` includes iPad. Do **not** set `UIRequiresFullScreen`. Layout is driven by the size of the scene (`GeometryReader`/`onGeometryChange`, size classes), not by orientation, idiom or `UIScreen.main`. iPad `UISupportedInterfaceOrientations~ipad`: all four (see iPad and iPhone Duo below). iPhone: portrait. No `UIApplicationSupportsMultipleScenes` needed |
| iPhone Duo | Build with Xcode 27.1. Test in the iPhone Duo simulator and the iOS resizable simulator (Device Hub). Layout must survive a fold mid-session and a window of any aspect ratio. No `UIScreen.main.bounds`, no `UIDevice.current.orientation`, no `userInterfaceIdiom == .phone` branching, no fixed heights like `844` |
| Accessibility | VoiceOver labels on every ClubChip ("Chiefs" not just "KC" if the abbreviation is cryptic), grid cells, buttons and the result; Dynamic Type up to the largest accessibility sizes without clipping; `accessibilityReduceMotion` removes spring/draw-in motion (CLAUDE.md promises a reduced-motion fallback); results must not rely on colour alone (`accessibilityDifferentiateWithoutColor`; the emoji share card already has squares plus a score); contrast AA on team-colour chips (white or black text, whichever passes); light and dark both work |
| Debug | Debug launch hooks (fixed clock, puzzle override) compile only under `#if DEBUG` (2.5.19: no hidden or undocumented features in release builds) |
| Widgets (if added) | Widget needs an App Group; shared `UserDefaults(suiteName:)` needs reason `1C8F.1` in the manifest of each target that touches it. Not in v1 |
| 3.1.1 purchases (later) | No prices, no "Unlimited"/"Pro" copy, no locked-feature teasers in v1. When StoreKit arrives: Restore Purchases, Terms link, privacy label re-checked, DSA trader answer re-checked |

### `PrivacyInfo.xcprivacy` (copy of the sister app's shape, nothing collected)

```xml
<dict>
  <key>NSPrivacyTracking</key><false/>
  <key>NSPrivacyTrackingDomains</key><array/>
  <key>NSPrivacyCollectedDataTypes</key><array/>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key><array><string>CA92.1</string></array>
    </dict>
  </array>
</dict>
```

Check the archive with Xcode's "Generate Privacy Report" (Organizer, archive).
It should list UserDefaults only and no collected data.

## Before submitting (outside Xcode)

1. **Rewrite the legal pages for the app.** `web/privacy.html`, `terms.html` and `support.html` say "Applies to the Chainmates website", describe browser local storage and Google Fonts, and `support.html` is titled "Help for the Chainmates website". A reviewer reading 5.1.1(i) will not find the iOS app covered. Add: the iOS app, `UserDefaults` on device, nothing collected, the puzzle-data download from GitHub Pages, how to delete (Reset all data or delete the app), share text, and a Children line. Merge to `main` and confirm all three still return 200 before review.
2. **Give support a real contact.** `support.html` only offers GitHub issues (needs a GitHub account). Add a monitored email address; the Support URL must lead somewhere a person can reach you, and the DSA trader details (if trader) are also public.
3. **Name and trademark check.** Search "Chainmates" in App Store Connect (name must be unique, 30 characters max, 2.3.7) and in the App Store for look-alikes. I could not check availability from here.
4. **Reserve the bundle ID and create the app record** with iPhone and iPad.
5. **Archive with Xcode 27.1** (iOS 27 SDK). From April 2027 uploads must be built with the iOS/iPadOS 27 SDK or later (<https://developer.apple.com/news/?id=k1mtkt1k>); Xcode 27.1 already meets it.
6. **Run the age rating questionnaire.** Answers have been required on every submission since September 2026 (<https://developer.apple.com/news/?id=tlur8uvi>).
7. **Accessibility Nutrition Labels** (optional today, "over time" required: <https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels>; no date given). Only tick features after testing every common task with that feature alone.
8. **DSA trader status** at Business > Agreements > Compliance (account level), then per app under App Information > App Store Regulations and Permits (<https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/>). Required even if you do not sell in the EU.
9. **Screenshots** (see below). Take them in the simulator, from the finished app, with a real daily puzzle. Show Charlie the simulator screenshots first (CLAUDE.md).
10. **TestFlight pass** on a real iPhone and an iPad: airplane mode, Dynamic Type XXXL, VoiceOver, Reduce Motion, Dark mode, iPad Split View and a narrow Stage Manager window, device date changed to the day after the last puzzle.
11. **Update contact info** for App Review in App Store Connect ("Before You Submit").

## App Store Connect

- **Privacy Policy URL**: https://cev64.github.io/chainmates/privacy.html
- **Support URL**: https://cev64.github.io/chainmates/support.html
- **Marketing URL** (optional): https://cev64.github.io/chainmates/
- **Terms of use**: not required for a free app with no subscription; link `terms.html` in the description if you want it visible.
- **Name / subtitle / keywords**: no "NFL", "Super Bowl", team names, player names, "Immaculate Grid", "Wordle". Name 30 characters, subtitle 30, keywords 100 (2.3.7, 5.2.1, 4.1(c)). Describe it as "pro football" or "football" in the description; keep "NFL" to the disclaimer sentence at the end, if at all. Metadata must be fine for 4+ even if the app is rated higher (2.3.8). Draft: Name `Chainmates`; subtitle `Daily football teammate puzzle`.
- **Creative assets** (new 2.3.14: product page headers and search result assets, <https://developer.apple.com/news/?id=ljpl7kyn>): optional. If used they must reflect the app, be all-audience, with no logos, unverifiable claims or prices. Skip them in v1.
- **Category**: Primary Sports; no secondary. Alternative is Games > Trivia, but Games or Entertainment as primary or secondary adds a Korean regional rating (GRAC) and puts the app under Time Allowances for parents (<https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/>). Judgement call, see below.
- **Price**: Free. No in-app purchases in v1.
- **App Privacy**: **Data Not Collected.** Tracking: No. The app has no server, no SDK and no analytics; `UserDefaults` stays on the device (Apple defines "collect" as data leaving the device). Safari opening the GitHub Pages URLs is not the app collecting data.
- **Age rating** (tiers are now 4+, 9+, 13+, 16+, 18+; the highest triggered descriptor sets the tier, which is the usual reading, not stated outright by Apple). I could not read the questionnaire itself, so match each question by its descriptor name:
  - None: profanity or crude humor; horror/fear; alcohol, tobacco or drug references; medical or treatment info; sexual content or nudity; mature or suggestive themes; cartoon/fantasy violence; realistic violence; guns or other weapons; simulated gambling; gambling; loot boxes.
  - No: unrestricted web access; user-generated content; messaging or chat; advertising; social media (the July 2026 question: no feed, no UGC); parental controls; age assurance.
  - **Contests**: Apple defines contests as users competing for rankings, rewards or personal goals, naming trivia quizzes. Frequent contests lands at 13+. The game has no leaderboard, no rewards and no one to compete with, so answer **None** and, if the form forces a choice, **Infrequent** (still 4+). Honest-answers rule is 2.3.6; if you pick Frequent the cost is only a 13+ rating, so when in doubt that is the safe side.
  - Expected result: **4+**. Do not set Made for Kids (it opts into the Kids Category rules). Age Categories and Override: Not Applicable. No Declared Age Range API use.
- **Accessibility labels** (voluntary now): claim only what you tested. Likely claims after testing: VoiceOver, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion, Voice Control. Not applicable: Captions, Audio Descriptions (no audio or video). Use the optional accessibility URL for the how-to-play text.
- **Export compliance**: answered by the Info.plist key (`NO`). No ECCN, no French declaration (exempt/none, **unverified live**: Apple's page would not load).
- **App Review contact / Sign-in required**: leave "Sign-in required" off. No demo account exists to give.
- **Screenshots** (<https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications>; up to 10 per size; PNG or JPEG, no alpha; one set scales down to smaller sizes if the UI is consistent):
  - iPhone, Dynamic Island (medium), **required, at least one**: 1206 x 2622 (or 1179 x 2556). Also upload 1320 x 2868 (large). The page's fallback rules are confusing, so upload both to be safe.
  - iPad **13", required** because the app runs on iPad: 2064 x 2752 portrait or 2752 x 2064 landscape (2048 x 2732 / 2732 x 2048 also accepted). The sister app used 2752 x 2064.
  - **iPhone Duo**: optional now (gives an "optimized for iPhone Duo" badge), **required from April 2027 for apps built with the iOS 27.1 SDK or later**: outer display 1398 x 2034 (2034 x 1398), inner display 2007 x 2853 (2853 x 2007). Duo launches Oct 23, 2026 (<https://developer.apple.com/news/?id=kkphp5qo>). Cheapest path: add them in v1 so later updates are not blocked.
  - Screenshots must show the app in use (2.3.3): puzzle in progress, a solved result, the hint, the archive, stats. No logos, no prices.
- **App Review Information**: your phone and email; notes below.

## iPad and iPhone Duo

- Since iPadOS 26 every iPad app is windowed and freely resizable. For apps built with the iOS 27 SDK, Apple says a supported orientation is "a preference provided to the system" that is ignored in a resizable environment, and "you should not consider interface orientation for any layout calculations" (WWDC26 session 278, <https://developer.apple.com/videos/play/wwdc2026/278/>). So "iPad is landscape" in CLAUDE.md is a design target for screenshots, not something the code can enforce. Design the iPad layout for any window size from narrow-portrait to wide-landscape.
- `UIRequiresFullScreen`: not deprecated in Apple's docs as of Aug 2026 per a secondary source, but its behaviour changed and it no longer opts out of resizing (WWDC26 278). Leave it out. Do not rely on it for review safety.
- Orientation plist: iOS 27 release notes (via a secondary write-up, <https://blakecrosley.com/blog/ipad-continuous-resizability-ios-27>) say an iPad app declaring fewer than all four orientations was treated as not continuously resizable in Beta 4, listed as fixed by the RC. I could not read Apple's final notes. Declare all four for `~ipad` and keep portrait for iPhone (per-idiom keys), and the question disappears. **(unverified: confirm in the final iOS 27 release notes)**
- UIKit scene lifecycle is mandatory on the iOS 27 SDK (apps without it do not launch, WWDC26 278). A SwiftUI `App` lifecycle project is not an AppDelegate-owned-window app; if any UIKit shim is added, keep it scene-based.
- iPhone Duo: apps built with the iOS 27.1 SDK use the whole inner display; toolbars and tab bars move vertically below the status bar; apps on older SDKs get letterboxed. All apps run unmodified. Guidance and checklist: <https://developer.apple.com/iphone-duo/prepare/>. Apple publishes no Duo-specific App Review rule beyond the April 2027 screenshot requirement. **(I found no other Duo submission rule.)**

## Notes for App Review (paste and fill in)

> Chainmates is a free daily puzzle game. Each day shows a Start player and a Finish player from pro football. The player adds players one at a time, each a teammate of the previous one, to connect Start to Finish in as few links as possible. Par, three downs, a free undo and a hint make up the scoring. There is also an archive of past puzzles (practice) and local stats and streaks.
>
> No account, sign-in or demo credentials are needed, and none are used. The app has no backend and works fully offline. Its data is bundled: `players.json` (player names, teams, seasons) and `puzzles.json` (the puzzle calendar). When online it checks the game's website (cev64.github.io/chainmates) for newer copies of those two JSON data files, so future puzzles stay in step with the site; no code is downloaded and nothing is sent. Statistics are saved on the device in UserDefaults and never leave it. The app collects no data, has no tracking, no analytics, no ads and no in-app purchases.
>
> This is a native SwiftUI app, not a web wrapper: there is no WKWebView or embedded website. The game rules (chain validation, scoring, share text) are one JavaScript file bundled in the app, evaluated by JavaScriptCore (JSContext), which has no DOM, no network access and no view. It is never downloaded or updated remotely (Guideline 2.5.2). Search, the keyboard flow, animation, haptics, Dynamic Type, VoiceOver and the share sheet are native.
>
> To see a full play: launch, tap Play today, tap Add player, type "mahomes", choose a result. A wrong teammate shows an incompletion and costs a down. Share on the results screen opens the system share sheet with a spoiler-free emoji result card (no player names). The Archive (calendar button) lets you play any earlier puzzle. Settings > About has the Privacy Policy, Terms and Support links and Reset all data.
>
> Chainmates is an unofficial fan game, not affiliated with or endorsed by the NFL, NFLPA or any team, and says so in the app. It uses player names and team abbreviations on team colours only: no logos, no photos, no league marks. Player and roster data comes from nflverse under CC-BY 4.0, credited in the app.
>
> The Start/Finish pairs are chosen by a script from the data and are not user-generated. The device date decides today's puzzle (Eastern Time midnight). If you review after the last bundled puzzle (2027-10-16), the app shows the archive instead.
>
> The app is built with Xcode 27.1 and is optimized for iPhone, iPad (resizable windows) and iPhone Duo.

(Replace the example search term with one that works against the final data, and change the iPhone Duo line if you skip Duo screenshots.)

## Still a judgement call

- **Real people's names (5.2.1, right of publicity).** Names of public figures as facts in a trivia game, with no photos, logos or endorsement implied, is how existing NFL trivia apps work (for example "Gridiron Trivia" is on the US store). I found no reported rejection of a player-name trivia app under 5.2.1; the reported 5.2.1 football cases were about trademarks and logos (a 2018 World Cup app told to drop FIFA terms, <https://developer.apple.com/forums/thread/107074>). Keep logos, "NFL", "Super Bowl" and "Monday Night Football" wording out of metadata and visuals. Add a line to `support.html` about how to request a name correction.
- **Team names and colours.** Abbreviation chips on team colour are the minimum-risk form. Full team names appear in `theme` strings ("Bills at Rams") and in VoiceOver labels; that is descriptive use, but a reviewer could ask. If asked, the fallback is abbreviations only.
- **nflverse licence.** CC-BY 4.0 is stated in CLAUDE.md and the web footer. nflverse itself compiles from other sources; whether the licence covers everything underneath is a question I did not research. Under 5.2.2 Apple can ask you to show you are permitted to use the data. Keep a link to the nflverse licence ready.
- **4.3(b) / 4.1 saturation.** Daily puzzle and sports-connection games are a crowded genre, and Wordle look-alikes have been rejected under 4.1 even after the name was removed (<https://developer.apple.com/forums/thread/821563>), and a similar app lost a 4.3(b) appeal (forum thread, secondary). The coloured-square share card is the closest thing to a Wordle tell. Ship the distinct visual identity, the chain motif, par scoring and archive, and say so in the notes. Existing teammate/connection games (Immaculate Grid and others) are the comparison a reviewer may make; this is from my own knowledge, not verified.
- **4.2 thinness.** The web app is the same game, and a thin v1 can draw "minimum functionality" (it hits small apps, <https://developer.apple.com/app-store/review/guidelines/>). The answer is native polish and visible depth (archive, stats, hints, accessibility, haptics). A home screen widget for today's puzzle would be a strong native signal and costs the App Group manifest entry above.
- **Category.** Sports avoids the Korean GRAC rating and Games Time Allowances. Games > Trivia has better discovery. I recommend Sports for v1.
- **iPad orientation.** Conflicting secondary reports on whether partial orientation lists limit iPad resizing on the iOS 27 SDK. Declaring all four and writing size-driven layouts is safe either way.
- **Contests answer** in the age rating (None vs Infrequent) is a reading of Apple's definition. Worst case is a 13+ rating, not a rejection.
- **DSA trader status.** Free with no income, built by one person: the non-trader option ("This is not a trader account") may fit v1. Apple says it cannot decide for you and suggests legal advice. A paid "unlimited plays" tier later probably makes you a trader, which publishes your address, phone and email on the EU product page.
- **Later paid tier.** StoreKit only (3.1.1). Keep the free game fully playable (no gate on today's puzzle). Re-do the privacy label, add Restore Purchases and Terms link, and re-check DSA.
- **Interpreted code.** 2.5.2 forbids downloading or executing code that "introduces or changes features". Bundled JS in JavaScriptCore is signed with the app and is not downloaded, which is the safe reading. The Developer Program License Agreement section on interpreted code (3.3.2) I could not read; secondary sources agree that scripts packaged in the app are allowed. **(unverified)**
- **Unverified items overall:** the questionnaire's exact wording, Apple's required-reason code page, the export-compliance page, the iOS 27 final release-note text on orientations, the TN3192 page (would not load), and any named reviewer experience with trivia or fan apps (no relevant reports found).
