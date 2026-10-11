# MacGOG

A native macOS app for your GOG library: browse, install, update, repair, and launch games, and sync their cloud saves. Built with SwiftUI on the [SwiftyGOG](https://github.com/MetricExpansion/SwiftyGOG) library.

Status: early development. See `Docs/Roadmap.md`.

## Building

Requires Xcode 27 and macOS 27. Clone SwiftyGOG next to this folder (`../SwiftyGOG`), then open `MacGOG.xcodeproj` and build the `MacGOG` scheme.

Command line (Xcode 27.2 beta):

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta2.app/Contents/Developer
xcodebuild -project MacGOG.xcodeproj -scheme MacGOG -destination 'platform=macOS' test
```

### Development options (Debug builds only)

- `-UsePreviewData YES`: run on the same fake account as the SwiftUI previews, with no network or Keychain.
- `-UseCLIAuth YES` or `MACGOG_CLI_AUTH=1`: use the `gogdl` CLI's sign-in instead of signing in again.
- `-libraryFolder /some/path`: install into another folder for this run, without changing your settings.

## Licence

GPL-3.0; see `LICENSE`.
