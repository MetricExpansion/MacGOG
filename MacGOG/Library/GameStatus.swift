import Foundation
import SwiftyGOG

/// A game in the library grid: an owned game, or an installed one the library doesn't list.
nonisolated struct LibraryItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let platforms: [GamePlatform]
    let imageURL: URL?
}

/// What the library shows about a game's installation.
enum GameStatus {
    case notInstalled
    case installing(DownloadJob)
    case running
    case updateAvailable(AvailableUpdate)
    case installed
    case missing
    case needsRepair
    /// Installed by Galaxy or another tool, and not yet verified by this app.
    case foreign

    var label: String? {
        switch self {
        case .notInstalled: nil
        case .installing(let job):
            switch job.state {
            case .running: job.progress.fraction.map { "\(Int($0 * 100))%" } ?? "Preparing"
            case .queued: "Queued"
            case .paused: "Paused"
            case .failed: "Failed"
            case .finished: "Installed"
            }
        case .running: "Playing"
        case .updateAvailable: "Update"
        case .installed: "Installed"
        case .missing: "Missing"
        case .needsRepair: "Needs repair"
        case .foreign: "Not verified"
        }
    }

    var isAttention: Bool {
        switch self {
        case .missing, .needsRepair: true
        case .installing(let job):
            if case .failed = job.state { true } else { false }
        default: false
        }
    }
}

extension AppModel {
    func status(of id: String) -> GameStatus {
        if let job = downloads.job(for: id) {
            return .installing(job)
        }
        if launcher.isRunning(id) {
            return .running
        }
        guard let record = registry.record(for: id) else { return .notInstalled }
        switch record.status {
        case .missing: return .missing
        case .needsRepair: return .needsRepair
        case .foreign: return .foreign
        case .ready:
            if let update = registry.updates[id] {
                return .updateAvailable(update)
            }
            return .installed
        }
    }

    /// Owned games, plus installed games the library doesn't list.
    var libraryItems: [LibraryItem] {
        var items = library.games.map {
            LibraryItem(id: $0.id, title: $0.title, platforms: $0.platforms, imageURL: $0.imageURL)
        }
        let listed = Set(items.map(\.id))
        for record in registry.records.values where !listed.contains(record.id) {
            items.append(
                LibraryItem(
                    id: record.id,
                    title: record.title,
                    platforms: record.platform.map { [$0] } ?? [],
                    imageURL: nil
                )
            )
        }
        return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
