# Decisions

Settled decisions. Ask the user before changing any of them.

## Distribution: outside the Mac App Store

- Ship as a **Developer ID–signed, notarized** app with the **hardened runtime**.
- **No App Sandbox.** The app installs games into any folder the user picks, launches game executables and Wine, and stores install locations as plain paths. Don't add sandbox entitlements or security-scoped bookmarks.
- Notarize with `xcrun notarytool submit … --wait`, then `xcrun stapler staple`. A later milestone covers a release script and update delivery (for example, Sparkle). It isn't decided yet.

## Licence: GPL-3.0

MacGOG links SwiftyGOG, which is GPL-3.0, so MacGOG is GPL-3.0 and its source must be available to users. This is also part of why the App Store is out.

## Sign-in: separate from the `gogdl` CLI

- The app keeps its own OAuth credentials in the **Keychain**, through a `KeychainCredentialStore` that conforms to SwiftyGOG's `CredentialStore`.
- The app never reads the CLI's token file (`~/Library/Application Support/SwiftyGOG/auth.json`), `AUTH_PATH`, or `GOG_ACCESS_TOKEN`.
- Signing out of one doesn't affect the other.
- **Development exception (Debug builds only):** `MACGOG_CLI_AUTH=1` or `-UseCLIAuth YES` makes the app use the CLI's default token file (never `AUTH_PATH`), so it can be tried against a real account. Sign Out in that mode doesn't delete the CLI's credentials. Release builds don't contain this code.

## In-process library, not a subprocess

The app links SwiftyGOG directly, rather than running `gogdl` the way Heroic runs Python gogdl. This gives it typed errors, cancellation, and structured progress.

## Shared installations with the CLI are allowed

A game installed by `gogdl` can be added to the app, and the reverse also works, because both read and write the same `.gogdl/manifest.json`. SwiftyGOG's per-installation lock stops both from writing one installation at once. The losing side gets `GOGError.installation(.locked)`; show it as "This game is being changed by another program."

## Platform targets

macOS 27 or newer. The app can install the Windows, macOS, and Linux builds of a game: `GamePlatform` selects the game files, not the host. macOS builds are the default. Windows games launch through a user-configured Wine (or a compatible wrapper). The app doesn't bundle Wine.
