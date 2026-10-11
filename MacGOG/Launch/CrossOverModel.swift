import AppKit
import Foundation
import Observation
import SwiftyGOG

/// CrossOver on this Mac, its bottles, and which bottle each Windows game runs in.
///
/// MacGOG only changes settings of bottles it created. Bottles the user made in CrossOver can be
/// chosen for a game but are left as they are.
@MainActor @Observable final class CrossOverModel {
    /// Which bottle a game uses, and whether MacGOG made it.
    nonisolated struct Assignment: Codable, Hashable, Sendable {
        var bottle: String
        var createdByMacGOG: Bool
    }

    /// `nil` when CrossOver isn't installed.
    private(set) var crossOver: CrossOver?
    private(set) var bottles: [CrossOverBottle] = []
    private(set) var assignments: [String: Assignment] = [:]
    /// Games whose bottle is being created.
    private(set) var creating: Set<String> = []

    @ObservationIgnored private let file: StateFile<[String: Assignment]>
    @ObservationIgnored private let locate: @MainActor () -> CrossOver?

    init(file: URL, locate: @escaping @MainActor () -> CrossOver? = CrossOverModel.locateInstalled) {
        self.file = StateFile(url: file)
        self.locate = locate
        assignments = (try? self.file.load()) ?? [:]
    }

    /// Finds CrossOver through Launch Services, wherever the user keeps it.
    static func locateInstalled() -> CrossOver? {
        guard
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.codeweavers.CrossOver")
        else {
            return CrossOver.find()
        }
        let crossOver = CrossOver(app: app)
        return FileManager.default.isExecutableFile(atPath: crossOver.wine.path) ? crossOver : nil
    }

    var isInstalled: Bool { crossOver != nil }

    /// Looks for CrossOver and reads its bottles again.
    func refresh() {
        crossOver = locate()
        bottles = (try? crossOver?.bottles()) ?? []
    }

    func assignment(for productID: String) -> Assignment? { assignments[productID] }

    /// The game's bottle, if it has one that still exists.
    func bottle(for productID: String) -> CrossOverBottle? {
        guard let name = assignments[productID]?.bottle else { return nil }
        return bottles.first { $0.name == name }
    }

    /// Whether MacGOG may change the game's bottle settings.
    func canEditSettings(for productID: String) -> Bool {
        assignments[productID]?.createdByMacGOG == true && bottle(for: productID) != nil
    }

    /// Runs the game in an existing bottle.
    func assign(_ bottle: String, to productID: String) {
        assignments[productID] = Assignment(bottle: bottle, createdByMacGOG: false)
        persist()
    }

    /// The game's bottle, creating one named after it when it has none.
    func ensureBottle(for productID: String, title: String, settings: CrossOverSettings) async throws
        -> CrossOverBottle
    {
        if let bottle = bottle(for: productID) {
            return bottle
        }
        return try await createBottle(for: productID, title: title, settings: settings)
    }

    /// Creates a bottle for the game with `settings` and runs the game in it from now on.
    @discardableResult
    func createBottle(for productID: String, title: String, settings: CrossOverSettings) async throws
        -> CrossOverBottle
    {
        guard let crossOver else { throw AppError.crossOverNotInstalled }
        creating.insert(productID)
        defer { creating.remove(productID) }
        refresh()
        let name = Self.bottleName(for: title, taken: Set(bottles.map(\.name)))
        let bottle = try await crossOver.createBottle(
            named: name,
            settings: settings,
            description: "Created by MacGOG for \(title)"
        )
        assignments[productID] = Assignment(bottle: bottle.name, createdByMacGOG: true)
        persist()
        refresh()
        return bottle
    }

    /// Changes the settings of a bottle MacGOG created. They apply the next time the game starts.
    func updateSettings(_ settings: CrossOverSettings, for productID: String) throws {
        guard let crossOver, canEditSettings(for: productID), let bottle = bottle(for: productID) else {
            return
        }
        try crossOver.updateSettings(settings, of: bottle)
        refresh()
    }

    /// Ends everything running in the game's bottle.
    func stop(_ productID: String) async {
        guard let crossOver, let name = assignments[productID]?.bottle else { return }
        try? await crossOver.stop(bottle: name)
    }

    func openCrossOver() {
        guard let app = crossOver?.app else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// A folder-safe bottle name from a game title, made unique.
    static func bottleName(for title: String, taken: Set<String>) -> String {
        // Bottle names become folder names, so drop path separators and control characters.
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.newlines).union(.controlCharacters)
        let cleaned = title.components(separatedBy: forbidden)
            .joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let base = cleaned.isEmpty ? "GOG Game" : String(cleaned.prefix(80))
        var name = base
        var number = 2
        while taken.contains(name) {
            name = "\(base) \(number)"
            number += 1
        }
        return name
    }

    #if DEBUG
        /// Seeds state for previews and tests.
        func preload(crossOver: CrossOver?, assignments: [String: Assignment]) {
            self.crossOver = crossOver
            bottles = (try? crossOver?.bottles()) ?? []
            self.assignments = assignments
        }
    #endif

    private func persist() {
        try? file.save(assignments)
    }
}
