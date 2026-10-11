# Architecture

## Shape

```
MacGOGApp (@main, SwiftUI App)
 └─ AppModel (@MainActor @Observable) ─ owns the single GOGClient
     ├─ SessionModel      sign-in state, login/logout
     ├─ LibraryModel      owned games, search, artwork
     ├─ InstallRegistry   which folders hold installed games (persisted)
     ├─ DownloadQueue     install/update/repair jobs and their progress
     ├─ LaunchController  running games
     ├─ CrossOverModel    CrossOver bottles, and which game uses which
     ├─ CloudSaveModel    save locations, sync state, conflicts
     └─ AppSettings       library folder, Wine path, defaults (UserDefaults)
```

Inject `AppModel`, or the individual models, through the SwiftUI environment (`.environment(model)`). Views never create a `GOGClient`, `Downloader`, or `ManifestService`; they call model methods.

Suggested source layout:

```
MacGOG/
  App/            MacGOGApp.swift, AppModel.swift, Settings.swift
  Session/        SessionModel.swift, KeychainCredentialStore.swift, LoginView.swift (WKWebView)
  Library/        LibraryModel.swift, LibraryView.swift, GameDetailView.swift
  Installs/       InstallRegistry.swift, DownloadQueue.swift, InstallSheet.swift, DownloadsView.swift
  Launch/         LaunchController.swift
  CloudSaves/     (Roadmap M6)
  Support/        Formatting (bytes, durations), error presentation
MacGOGTests/      Swift Testing suites, fixtures (fake HTTPTransport, in-memory CredentialStore)
```

## Concurrency model

- Every model is `@MainActor @Observable`, which is also the target's default isolation.
- SwiftyGOG calls are `async` and `@concurrent` where they're long-running, so a model method can `await` them directly. They run off the main actor and resume on it.
- Each user-initiated operation is an unstructured `Task` stored on the model that owns it, keyed by product ID or job ID, so it can be cancelled. Never leave a task un-owned.
- Progress callbacks arrive on arbitrary threads (see Downloads). That's the only place the app needs a thread-safe mutable container. Use `Synchronization.Mutex` inside a `final class … : Sendable`, never `@unchecked Sendable`.

## Session

- **KeychainCredentialStore** conforms to `CredentialStore`. It holds one generic-password item (service `com.<team>.MacGOG.credentials`, account `gog`) containing the JSON-encoded `[String: OAuthToken]`.
  - `load` returns `[:]` for `errSecItemNotFound`.
  - `save` is an add-or-update.
  - `delete` ignores not-found.
  - Use `kSecAttrAccessibleAfterFirstUnlock`, and don't sync it (`kSecAttrSynchronizable` false).
  - Throw a small app error with the `OSStatus` for anything else.
- **SessionModel** state is one of: `unknown`, `signedOut`, `signingIn`, `signedIn(userID:)`, or `failed(GOGError)`.
  - At launch it checks `try await auth.hasStoredCredentials`. If that throws `.invalidCredentialStore`, call `logout()`, then treat the user as signed out.
- **Login** is a sheet with a `WKWebView` (wrapped in `NSViewRepresentable`) that loads `Authorization.loginURL()`.
  - In `webView(_:decidePolicyFor:decisionHandler:)`, when the URL host is `embed.gog.com` and the path is `/on_login_success`, cancel the navigation.
  - Then call `Authorization.authorizationCode(from: url.absoluteString)` and `auth.login(code:)`.
  - Use a non-persistent `WKWebsiteDataStore`, so GOG's web cookies don't outlive the sheet, unless the user asks to stay signed in on the web too.
  - `ASWebAuthenticationSession` doesn't work here, because the callback is an `https` URL on GOG's domain.
- **Sign out** calls `auth.logout()`, then clears the library model. Installed games stay on disk and in the registry.
- When any call fails with `.authentication(.notSignedIn)`, the session moves to `signedOut` and the UI presents sign-in.

## Library

- `LibraryModel.refresh()` calls `client.searchLibrary(nil)` and stores `[OwnedGame]`. Search filters locally for responsiveness, and can also call `searchLibrary(text)`.
- `LibraryModel.details(for:)` fetches `client.productDetails(id)` once per game: artwork, description, DLC, platforms, and installer languages. Library tiles use `OwnedGame.imageURL`.
- Join the library with `InstallRegistry` by product ID to show Installed, Update available, or Not installed.

## Install registry

- Persist an array of `{productID, path}` in `~/Library/Application Support/MacGOG/installations.json`. Write it atomically. This is app state; SwiftyGOG's `.gogdl/manifest.json` inside each game folder remains the source of truth for what's installed.
- At launch, for each entry, try `Installation(at:)`:
  - On success, keep the `Installation` value.
  - If the folder is missing, show "Missing — locate or remove".
  - If the manifest is unreadable, show "Needs repair" and offer re-download.
- **Add existing game:** pick a folder. If `Installation(at:)` succeeds, it's a SwiftyGOG or `gogdl` install. If only `InstalledGame.read(at:)` succeeds, it's a Galaxy or other install; offer to verify it, which installs over it by planning with matching options.
- **Update checks:** on launch and on demand, call `availableUpdate(client:)` for each installation, with bounded concurrency (for example, 4 at a time). Cache the results in memory.

## Downloads

- **DownloadQueue** holds `[DownloadJob]`.
  - Each job has a kind (`install(plan, folder)`, `update(Installation)`, or `repair(Installation)`), a state (`queued`, `running`, `paused`, `failed(Error)`, or `finished(DownloadResult)`), and a `JobProgress`.
  - Run **one job per installation folder at a time**, which SwiftyGOG also enforces with a lock, and a small number overall (default 1, configurable).
  - The `workers` setting (1…128, default 4) is per job.
- **Install flow:**
  1. The user picks platform, language, and DLC in an install sheet.
  2. `ManifestService.plan` shows `downloadSize` and `diskSize`.
  3. The user confirms the destination: library folder plus `plan.folder`.
  4. Check free space with `URL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])` against `diskSize`, until the library offers a helper.
  5. Enqueue the job.
- **Progress plumbing:**
  - The job owns a `final class ProgressSink: Sendable` with a `Mutex<Counters>`, holding the disk total, completed bytes, downloaded bytes, the current phase, and the last file.
  - The `progress:` closure only updates counters under the lock.
  - A main-actor `Task` on the job samples the sink every 250 ms. It updates the observable `JobProgress` (fraction, bytes per second from a moving window over `downloaded`, ETA, and phase text).
  - Never send one main-actor hop per event: big games emit tens of thousands.
- **Pause** cancels the job's task and marks the job `paused`. **Resume** re-runs the same operation: verified chunks are reused, and installed files are re-verified.
- **Cancel** for a new install does the same as pause, then offers to delete the partial folder.
- While any job runs, hold `ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason:)`. When the user quits with jobs running, confirm first. On next launch, offer to resume unfinished jobs (persist the queue alongside the registry).
- Show a Dock badge, or a menu bar extra, with overall progress. Post a user notification on completion or failure.

## Launching

- `LaunchController.launch(installation)`:
  1. Build `LaunchOptions` from the installation's platform and Settings (Wine path, prefix per game, wrapper).
  2. Call `GameLauncher.command`, then run `GameLauncher.run` in a task keyed by product ID.
  3. Mark the game Running until the task returns.
  4. **Stop** cancels the task, which terminates the process.
- Windows games run in a CrossOver bottle (`CrossOverModel`, one bottle per game, created on first play) or through a configured Wine binary with a prefix per game. Play is greyed out with an explanation until one is available. `LaunchController.windowsEnvironment(for:)` tells cloud saves where the game's `C:` drive is.
- Verify macOS game launching early with a real game. GOG macOS depots are app bundles, and `/usr/bin/env` may not be the right way to start them (Roadmap M5).

## Cloud saves

`CloudSaveModel` finds a game's save locations with `CloudSaves.locations` (Windows games map into their Wine prefix). Before launch and after exit it runs a dry-run sync per location, asks the user to keep local or cloud saves on a conflict, then applies. It stores each location's `since` timestamp in `cloudsaves.json`.

## Error presentation

A single `presentableError(_ error: any Error) -> PresentableError?` maps `GOGError` cases to a title, a message, and recovery actions (Sign In, Retry, Choose Folder). It returns `nil` for `CancellationError`. See the table in `SwiftyGOG-API.md`. Views show it in an alert or an inline banner. Never show raw `String(describing:)` of non-GOG errors without a generic title.

## Testing

- Unit-test models with a fake `HTTPTransport` (canned JSON per URL path) and an in-memory `CredentialStore`. Copy the fixture patterns from SwiftyGOG's `Tests/SwiftyGOGTests`.
- Test `ProgressSink` math, registry persistence and recovery, `KeychainCredentialStore` (Keychain is available to unit tests on macOS; use a unique service name per test and delete it afterwards), and error mapping.
- SwiftUI previews use the same fakes through a `AppModel.preview` factory.
- Don't hit the real GOG API in automated tests.
