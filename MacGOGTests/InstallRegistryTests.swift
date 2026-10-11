import Foundation
import SwiftyGOG
import Testing

@testable import MacGOG

@MainActor
@Suite struct InstallRegistryTests {
    @Test func persistsAndRecognizesInstallations() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let file = folder.url.appending(path: "installations.json")
        let root = try PreviewData.writeInstallation(in: folder.url)
        let registry = InstallRegistry(file: file)
        await registry.register(productID: PreviewData.witcherID, folder: root, title: "Witcher")

        let reloaded = InstallRegistry(file: file)
        await reloaded.load()
        let record = try #require(reloaded.record(for: PreviewData.witcherID))
        #expect(record.installation?.plan.version == "1.5")
        #expect(record.platform == .osx)
        #expect(record.info?.playTasks.filter { $0.kind == .file }.count == 2)
    }

    @Test func missingAndDamagedFolders() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let file = folder.url.appending(path: "installations.json")
        let root = try PreviewData.writeInstallation(in: folder.url)
        let registry = InstallRegistry(file: file)
        await registry.register(productID: PreviewData.witcherID, folder: root, title: "Witcher")

        try Data("{".utf8).write(to: root.appending(path: ".gogdl/manifest.json"))
        await registry.refresh(PreviewData.witcherID)
        guard case .needsRepair = registry.record(for: PreviewData.witcherID)?.status else {
            Issue.record("expected needsRepair")
            return
        }

        try FileManager.default.removeItem(at: root)
        await registry.refresh(PreviewData.witcherID)
        guard case .missing = registry.record(for: PreviewData.witcherID)?.status else {
            Issue.record("expected missing")
            return
        }

        registry.remove(PreviewData.witcherID)
        let reloaded = InstallRegistry(file: file)
        await reloaded.load()
        #expect(reloaded.records.isEmpty)
    }

    @Test func foreignInstallsAreRecognized() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let root = try PreviewData.writeInstallation(in: folder.url)
        try FileManager.default.removeItem(at: root.appending(path: ".gogdl"))
        guard case .foreign(let info) = try await InstallRegistry.inspectFolder(root) else {
            Issue.record("expected a foreign install")
            return
        }
        #expect(info.appName == PreviewData.witcherID)
    }
}
