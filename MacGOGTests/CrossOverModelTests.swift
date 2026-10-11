import Foundation
import SwiftyGOG
import Testing

@testable import MacGOG

/// A fake CrossOver whose `cxbottle` makes a bottle folder with a minimal configuration.
private func fakeCrossOver(in folder: URL) throws -> CrossOver {
    let crossOver = CrossOver(
        app: folder.appending(path: "CrossOver.app", directoryHint: .isDirectory),
        bottlesFolder: folder.appending(path: "Bottles", directoryHint: .isDirectory)
    )
    try FileManager.default.createDirectory(at: crossOver.tools, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: crossOver.bottlesFolder, withIntermediateDirectories: true)
    let scripts = [
        "wine": "exit 0",
        "wineserver": "exit 0",
        "cxbottle": """
        mkdir -p '\(crossOver.bottlesFolder.path)'/"$2"
        printf '[Bottle]\\n"Template" = "win10_64"\\n[EnvironmentVariables]\\n"WINEMSYNC" = "1"\\n' \
          > '\(crossOver.bottlesFolder.path)'/"$2"/cxbottle.conf
        """,
    ]
    for (name, body) in scripts {
        let url = crossOver.tools.appending(path: name)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
    return crossOver
}

@MainActor
@Suite struct CrossOverModelTests {
    @Test func bottleNamesAreFolderSafeAndUnique() {
        #expect(
            CrossOverModel.bottleName(for: "The Witcher: Enhanced Edition", taken: [])
                == "The Witcher Enhanced Edition"
        )
        #expect(CrossOverModel.bottleName(for: "a/b\\c", taken: []) == "a b c")
        #expect(CrossOverModel.bottleName(for: "...", taken: []) == "GOG Game")
        #expect(CrossOverModel.bottleName(for: "Gwent", taken: ["Gwent", "Gwent 2"]) == "Gwent 3")
    }

    @Test func createsAndRemembersBottles() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let crossOver = try fakeCrossOver(in: folder.url)
        let state = folder.url.appending(path: "crossover.json")
        let model = CrossOverModel(file: state) { crossOver }
        model.refresh()
        #expect(model.isInstalled)
        let bottle = try await model.createBottle(for: "1", title: "Gwent", settings: CrossOverSettings())
        #expect(bottle.name == "Gwent")
        #expect(model.bottle(for: "1")?.name == "Gwent")
        #expect(model.canEditSettings(for: "1"))
        // A second game gets its own bottle.
        _ = try await model.ensureBottle(for: "2", title: "Gwent", settings: CrossOverSettings())
        #expect(model.bottle(for: "2")?.name == "Gwent 2")
        // Choosing an existing bottle never makes it MacGOG's to edit.
        model.assign("Gwent", to: "3")
        #expect(!model.canEditSettings(for: "3"))

        let relaunched = CrossOverModel(file: state) { crossOver }
        relaunched.refresh()
        #expect(relaunched.bottle(for: "1")?.name == "Gwent")
        #expect(
            relaunched.assignment(for: "3")
                == CrossOverModel.Assignment(bottle: "Gwent", createdByMacGOG: false)
        )
    }

    @Test func launcherUsesBottlesForWindowsGames() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let crossOver = try fakeCrossOver(in: folder.url)
        let settings = AppSettings(
            defaults: UserDefaults(suiteName: "MacGOGTests-\(UUID().uuidString)") ?? .standard
        )
        let model = CrossOverModel(file: folder.url.appending(path: "crossover.json")) { crossOver }
        model.refresh()
        let launcher = LaunchController(settings: settings, crossOver: model)
        // CrossOver is the default when it's installed.
        #expect(launcher.windowsRunner == .crossOver)
        #expect(launcher.windowsEnvironment(for: "1") == nil)
        try await model.createBottle(for: "1", title: "Gwent", settings: CrossOverSettings())
        let environment = try #require(launcher.windowsEnvironment(for: "1"))
        #expect(environment.prefix.lastPathComponent == "Gwent")
        #expect(environment.user == "crossover")

        settings.windowsRunner = .wine
        #expect(launcher.windowsEnvironment(for: "1")?.prefix == settings.winePrefix(for: "1"))
        #expect(launcher.windowsEnvironment(for: "1")?.user == NSUserName())
    }

    @Test func withoutCrossOverWineIsTheDefault() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let settings = AppSettings(
            defaults: UserDefaults(suiteName: "MacGOGTests-\(UUID().uuidString)") ?? .standard
        )
        let model = CrossOverModel(file: folder.url.appending(path: "crossover.json")) { nil }
        model.refresh()
        let launcher = LaunchController(settings: settings, crossOver: model)
        #expect(launcher.windowsRunner == .wine)
        settings.windowsRunner = .crossOver
        #expect(launcher.windowsEnvironment(for: "1") == nil)
    }
}
