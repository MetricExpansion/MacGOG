import Foundation
import SwiftyGOG
import Testing

@testable import MacGOG

@MainActor
@Suite struct AppModelTests {
    @Test func signedOutAtLaunchWithoutCredentials() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let model = AppModel.testing(signedIn: false, folder: folder.url)
        await model.start()
        #expect(model.session.state == .signedOut)
        #expect(model.library.games.isEmpty)
    }

    @Test func signedInLoadsLibraryAndSignOutClearsIt() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let model = AppModel.testing(signedIn: true, folder: folder.url)
        await model.start()
        #expect(model.session.state == .signedIn)
        await model.refreshLibrary()
        #expect(
            model.library.games.map(\.title) == [
                "Gwent: The Witcher Card Game", "The Witcher: Enhanced Edition", "Tyrian 2000",
            ]
        )
        #expect(model.library.ownedIDs.contains(PreviewData.dlcID))
        #expect(model.library.game(PreviewData.witcherID)?.imageURL?.scheme == "https")
        await model.session.signOut()
        #expect(model.session.state == .signedOut)
        #expect(model.library.games.isEmpty)
    }

    @Test func productDetailsAreTyped() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let model = AppModel.testing(signedIn: true, folder: folder.url)
        await model.library.refresh()
        let details = try await model.library.details(for: PreviewData.witcherID)
        #expect(details.languages(for: .windows).map(\.code).count == 3)
        #expect(model.library.ownedDLCs(of: details).map(\.title) == ["Adventure Pack"])
    }

    @Test func libraryCacheSurvivesRelaunch() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        await AppModel.testing(signedIn: true, folder: folder.url).library.refresh()
        let relaunched = AppModel.testing(signedIn: true, folder: folder.url)
        relaunched.library.loadCached()
        #expect(relaunched.library.games.count == 3)
    }

    @Test func unreadableCredentialsSignOut() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let model = AppModel(
            http: HTTPClient(transport: FixtureTransport(routes: [:]), attempts: 1),
            store: BrokenStore(),
            defaults: UserDefaults(suiteName: "MacGOGTests-\(UUID().uuidString)") ?? .standard,
            supportFolder: folder.url,
            artwork: ArtworkLoader(cache: folder.url),
            hooks: .none
        )
        await model.session.restore()
        #expect(model.session.state == .signedOut)
    }
}

private struct BrokenStore: CredentialStore {
    func load() throws -> [String: OAuthToken] { throw GOGError.authentication(.invalidCredentialStore) }

    func save(_ credentials: [String: OAuthToken]) throws {}

    func delete() throws {}
}
