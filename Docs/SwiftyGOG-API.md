# SwiftyGOG API for the app

This is a map of the SwiftyGOG calls MacGOG uses. The source in `../SwiftyGOG/Sources/SwiftyGOG` is authoritative. Read a function's doc comment before relying on details here. Everything below is `Sendable`.

## Client and sign-in

```swift
let http = HTTPClient()                                   // one per app; HTTPClient(transport:) in tests
let auth = Authorization(store: KeychainCredentialStore(), http: http)
let client = GOGClient(auth: auth, http: http)
```

- `Authorization` is an actor. With `init(store:accessToken:http:)`, the store isn't read until credentials are first needed, so an unreadable store shows up as an error on first use rather than at launch.
- `try await auth.hasStoredCredentials`: re-reads the store. This is how the app decides whether the user is signed in at launch.
- `Authorization.loginURL()`: the URL to load in the login web view.
- `Authorization.authorizationCode(from: String)`: accepts the full `https://embed.gog.com/on_login_success?...` redirect URL (or a bare code), validates it, and throws `GOGError.authentication(...)` for denied, ambiguous, or malformed input.
- `try await auth.login(code:)`: exchanges the code and saves the token to the store. Throws `.authentication(.credentialPathRequired)` if the store is `nil`.
- `try await auth.logout()`: deletes stored credentials and discards in-flight refreshes. Afterwards, calls fail with `.authentication(.notSignedIn)`.
- `OAuthToken.userID` identifies the account. There's no profile or username call yet; see Roadmap.

`CredentialStore` is the protocol the app implements for the Keychain:

```swift
public protocol CredentialStore: Sendable {
    func load() throws -> [String: OAuthToken]   // empty when nothing stored
    func save(_ credentials: [String: OAuthToken]) throws
    func delete() throws                          // succeeds when nothing stored
}
```

The dictionary is keyed by OAuth client ID. Besides the main account entry, it holds per-game entries used for cloud saves. Store the whole dictionary as one JSON-encoded Keychain item (`OAuthToken` is `Codable`). `Authorization` re-reads the store before refreshing, and merges its writes into the latest contents.

## Library

- `client.searchLibrary(_ text: String? = nil) -> [OwnedGame]` returns owned games (`id`, `title`, `platforms`), excluding DLC. `nil` or empty text lists everything. Pages are fetched internally.
- `client.ownedGames() -> [String]` returns every owned product ID, including DLC.
- `client.buildList(id, platform:password:) -> BuildList` returns `builds: [GameBuild]`, newest first (`id`, `version`, `branch`, `generation`, `published`, `publishedDate`, `isPublic`), plus `hasPrivateBranches`. It doesn't work for `.linux`, which uses installers. Set `DownloadOptions.build` to a build's `id` to install that build, older ones included; `Installation.update(options:)` with it downgrades or upgrades in place.
- `client.productDetails(id) -> ProductDetails`: title, `images` (logo, background, icon), `lead`/`fullDescription` HTML, `releaseDate`, `platforms`, `dlcs: [ProductDLC]`, and `languages(for: platform) -> [Language]` from the installers. Unauthenticated.
- `OwnedGame.imageURL`: the 392×220 library tile.
- `client.product(id)` and `client.gameDetails(id)` return raw `JSONValue`. **Don't use them in the app.** Add typed models to the library instead.

## Planning and installing

```swift
var options = DownloadOptions(platform: .osx, language: "en-US")   // see validated()
let plan = try await ManifestService(client: client).plan(id, options: options)
// plan.folder, plan.downloadSize, plan.diskSize, plan.version, plan.buildID, plan.files.count
let result = try await Downloader(client: client).install(
    plan, at: libraryFolder.appending(path: plan.folder),
    workers: options.workers, useDeltas: options.useDeltas,
    progress: { event in /* any thread */ })
```

- `DownloadOptions.validated()` normalizes the language to a GOG code and throws `.invalidArgument(.language | .generation | .workerCount)`. `plan` calls it too.
- `Language.all` is the full GOG language list, for a picker. `Language.match(_:)` maps names, locales, and codes.
- `install(at:)` takes the **game folder itself**. For a new install, that's the user's library folder plus `plan.folder`, as `gogdl download` does.
- `install` is `@concurrent`. Cancelling its task stops it cleanly, and running the same install again resumes from verified chunks.
- `DownloadResult` has `installed`, `skipped`, and `downloadedBytes`.

### Progress: `DownloadEvent`

The callback is `@Sendable` and is called concurrently from worker tasks. Never touch UI state in it directly. Accumulate the events and publish them to the main actor at a throttled rate (Architecture, Downloads).

| Event | Meaning |
|---|---|
| `.started(files:diskSize:downloadSize:)` | Totals. `diskSize` is the denominator for progress. `downloadSize` is an upper bound on network bytes. |
| `.preparingPatches` | Update only: looking for xdelta patches. |
| `.patchesUnavailable` | Falling back to chunk downloads. Informational. |
| `.downloaded(bytes:)` | Network bytes received, per chunk or range. Use it for speed and ETA. |
| `.fileVerified(path:size:)` | Already correct on disk. Counts toward progress. |
| `.fileInstalled(path:size:patched:)` | Written and verified. Counts toward progress. |
| `.patchFailed(path:)` | That file falls back to chunks. Informational. |
| `.finalizing` | Directories, links, removals, and the saved plan. Short. |

Progress fraction = (sum of `fileVerified` sizes + sum of `fileInstalled` sizes) / `diskSize`.

## Installed games: `Installation`

```swift
let installation = try Installation(at: gameFolder)     // throws if no .gogdl/manifest.json
installation.plan          // InstallPlan: product, platform, buildID, version, language, choices, files
installation.options       // DownloadOptions repeating platform, language, branch, DLC choice
try await installation.availableUpdate(client: client, password: nil) // AvailableUpdate? (buildID, version)
try await installation.update(client: client, options: nil, progress: …)  // nil = repeat saved choices
try await installation.repair(client: client, progress: …)                // re-verify the installed build
```

- `availableUpdate` compares against the newest build on the installed branch. For Linux it compares installer versions.
- Installs remember a non-default support folder in `plan.supportPath`. The app doesn't need to track it.
- `InstalledGame.read(at:)` reads GOG's own metadata (`goggame-*.info`): title, play tasks, DLC IDs. Use it to import a folder installed by Galaxy or the CLI, and for launch information. `playTasks: [PlayTask]` types the tasks; pass `task.index` as `LaunchOptions.task`.

## Launching

```swift
let command = try GameLauncher.command(root: gameFolder, id: productID, options: LaunchOptions(
    platform: plan.platform, wine: winePath, winePrefix: prefix, noWine: false, wrapper: [], arguments: []))
let status = try await GameLauncher.run(command)   // waits for exit; cancel the task to terminate
```

- `command` picks the primary play task (or `LaunchOptions.task`) and resolves paths case-insensitively inside the game folder.
- `run` resolves the executable via `/usr/bin/env` and inherits the app's environment. When a macOS play task points at an `.app` bundle, `command` runs the bundle's `CFBundleExecutable`.

## Cloud saves

```swift
let saves = CloudSaves(client: client)
let preview = try await saves.sync(id: id, platform: .osx, root: saveFolder, name: "__default",
                                   since: lastSync, preference: .automatic, dryRun: true)
// preview.direction: .upload / .download / .none / .conflict; preview.transfer, preview.delete
```

- Run with `dryRun: false` and the user's chosen `SavePreference` (`.forceUpload` or `.forceDownload` resolves a conflict) to apply. After a successful non-dry run, store `Date().timeIntervalSince1970` as the game's new `since` value. If `direction == .none`, keep the old one.
- Without a forced preference, a conflict throws `.cloudSaves(.conflict)`.
- `saves.locations(id:platform:installation:winePrefix:)` returns `[SaveLocation]` (`name`, `url`) from Galaxy's remote config; pass each as `sync(root: location.url, name: location.name)`. Empty when the game has no cloud saves on that platform.

## Errors: `GOGError`

Switch on cases; `description` is user-presentable. The ones the UI must handle specially:

| Case | UI |
|---|---|
| `.authentication(.notSignedIn)`, `.authentication(.invalidCredentialStore)` | Show sign-in. Call `logout()` first for an invalid store. |
| `.http(status: 401, _)` after refresh | Same as not signed in. |
| `.transport(host:)` | "Can't reach GOG"; offer retry. |
| `.installation(.locked)` | "Being changed by another program"; offer retry. |
| `.installation(.anotherProduct)` | The folder holds a different game; ask for another folder. |
| `.unsupported(.buildUnavailable)` | Branch or build gone, or a password is needed. |
| `.unsupported(.noMatchingDepots)` | No files for that language or DLC choice; ask for another language. |
| `.cloudSaves(.conflict)` | Conflict dialog: keep local or keep cloud. |
| `.checksumMismatch` | Corrupt data; offer retry, since verified chunks are kept. |

`CancellationError` means the user cancelled; don't show it as an error.

## Testing hooks

- `HTTPClient(transport: some HTTPTransport, attempts: 1)`: a fake transport returns canned `HTTPResponse` and `HTTPDownload` values. See `../SwiftyGOG/Tests/SwiftyGOGTests/CoreTests.swift` and `UpdateCheckTests.swift` for fixtures to copy.
- `Authorization(store: InMemoryStore(), http:)` or `try Authorization(accessToken: "test", http:)` to skip OAuth.
