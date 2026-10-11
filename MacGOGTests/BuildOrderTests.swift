import Foundation
import SwiftyGOG
import Testing

@testable import MacGOG

@MainActor
@Suite struct BuildOrderTests {
    @Test func comparesByPublicationDate() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let list = try await AppModel.testing(signedIn: true, folder: folder.url).client
            .buildList(PreviewData.witcherID, platform: .osx)
        // 57 (beta, May 2024) is listed after 55 (June 2023) but is newer.
        #expect(list.isBuild("57", olderThan: "55") == false)
        #expect(list.isBuild("54", olderThan: "55") == true)
        #expect(list.isBuild("12", olderThan: "56") == true)
        #expect(list.isBuild("56", olderThan: "55") == false)
        #expect(list.isBuild("999", olderThan: "55") == nil)
    }
}
