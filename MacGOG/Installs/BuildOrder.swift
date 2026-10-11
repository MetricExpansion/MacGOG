import Foundation
import SwiftyGOG

extension BuildList {
    /// Whether `build` is older than the build with ID `reference`, by publication date when both
    /// have one, otherwise by GOG's newest-first order. `nil` when either isn't in the list.
    func isBuild(_ build: String, olderThan reference: String) -> Bool? {
        guard let target = builds.firstIndex(where: { $0.id == build }),
            let other = builds.firstIndex(where: { $0.id == reference })
        else { return nil }
        if let targetDate = builds[target].publishedDate, let otherDate = builds[other].publishedDate {
            return targetDate < otherDate
        }
        return target > other
    }
}
