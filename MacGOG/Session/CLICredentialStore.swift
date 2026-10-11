#if DEBUG
    import Foundation
    import SwiftyGOG

    /// Development only: shares the `gogdl` CLI's sign-in, so the app can be tried against a real
    /// account without signing in again. Release builds always use the Keychain.
    ///
    /// Opt in with the `MACGOG_CLI_AUTH=1` environment variable or the `-UseCLIAuth YES` argument.
    /// The CLI's default file is used directly, never `AUTH_PATH`. Refreshed tokens are written back,
    /// which SwiftyGOG merges safely, but signing out never deletes the CLI's credentials.
    nonisolated struct CLICredentialStore: CredentialStore {
        static let file = URL.applicationSupportDirectory.appending(path: "SwiftyGOG/auth.json")

        private let store = FileCredentialStore(url: file)

        static func requested(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            defaults: UserDefaults = .standard
        ) -> CLICredentialStore? {
            environment["MACGOG_CLI_AUTH"] == "1" || defaults.bool(forKey: "UseCLIAuth")
                ? CLICredentialStore() : nil
        }

        func load() throws -> [String: OAuthToken] { try store.load() }

        func save(_ credentials: [String: OAuthToken]) throws { try store.save(credentials) }

        /// Leaves the CLI signed in; the app is signed out until it relaunches.
        func delete() throws {}
    }
#endif
