# Roadmap

Work through the milestones in order. Each one should leave the app building, its tests passing, and something usable. Tick the boxes as criteria are met, and note deviations under the milestone.

Items tagged **(library)** are changes to `../SwiftyGOG`, made there with tests and without breaking `gogdl`.

## M0. Project skeleton

- [ ] Xcode project `MacGOG`: macOS 27, Swift 6, default MainActor isolation, complete concurrency checking, hardened runtime, no sandbox.
- [ ] Local package dependency on `../SwiftyGOG`, linking the `SwiftyGOG` product only. It builds against SwiftyGOG `main`.
- [ ] `AppModel` creates one `HTTPClient`, `Authorization(store:)`, and `GOGClient`, and injects them through the environment.
- [ ] Test target with a fake `HTTPTransport` and an in-memory `CredentialStore`. One passing test constructs `AppModel` with fakes.
- [ ] `.swift-format` lint is clean. `LICENSE` (GPL-3.0) is present.

## M1. Sign in and sign out

- [ ] `KeychainCredentialStore`, with unit tests for round trip, delete, and not-found.
- [ ] Login sheet: a `WKWebView` that intercepts `on_login_success` and calls `auth.login(code:)`. Denied or invalid redirects show the library's error.
- [ ] `SessionModel` drives the root view: signed out shows a Sign In screen, signed in shows the library.
- [ ] Sign Out (in the menu and settings) calls `logout()` and returns to the Sign In screen.
- [ ] An unreadable Keychain item or an expired session leads back to sign-in, not to a stuck error.

## M2. Library

- [ ] **(library)** A typed `ProductDetails` from `api.gog.com/products/{id}?expand=downloads,expanded_dlcs,description`: title, artwork (`images`: logo, background, icon; normalize protocol-relative `//` URLs to `https`), DLC list, platforms, and the languages each platform's installers ship. Parse it at the edge as `GameBuild` and `OwnedGame` are parsed; keep tests with fixture JSON.
- [ ] Optionally **(library)**: include the library listing's image in `OwnedGame`, if `getFilteredProducts` returns one, so the grid doesn't need one request per game.
- [ ] Library grid or list with search, platform badges, and install state (Installed, Update available, Not installed).
- [ ] Game detail view: artwork, description, DLC, builds (`buildList`), and installed info.
- [ ] Artwork is loaded through `URLSession` with a disk cache in `~/Library/Caches/MacGOG`.

## M3. Install, with progress

- [ ] Settings: default library folder, default platform (`.osx`), default language, worker count, and concurrent jobs.
- [ ] Install sheet: platform, language (from the product's languages, falling back to `Language.all`), DLC selection, branch with an optional password, and a destination. It shows `downloadSize` and `diskSize` from `ManifestService.plan`.
- [ ] Free-space check before enqueueing. **(library, optional)** a helper that accounts for files already present.
- [ ] `DownloadQueue` with `ProgressSink` throttling, pause, resume, and cancel, and a Downloads window or panel showing per-job progress, speed, ETA, and phase.
- [ ] Prevent sleep while running, confirm before quitting, and resume unfinished jobs on relaunch.
- [ ] Completion and failure notifications, and a Dock badge.
- [ ] `InstallRegistry` persisted. Installed games appear in the library after a restart.

## M4. Updates, repair, and installed-game management

- [ ] Background update checks with `availableUpdate`, plus an Update button that uses `Installation.update` with saved choices. The update sheet can change the language or DLC.
- [ ] Verify or Repair, with `Installation.repair`.
- [ ] Add existing folder (installed by SwiftyGOG, `gogdl`, or Galaxy). Handle a missing folder: locate it or remove it from the library.
- [ ] Uninstall: remove the folder after confirmation, and remove it from the registry. **(library, optional)** a safe `uninstall` that deletes only planned files, the support folder, and `.gogdl`.
- [ ] Error mapping covers `.locked`, `.anotherProduct`, `.buildUnavailable`, and `.noMatchingDepots`, with recovery actions.

## M5. Launching

- [ ] Play button through `GameLauncher`, with Running state and Stop.
- [ ] Verify macOS depot games launch correctly. If GOG's play task points inside an `.app` bundle, starting through `/usr/bin/env` may be wrong. Fix it in the library's `GameLauncher` if needed.
- [ ] Windows games: settings for the Wine binary, a per-game prefix, and an optional wrapper. Play is disabled with a clear message until they're configured.
- [ ] Play task picker when a game has several tasks.

## M6. Cloud saves

- [ ] **(library)** Resolve a game's save locations. Heroic reads GOG's remote config for the game's client ID, which lists `cloudStorage` locations with placeholders such as `<?SAVED_GAMES?>` and `<?INSTALL?>`, and maps the placeholders per platform. Study Heroic's gogdl implementation, port the resolution with tests, and expose it as `CloudSaves.locations(id:platform:installation:)`.
- [ ] Per-game "last synced" timestamp in app state.
- [ ] Sync before launch and after exit (configurable): a dry run, then apply, with a conflict dialog (keep local or keep cloud) that maps to `.forceUpload`/`.forceDownload`.
- [ ] Manual Sync Now and Delete Cloud Saves (`CloudSaves.clear`), with confirmation.

## M7. Release

- [ ] Release configuration: Developer ID signing, notarization script (`notarytool`, `stapler`), and a DMG or ZIP.
- [ ] App update mechanism (to be decided, for example Sparkle; ask before adding the dependency).
- [ ] About window with GPL-3.0 notice and source link; `Docs/ThirdParty.md` is up to date.

## Library follow-ups from the SwiftyGOG audit

These items in `../SwiftyGOG/Documentation/AppReadiness.md` are still open. Pick them up when a milestone needs them:

- `GOGError` recovery classification, and a coarse transport reason (offline, timed out, TLS) so the app can say "You're offline".
- Configurable User-Agent on `HTTPClient` (set it to `MacGOG/<version>`).
- Faster resume: a journal of completed files, to avoid re-hashing everything after a pause. This needs a deliberate trade-off decision.
- Parallel chunk fetching within a single large file.
- Exposing the launched process (PID, exit stream) rather than only awaiting it.
