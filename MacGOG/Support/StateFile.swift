import Foundation

/// A JSON file of app state, written atomically so a crash never leaves it half-written.
nonisolated struct StateFile<Value: Codable & Sendable>: Sendable {
    let url: URL

    /// The stored value, or `nil` when the file doesn't exist yet.
    func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    func save(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

nonisolated extension URL {
    /// `~/Library/Application Support/MacGOG`.
    static var macGOGSupport: URL {
        URL.applicationSupportDirectory.appending(path: "MacGOG", directoryHint: .isDirectory)
    }

    /// `~/Library/Caches/MacGOG`.
    static var macGOGCaches: URL {
        URL.cachesDirectory.appending(path: "MacGOG", directoryHint: .isDirectory)
    }

    /// Free space for important data on this URL's volume, walking up to an existing ancestor.
    var availableCapacity: Int64? {
        var url = self
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
        }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
