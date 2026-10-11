import Foundation
import Observation
import SwiftyGOG

/// User preferences, stored in `UserDefaults`.
@MainActor @Observable final class AppSettings {
    private enum Key {
        static let libraryFolder = "libraryFolder"
        static let platform = "defaultPlatform"
        static let language = "defaultLanguage"
        static let workers = "workers"
        static let concurrentJobs = "concurrentJobs"
        static let wine = "winePath"
        static let winePrefixes = "winePrefixesFolder"
        static let wrapper = "launchWrapper"
        static let syncSaves = "syncSavesAroundLaunch"
        static let checkUpdates = "checkUpdatesAtLaunch"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Where new games are installed; each game gets its own folder inside it.
    var libraryFolder: URL {
        didSet { defaults.set(libraryFolder.path, forKey: Key.libraryFolder) }
    }

    var defaultPlatform: GamePlatform {
        didSet { defaults.set(defaultPlatform.rawValue, forKey: Key.platform) }
    }

    /// A GOG language code, such as `en-US`.
    var defaultLanguage: String {
        didSet { defaults.set(defaultLanguage, forKey: Key.language) }
    }

    /// Parallel downloads within one job, 1…128.
    var workers: Int {
        didSet { defaults.set(workers, forKey: Key.workers) }
    }

    /// Jobs that may run at once.
    var concurrentJobs: Int {
        didSet { defaults.set(concurrentJobs, forKey: Key.concurrentJobs) }
    }

    /// The Wine (or compatible) binary for Windows games; empty when not configured.
    var winePath: String {
        didSet { defaults.set(winePath, forKey: Key.wine) }
    }

    /// Each Windows game gets its own Wine prefix inside this folder.
    var winePrefixesFolder: URL {
        didSet { defaults.set(winePrefixesFolder.path, forKey: Key.winePrefixes) }
    }

    /// An optional command that wraps every launch, in shell-word syntax.
    var launchWrapper: String {
        didSet { defaults.set(launchWrapper, forKey: Key.wrapper) }
    }

    var syncSavesAroundLaunch: Bool {
        didSet { defaults.set(syncSavesAroundLaunch, forKey: Key.syncSaves) }
    }

    var checkUpdatesAtLaunch: Bool {
        didSet { defaults.set(checkUpdatesAtLaunch, forKey: Key.checkUpdates) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        libraryFolder =
            defaults.string(forKey: Key.libraryFolder).map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? URL.homeDirectory.appending(path: "Games/GOG", directoryHint: .isDirectory)
        defaultPlatform = defaults.string(forKey: Key.platform).flatMap(GamePlatform.init(rawValue:)) ?? .osx
        defaultLanguage = defaults.string(forKey: Key.language) ?? "en-US"
        workers = (defaults.object(forKey: Key.workers) as? Int).map { min(max($0, 1), 128) } ?? 4
        concurrentJobs = (defaults.object(forKey: Key.concurrentJobs) as? Int).map { max($0, 1) } ?? 1
        winePath = defaults.string(forKey: Key.wine) ?? ""
        winePrefixesFolder =
            defaults.string(forKey: Key.winePrefixes).map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? URL.macGOGSupport.appending(path: "Prefixes", directoryHint: .isDirectory)
        launchWrapper = defaults.string(forKey: Key.wrapper) ?? ""
        syncSavesAroundLaunch = defaults.object(forKey: Key.syncSaves) as? Bool ?? true
        checkUpdatesAtLaunch = defaults.object(forKey: Key.checkUpdates) as? Bool ?? true
    }

    /// Whether `winePath` names an executable file.
    var isWineConfigured: Bool {
        !winePath.isEmpty && FileManager.default.isExecutableFile(atPath: winePath)
    }

    func winePrefix(for productID: String) -> URL {
        winePrefixesFolder.appending(path: productID, directoryHint: .isDirectory)
    }
}
