import Foundation
import Observation
import SwiftyGOG

/// Starts and stops games, and tracks which ones are running. Windows games run in a CrossOver
/// bottle, or through the Wine binary chosen in Settings, and are set up there first as GOG Galaxy
/// would: runtimes installed and install script run.
@MainActor @Observable final class LaunchController {
    /// What a Windows game was last set up for.
    nonisolated struct SetupRecord: Codable, Hashable, Sendable {
        var buildID: String?
        /// The `C:` drive's folder: the bottle or Wine prefix.
        var prefix: String
    }

    private(set) var running: Set<String> = []
    /// Games getting ready to start, such as while their CrossOver bottle is created or they're set up.
    private(set) var preparing: Set<String> = []
    /// What each preparing game is doing, such as "Installing DirectX…".
    private(set) var preparingStatus: [String: String] = [:]

    /// Runs before a game starts, such as a cloud save download. Throwing cancels the launch.
    @ObservationIgnored var beforeLaunch: (@MainActor (InstalledGameRecord) async throws -> Void)?
    /// Runs after a game exits, such as a cloud save upload.
    @ObservationIgnored var afterExit: (@MainActor (InstalledGameRecord) async -> Void)?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let crossOver: CrossOverModel
    @ObservationIgnored private let postInstall: PostInstall
    @ObservationIgnored private let setupFile: StateFile<[String: SetupRecord]>
    @ObservationIgnored private var setups: [String: SetupRecord]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init(settings: AppSettings, crossOver: CrossOverModel, client: GOGClient, supportFolder: URL) {
        self.settings = settings
        self.crossOver = crossOver
        postInstall = PostInstall(
            client: client,
            runtimesFolder: supportFolder.appending(path: "Runtimes", directoryHint: .isDirectory)
        )
        setupFile = StateFile(url: supportFolder.appending(path: "setup.json"))
        setups = (try? setupFile.load()) ?? [:]
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
        defer {
            preparing.remove(record.id)
            preparingStatus[record.id] = nil
        }
        let options = try await launchOptions(for: record, task: task)
        if needsSetup(record) {
            try await setUp(record, options: options)
        }
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

    /// Whether a Windows game hasn't been set up for its installed build in its current bottle or
    /// prefix. Games installed by Galaxy were set up by Galaxy.
    func needsSetup(_ record: InstalledGameRecord) -> Bool {
        guard record.platform == .windows, let installation = record.installation else { return false }
        // Without a bottle yet, the game is set up once its bottle is made at launch.
        guard let prefix = windowsEnvironment(for: record.id)?.prefix else { return true }
        return setups[record.id] != SetupRecord(buildID: installation.plan.buildID, prefix: prefix.path)
    }

    /// Sets a Windows game up again now, such as after changing its bottle's contents by hand.
    func runSetup(_ record: InstalledGameRecord) async throws {
        guard !isRunning(record.id), !isPreparing(record.id), record.installation != nil else { return }
        if let blocker = blocker(for: record) {
            throw blocker
        }
        preparing.insert(record.id)
        defer {
            preparing.remove(record.id)
            preparingStatus[record.id] = nil
        }
        try await setUp(record, options: launchOptions(for: record, task: nil))
    }

    /// Installs the game's runtimes and runs its install script where it will run. A runtime whose
    /// installer fails is skipped, as Galaxy does, since a newer version is often already there; a
    /// failed install script stops the launch.
    private func setUp(_ record: InstalledGameRecord, options: LaunchOptions) async throws {
        guard let installation = record.installation, let prefix = windowsEnvironment(for: record.id)?.prefix
        else { return }
        preparingStatus[record.id] = "Checking what the game needs…"
        let dependencies = try await postInstall.dependencies(for: installation)
        for dependency in dependencies {
            preparingStatus[record.id] = "Downloading \(dependency.name)…"
            try await postInstall.download([dependency], workers: settings.workers)
        }
        for step in try postInstall.steps(for: installation, dependencies: dependencies) {
            preparingStatus[record.id] =
                switch step.kind {
                case .runtime: "Installing \(step.name)…"
                case .script: "Running the install script…"
                }
            let command = try GameLauncher.command(
                program: step.program,
                arguments: step.arguments,
                directory: step.directory,
                options: options
            )
            let status = try await GameLauncher.run(command)
            if step.kind == .script, status != 0 {
                throw AppError.setupFailed(status: status)
            }
        }
        setups[record.id] = SetupRecord(buildID: installation.plan.buildID, prefix: prefix.path)
        try? setupFile.save(setups)
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
        preparingStatus[record.id] = "Starting…"
        switch windowsRunner {
        case .crossOver:
            guard let app = crossOver.crossOver else { throw AppError.crossOverNotInstalled }
            if crossOver.bottle(for: record.id) == nil {
                preparingStatus[record.id] = "Creating a CrossOver bottle…"
            }
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
