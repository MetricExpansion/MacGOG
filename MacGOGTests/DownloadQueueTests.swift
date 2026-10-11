import Foundation
import SwiftyGOG
import Testing

@testable import MacGOG

@MainActor
@Suite struct DownloadQueueTests {
    @Test func unfinishedJobsComeBackPaused() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let model = AppModel.testing(signedIn: true, folder: folder.url)
        // Two jobs at once, so the second waits in the queue.
        model.settings.concurrentJobs = 1
        let game = folder.url.appending(path: "Witcher")
        let first = model.downloads.enqueue(
            .install(PreviewData.witcherPlan, folder: game),
            productID: PreviewData.witcherID,
            title: "Witcher"
        )
        let second = model.downloads.enqueue(
            .update(
                folder: folder.url.appending(path: "Tyrian"),
                options: DownloadOptions(platform: .windows, language: "fr-FR")
            ),
            productID: PreviewData.tyrianID,
            title: "Tyrian"
        )
        #expect(second.isQueued)
        #expect(
            model.downloads.enqueue(.repair(folder: game), productID: PreviewData.witcherID, title: "W")
                === first
        )
        model.downloads.pause(second)
        await model.downloads.cancel(first)

        let relaunched = AppModel.testing(signedIn: true, folder: folder.url)
        relaunched.downloads.restore()
        #expect(relaunched.downloads.restoredCount == 1)
        let restored = try #require(relaunched.downloads.jobs.first)
        guard case .paused = restored.state, case .update(_, let options) = restored.kind else {
            Issue.record("expected a paused update")
            return
        }
        #expect(options?.language == "fr-FR")
        #expect(options?.platform == .windows)
    }
}
