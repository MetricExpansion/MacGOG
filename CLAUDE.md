# MacGOG

MacGOG is a native SwiftUI macOS app for downloading, updating, repairing, launching, and syncing cloud saves for games in a user's GOG library. All GOG protocol work is done by the **SwiftyGOG** Swift package (`../SwiftyGOG`), which also ships the `gogdl` CLI. This app is a GUI over that library. It never shells out to `gogdl`.

Read these before writing code:

- `Docs/Decisions.md`: settled product and platform decisions. Don't reopen them without asking.
- `Docs/Architecture.md`: app structure, state ownership, and how each feature maps onto SwiftyGOG.
- `Docs/SwiftyGOG-API.md`: the library calls the app uses, with their semantics and gotchas.
- `Docs/Roadmap.md`: milestones in build order, each with acceptance criteria. Work through them in order.

## Ground rules

- **Library first.** If a feature needs protocol, file, or network logic, it belongs in SwiftyGOG, not the app. Examples: parsing GOG JSON, choosing builds, verifying files, or computing sizes. Make the change in `../SwiftyGOG` with tests, following that repo's `CLAUDE.md` or `Documentation/Design.md`, and keep `gogdl` working. The app holds UI, app state, persistence of app data, Keychain, and macOS integration.
- **Never parse GOG JSON in the app.** `JSONValue` results (`GOGClient.product`, `gameDetails`) are a sign a typed model is missing from the library. Add one there, as `OwnedGame`, `GameBuild`, and `BuildList` already are.
- **Never parse error strings.** Switch on `GOGError` cases. If the app needs a distinction the cases don't give, add it to the library.
- **Never parse progress text.** Use `DownloadEvent`.
- **One `GOGClient` for the app's lifetime**, owned by the app model and shared by every feature. It holds the token-refresh actor and the HTTP session.
- **Long work stays off the main actor.** SwiftyGOG's long-running entry points are `@concurrent`; call them from `@MainActor` code with `await` and they run elsewhere. Don't wrap them in `Task.detached`.
- **Cancellation is the stop button.** Cancel the `Task` running an install. SwiftyGOG never publishes partial files and keeps verified chunks, so running the same install again resumes it.

## Toolchain and build

- Xcode 27 with the Swift 6.4 toolchain; Swift 6 language mode.
- Deployment target **macOS 27.0**, because SwiftyGOG requires it.
- App target build settings:
  - Default Actor Isolation: `MainActor`
  - Strict Concurrency: Complete
  - `NonisolatedNonsendingByDefault` upcoming feature enabled, to match the library
- Dependency: add `../SwiftyGOG` as a **local package** and link only the `SwiftyGOG` product. Don't link `gogdl` or ArgumentParser.
  - The app relies on SwiftyGOG APIs (`CredentialStore`, `DownloadEvent`, `Installation`, `DownloadOptions(repeating:)`) that are on SwiftyGOG's `main` since MetricExpansion/SwiftyGOG#3. Keep `../SwiftyGOG` on an up-to-date `main`.

Build and test from the command line. Use the scheme name in the Xcode project; this assumes `MacGOG`:

```sh
xcodebuild -project MacGOG.xcodeproj -scheme MacGOG -destination 'platform=macOS' build
xcodebuild -project MacGOG.xcodeproj -scheme MacGOG -destination 'platform=macOS' test
# Library changes:
(cd ../SwiftyGOG && swift test && swift format lint --strict --recursive Sources Tests Package.swift)
```

If the folder has no Xcode project yet, create a macOS App project named `MacGOG` (SwiftUI lifecycle, Swift Testing, no Core Data). Then apply the settings above. Don't add the App Sandbox capability; see `Docs/Decisions.md`.

## Code style

Follow SwiftyGOG's conventions so the two codebases read the same:

- Four-space indentation and a 110-column line length. Run `swift format format --in-place --recursive MacGOG MacGOGTests` with the `.swift-format` file in this folder, and keep `swift format lint --strict` clean.
- One empty line between declarations. One statement per line. Prefer `switch`/`if` expressions over nested ternaries.
- Models are `Sendable` value types. Use `@Observable` classes only for UI-facing state, and isolate them to the main actor.
- No `@unchecked Sendable`, no `nonisolated(unsafe)`, and no shared mutable singletons. Pass dependencies in through initializers or the SwiftUI environment.
- Use typed throws only at closed boundaries. UI-facing async functions use plain `throws`.
- Comments explain *why*, not *what*. Document public or shared types with `///`.
- Swift Testing (`@Suite`, `@Test`, `#expect`). Test app logic without the network by injecting an `HTTPTransport` fixture and an in-memory `CredentialStore` (see `Docs/Architecture.md`, Testing).

## Security and privacy

- Keep OAuth tokens only in the Keychain, through the app's `KeychainCredentialStore`. Never write them to logs, `UserDefaults`, crash reports, or files.
- Never log signed CDN URLs or tokens. `GOGError` messages are already safe to show (host and path only).
- The app has **its own sign-in**, separate from the `gogdl` CLI. Never call `Authorization.defaultTokenPath()` or read `AUTH_PATH`/`GOG_ACCESS_TOKEN` in the app.
- Only the embedded login web view loads GOG's sign-in page. Intercept the `on_login_success` redirect and hand its URL to `Authorization.authorizationCode(from:)`, which validates it.

## Licensing

SwiftyGOG is GPL-3.0, so MacGOG is GPL-3.0 too. Keep `LICENSE` at the root, keep source headers free of conflicting licence claims, and only add dependencies with GPL-3.0-compatible licences. Note any new third-party code in `Docs/ThirdParty.md`.

## Working agreements

- Before starting a milestone, re-read its acceptance criteria in `Docs/Roadmap.md`. When it's done, tick it there and note any deviations.
- Keep commits focused, with imperative subject lines that say what changed and why.
- If a library change is needed, make it as a separate commit in `../SwiftyGOG` with tests, and mention it in the app commit that depends on it.
- Ask the user before changing anything in `Docs/Decisions.md`, adding a dependency, or changing SwiftyGOG's public API in ways that break `gogdl`.
