import Foundation
import SwiftyGOG

nonisolated extension Int64 {
    var formattedBytes: String { formatted(.byteCount(style: .file)) }
}

nonisolated extension Double {
    /// A transfer rate in bytes per second, such as "12.5 MB/s".
    var formattedRate: String { "\(Int64(self).formattedBytes)/s" }
}

nonisolated extension TimeInterval {
    /// A short remaining-time label, such as "3 min" or "1 hr, 5 min".
    var formattedRemaining: String {
        Duration.seconds(self).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)
        )
    }
}

nonisolated extension GamePlatform {
    var displayName: String {
        switch self {
        case .windows: "Windows"
        case .osx: "macOS"
        case .linux: "Linux"
        }
    }

    var symbolName: String {
        switch self {
        case .windows: "pc"
        case .osx: "apple.logo"
        case .linux: "terminal"
        }
    }
}

nonisolated extension Language {
    /// The name in English, with the native name when it differs.
    var displayName: String { name == nativeName ? name : "\(name) (\(nativeName))" }
}
