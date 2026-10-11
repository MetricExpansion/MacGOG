import Foundation
import SwiftyGOG
import Synchronization

/// Totals accumulated from `DownloadEvent`s.
nonisolated struct ProgressCounters: Sendable, Equatable {
    enum Phase: Sendable, Equatable {
        case preparing
        case preparingPatches
        case transferring
        case finalizing
    }

    var phase = Phase.preparing
    var files = 0
    var filesDone = 0
    /// The denominator for progress.
    var diskSize: Int64 = 0
    /// An upper bound on network bytes.
    var downloadSize: Int64 = 0
    /// Bytes of files verified or installed.
    var completed: Int64 = 0
    /// Network bytes received.
    var downloaded: Int64 = 0
    var lastFile: String?

    mutating func apply(_ event: DownloadEvent) {
        switch event {
        case .started(let files, let diskSize, let downloadSize):
            self.files = files
            self.diskSize = diskSize
            self.downloadSize = downloadSize
            if phase == .preparing {
                phase = .transferring
            }
        case .preparingPatches:
            phase = .preparingPatches
        case .patchesUnavailable, .patchFailed:
            break
        case .downloaded(let bytes):
            downloaded += bytes
            phase = .transferring
        case .fileVerified(let path, let size), .fileInstalled(let path, let size, _):
            completed += size
            filesDone += 1
            lastFile = path
            phase = .transferring
        case .finalizing:
            phase = .finalizing
        }
    }
}

/// Collects progress events from SwiftyGOG's worker tasks. Events arrive concurrently and in huge
/// numbers, so they only update counters under a lock; the UI samples them on a timer.
nonisolated final class ProgressSink: Sendable {
    private let counters = Mutex(ProgressCounters())

    func record(_ event: DownloadEvent) {
        counters.withLock { $0.apply(event) }
    }

    var snapshot: ProgressCounters {
        counters.withLock { $0 }
    }
}

/// What the Downloads view shows for a job, derived from sampled counters.
struct JobProgress: Equatable {
    private struct Sample: Equatable {
        let time: TimeInterval
        let downloaded: Int64
        let completed: Int64
    }

    /// Rates are averaged over this many seconds.
    static let window: TimeInterval = 5

    private(set) var counters = ProgressCounters()
    /// Network bytes per second.
    private(set) var bytesPerSecond: Double = 0
    /// Estimated seconds until done, when there's enough data to guess.
    private(set) var remaining: TimeInterval?
    private var samples: [Sample] = []

    /// 0…1 once totals are known.
    var fraction: Double? {
        guard counters.diskSize > 0 else { return nil }
        return min(Double(counters.completed) / Double(counters.diskSize), 1)
    }

    var phaseText: String {
        switch counters.phase {
        case .preparing: "Preparing…"
        case .preparingPatches: "Looking for patches…"
        case .transferring where counters.files > 0:
            "\(counters.filesDone) of \(counters.files) files"
        case .transferring: "Downloading…"
        case .finalizing: "Finishing…"
        }
    }

    mutating func update(with counters: ProgressCounters, at time: TimeInterval) {
        self.counters = counters
        samples.append(Sample(time: time, downloaded: counters.downloaded, completed: counters.completed))
        samples.removeAll { time - $0.time > Self.window }
        guard let first = samples.first, let last = samples.last, last.time - first.time >= 1 else {
            return
        }
        let elapsed = last.time - first.time
        bytesPerSecond = Double(last.downloaded - first.downloaded) / elapsed
        let completedRate = Double(last.completed - first.completed) / elapsed
        remaining =
            if completedRate > 0, counters.diskSize > counters.completed {
                Double(counters.diskSize - counters.completed) / completedRate
            } else {
                nil
            }
    }

    /// Clears rates when a job stops, keeping the totals.
    mutating func stop() {
        samples = []
        bytesPerSecond = 0
        remaining = nil
    }
}
