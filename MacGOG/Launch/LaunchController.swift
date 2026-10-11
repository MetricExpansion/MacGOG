import Foundation
import Observation
import SwiftyGOG

/// Starts and stops games, and tracks which ones are running.
@MainActor @Observable final class LaunchController {
    private(set) var running: Set<String> = []

    /// Runs before a game starts, such as a cloud save download. Throwing cancels the launch.
    @ObservationIgnored var beforeLaunch: (@MainActor (InstalledGameRecord) async throws -> Void)?
    /// Runs after a game exits, such as a cloud save upload.
    @ObservationIgnored var afterExit: (@MainActor (InstalledGameRecord) async -> Void)?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init(settings: AppSettings) {
        self.settings = settings
    }

    func isRunning(_ productID: String) -> Bool { running.contains(productID) }

    /// Why a game can't be launched now, or `nil` when it can.
    func blocker(for record: InstalledGameRecord) -> AppError? {
        switch record.status {
        case .missing: return .folderMissing(record.entry.path)
        case .needsRepair: return .notInstalled
        case .ready, .foreign: break
        }
        if record.platform == .windows, !settings.isWineConfigured {
            return .wineNotConfigured
        }
        return nil
    }

    /// Launches a game's play task (the primary one when `task` is `nil`) and returns once it has
    /// started. The game is marked running until it exits.
    func launch(_ record: InstalledGameRecord, task: Int? = nil) async throws {
        guard !isRunning(record.id) else { return }
        if let blocker = blocker(for: record) {
            throw blocker
        }
        let platform = record.platform ?? .osx
        var prefix: URL?
        if platform == .windows {
            let folder = settings.winePrefix(for: record.id)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            prefix = folder
        }
        let options = LaunchOptions(
            platform: platform,
            task: task,
            wine: settings.winePath,
            winePrefix: prefix?.path,
            wrapper: try ShellWords.parse(settings.launchWrapper)
        )
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

    /// Terminates a running game.
    func stop(_ productID: String) {
        tasks[productID]?.cancel()
    }
}
