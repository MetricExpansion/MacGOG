import Foundation
import SwiftyGOG

@testable import MacGOG

/// A fresh temporary folder, removed by `cleanUp()`.
struct TemporaryFolder {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "MacGOGTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )

    init() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: url)
    }
}

extension AppModel {
    /// A model with fake GOG responses and an in-memory credential store.
    static func testing(signedIn: Bool, folder: URL) -> AppModel {
        let defaults = UserDefaults(suiteName: "MacGOGTests-\(UUID().uuidString)") ?? .standard
        return AppModel(
            http: HTTPClient(transport: FixtureTransport(routes: PreviewData.routes), attempts: 1),
            store: signedIn ? InMemoryCredentialStore.signedIn() : InMemoryCredentialStore(),
            defaults: defaults,
            supportFolder: folder,
            artwork: ArtworkLoader(cache: folder.appending(path: "Artwork")),
            hooks: .none
        )
    }
}
