import Foundation
import Observation
import SwiftyGOG

/// Starts and stops games, and tracks which ones are running. Windows games run in a CrossOver
/// bottle, or through the Wine binary chosen in Settings.
@MainActor @Observable final class LaunchController {
    private(set) var running: Set<String> = []
    /// Games getting ready to start, such as while their CrossOver bottle is created.
    private(set) var preparing: Set<String> = []

    /// Runs before a game starts, such as a cloud save download. Throwing cancels the launch.
    @ObservationIgnored var beforeLaunch: (@MainActor (InstalledGameRecord) async throws -> Void)?
    /// Runs after a game exits, such as a cloud save upload.
    @ObservationIgnored var afterExit: (@MainActor (InstalledGameRecord) async -> Void)?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let crossOver: CrossOverModel
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init(settings: AppSettings, crossOver: CrossOverModel) {
        self.settings = settings
        self.crossOver = crossOver
    }

    func isRunning(_ productID: String) -> Bool { running.contains(productID) }

    func isPreparing(_ productID: String) -> Bool { preparing.contains(productID) }

    /// What runs Windows games: the user's choice, or CrossOver when it's installed.
    var windowsRunner: WindowsRunner {
        settings.windowsRunner ?? (crossOver.isInstalled ? .crossOver : .wine)
    }

    /// Where a Windows game's `C:` drive lives and who its Windows user is, for finding its saves.
    /// `nil` when it has no CrossOver bottle yet.
    func windowsEnvironment(for productID: String) -> (prefix: URL, user: String)? {
        switch windowsRunner {
        case .crossOver:
            crossOver.bottle(for: productID).map { ($0.url, CrossOver.windowsUser) }
        case .wine:
            (settings.winePrefix(for: productID), NSUserName())
        }
    }

    /// Why a game can't be launched now, or `nil` when it can.
    func blocker(for record: InstalledGameRecord) -> AppError? {
        switch record.status {
        case .missing: return .folderMissing(record.entry.path)
        case .needsRepair: return .notInstalled
        case .ready, .foreign: break
        }
        guard record.platform == .windows else { return nil }
        switch windowsRunner {
        case .crossOver:
            return crossOver.isInstalled ? nil : .crossOverNotInstalled
        case .wine:
            return settings.isWineConfigured ? nil : .wineNotConfigured
        }
    }

    /// Launches a game's play task (the primary one when `task` is `nil`) and returns once it has
    /// started. A Windows game without a CrossOver bottle gets one first. The game is marked running
    /// until it and every program it started have exited.
    func launch(_ record: InstalledGameRecord, task: Int? = nil) async throws {
        guard !isRunning(record.id), !isPreparing(record.id) else { return }
        if let blocker = blocker(for: record) {
            throw blocker
        }
        preparing.insert(record.id)
        defer { preparing.remove(record.id) }
        let options = try await launchOptions(for: record, task: task)
        let command = try GameLauncher.command(root: record.entry.folder, id: record.id, options: options)
        running.insert(record.id)
        do {
            try await beforeLaunch?(record)
        } catch {
            running.remove(record.id)
            throw error
        }
        tasks[record.id] = Task {
            _ = try? await GameLauncher.run(command)
            tasks[record.id] = nil
            await afterExit?(record)
            running.remove(record.id)
        }
    }

    /// Terminates a running game. A CrossOver game's whole bottle is stopped, since the game may
    /// have been started by a launcher that already exited.
    func stop(_ productID: String) {
        tasks[productID]?.cancel()
        if windowsRunner == .crossOver, crossOver.assignment(for: productID) != nil {
            Task { await crossOver.stop(productID) }
        }
    }

    private func launchOptions(for record: InstalledGameRecord, task: Int?) async throws -> LaunchOptions {
        let platform = record.platform ?? .osx
        let wrapper = try ShellWords.parse(settings.launchWrapper)
        guard platform == .windows else {
            return LaunchOptions(platform: platform, task: task, wrapper: wrapper)
        }
        switch windowsRunner {
        case .crossOver:
            guard let app = crossOver.crossOver else { throw AppError.crossOverNotInstalled }
            let bottle = try await crossOver.ensureBottle(
                for: record.id,
                title: record.title,
                settings: settings.newBottleSettings
            )
            return LaunchOptions(
                platform: platform,
                task: task,
                wrapper: wrapper,
                crossOver: CrossOverLaunch(crossOver: app, bottle: bottle.name)
            )
        case .wine:
            let prefix = settings.winePrefix(for: record.id)
            try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
            return LaunchOptions(
                platform: platform,
                task: task,
                wine: settings.winePath,
                winePrefix: prefix.path,
                wrapper: wrapper
            )
        }
    }
}
