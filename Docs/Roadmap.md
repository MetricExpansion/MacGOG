# Roadmap

Work through the milestones in order. Each one should leave the app building, its tests passing, and something usable. Tick the boxes as criteria are met, and note deviations under the milestone.

Items tagged **(library)** are changes to `../SwiftyGOG`, made there with tests and without breaking `gogdl`.

## M0. Project skeleton

- [x] Xcode project `MacGOG`: macOS 27, Swift 6, default MainActor isolation, complete concurrency checking, hardened runtime, no sandbox.
- [x] Local package dependency on `../SwiftyGOG`, linking the `SwiftyGOG` product only. It builds against SwiftyGOG `main`.
- [x] `AppModel` creates one `HTTPClient`, `Authorization(store:)`, and `GOGClient`, and injects them through the environment.
- [x] Test target with a fake `HTTPTransport` and an in-memory `CredentialStore`. One passing test constructs `AppModel` with fakes.
- [x] `.swift-format` lint is clean. `LICENSE` (GPL-3.0) is present.

Notes:

- The project uses Xcode 27's text project format (`project.xcproj`). Build with Xcode-beta2 (Xcode 27.2): `DEVELOPER_DIR=/Applications/Xcode-beta2.app/Contents/Developer`.
- Fakes (`FixtureTransport`, `InMemoryCredentialStore`, `PreviewData`, `AppModel.preview`) live in the app target under `#if DEBUG` in `Support/PreviewSupport.swift`, so previews and tests share them.

## M1. Sign in and sign out

- [x] `KeychainCredentialStore`, with unit tests for round trip, delete, and not-found.
- [x] Login sheet: a `WKWebView` that intercepts `on_login_success` and calls `auth.login(code:)`. Denied or invalid redirects show the library's error.
- [x] `SessionModel` drives the root view: signed out shows a Sign In screen, signed in shows the library.
- [x] Sign Out (in the menu and settings) calls `logout()` and returns to the Sign In screen.
- [x] An unreadable Keychain item or an expired session leads back to sign-in, not to a stuck error.

Notes:

- `SessionModel.State.signedIn` carries no user ID: there's no profile call yet, and fetching the token at launch could refresh it over the network.
- The login sheet is built to the spec but hasn't been tried with a real sign-in yet. Debug builds can borrow the CLI's sign-in instead (`-UseCLIAuth YES`; see `Decisions.md`).

## M2. Library

- [x] **(library)** A typed `ProductDetails` from `api.gog.com/products/{id}?expand=downloads,expanded_dlcs,description`: title, artwork (`images`: logo, background, icon; normalize protocol-relative `//` URLs to `https`), DLC list, platforms, and the languages each platform's installers ship. Parse it at the edge as `GameBuild` and `OwnedGame` are parsed; keep tests with fixture JSON.
- [x] Optionally **(library)**: include the library listing's image in `OwnedGame`, if `getFilteredProducts` returns one, so the grid doesn't need one request per game.
- [x] Library grid or list with search, platform badges, and install state (Installed, Update available, Not installed).
- [x] Game detail view: artwork, description, DLC, builds (`buildList`), and installed info.
- [x] Artwork is loaded through `URLSession` with a disk cache in `~/Library/Caches/MacGOG`.

Notes:

- Library changes: MetricExpansion/SwiftyGOG commits "Add typed product details for store pages" and "Add library tile artwork to OwnedGame". `productDetails` is unauthenticated (the endpoint is public). Tiles use GOG's 392×220 `_392.jpg` images.
- Descriptions are shown as plain text (`HTMLText`), because AppKit's HTML import would fetch remote images.

## M3. Install, with progress

- [x] Settings: default library folder, default platform (`.osx`), default language, worker count, and concurrent jobs.
- [x] Install sheet: platform, language (from the product's languages, falling back to `Language.all`), DLC selection, branch with an optional password, and a destination. It shows `downloadSize` and `diskSize` from `ManifestService.plan`.
- [x] Free-space check before enqueueing. **(library, optional)** a helper that accounts for files already present.
- [x] `DownloadQueue` with `ProgressSink` throttling, pause, resume, and cancel, and a Downloads window or panel showing per-job progress, speed, ETA, and phase.
- [x] Prevent sleep while running, confirm before quitting, and resume unfinished jobs on relaunch.
- [x] Completion and failure notifications, and a Dock badge.
- [x] `InstallRegistry` persisted. Installed games appear in the library after a restart.

Notes:

- The free-space check compares `plan.diskSize` with the volume's available capacity, so it's conservative when files are already present. The library helper is still open.
- Tried against a real account: Beneath a Steel Sky (93 MB, macOS) installed, paused, resumed, and reappeared after relaunch.

## M4. Updates, repair, and installed-game management

- [x] Background update checks with `availableUpdate`, plus an Update button that uses `Installation.update` with saved choices. The update sheet can change the language or DLC.
- [x] Verify or Repair, with `Installation.repair`.
- [x] Add existing folder (installed by SwiftyGOG, `gogdl`, or Galaxy). Handle a missing folder: locate it or remove it from the library.
- [x] Uninstall: remove the folder after confirmation, and remove it from the registry. **(library, optional)** a safe `uninstall` that deletes only planned files, the support folder, and `.gogdl`.
- [x] Error mapping covers `.locked`, `.anotherProduct`, `.buildUnavailable`, and `.noMatchingDepots`, with recovery actions.

Notes:

- Uninstall moves the folder to the Trash rather than deleting it. The library's safe `uninstall` is still open.
- A game folder with a damaged manifest offers Reinstall, which installs over the folder; Galaxy installs offer Verify with GOG, which does the same with their platform and language.

## M5. Launching

- [x] Play button through `GameLauncher`, with Running state and Stop.
- [ ] Verify macOS depot games launch correctly. If GOG's play task points inside an `.app` bundle, starting through `/usr/bin/env` may be wrong. Fix it in the library's `GameLauncher` if needed.
- [x] Windows games: settings for the Wine binary, a per-game prefix, and an optional wrapper. Play is disabled with a clear message until they're configured.
- [x] Play task picker when a game has several tasks.

Notes:

- Library change: "Launch the executable inside macOS app bundle play tasks". GOG's macOS depots install as `<Game>.app` with play tasks such as `Contents/MacOS/GOGLauncher`, which run directly. Not yet confirmed by launching a real game, so the second item stays open.
- URL play tasks appear as links in the Play menu.

## M6. Cloud saves

- [x] **(library)** Resolve a game's save locations. Heroic reads GOG's remote config for the game's client ID, which lists `cloudStorage` locations with placeholders such as `<?SAVED_GAMES?>` and `<?INSTALL?>`, and maps the placeholders per platform. Study Heroic's gogdl implementation, port the resolution with tests, and expose it as `CloudSaves.locations(id:platform:installation:)`.
- [x] Per-game "last synced" timestamp in app state.
- [x] Sync before launch and after exit (configurable): a dry run, then apply, with a conflict dialog (keep local or keep cloud) that maps to `.forceUpload`/`.forceDownload`.
- [x] Manual Sync Now and Delete Cloud Saves (`CloudSaves.clear`), with confirmation.

Notes:

- Library change: "Resolve cloud save locations from Galaxy's remote configuration" adds `CloudSaves.locations(id:platform:installation:winePrefix:home:user:)` (not `locations(id:platform:installation:)`), and `gogdl save-locations`.
- Sync state is per game and per save location, in `cloudsaves.json`. A sync failure around launch is shown but never blocks play.
- Not yet tried against real cloud saves.

## M7. Release

- [ ] Release configuration: Developer ID signing, notarization script (`notarytool`, `stapler`), and a DMG or ZIP.
- [ ] App update mechanism (to be decided, for example Sparkle; ask before adding the dependency).
- [ ] About window with GPL-3.0 notice and source link; `Docs/ThirdParty.md` is up to date. (The About panel exists; release packaging doesn't.)

## Library follow-ups from the SwiftyGOG audit

These items in `../SwiftyGOG/Documentation/AppReadiness.md` are still open. Pick them up when a milestone needs them:

- `GOGError` recovery classification, and a coarse transport reason (offline, timed out, TLS) so the app can say "You're offline".
- Configurable User-Agent on `HTTPClient` (set it to `MacGOG/<version>`).
- Faster resume: a journal of completed files, to avoid re-hashing everything after a pause. This needs a deliberate trade-off decision.
- Parallel chunk fetching within a single large file.
- Exposing the launched process (PID, exit stream) rather than only awaiting it.
