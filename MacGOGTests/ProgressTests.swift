import SwiftyGOG
import Testing

@testable import MacGOG

@Suite struct ProgressTests {
    @Test func countersFollowEvents() {
        var counters = ProgressCounters()
        counters.apply(.started(files: 3, diskSize: 300, downloadSize: 200))
        counters.apply(.downloaded(bytes: 50))
        counters.apply(.fileVerified(path: "a", size: 100))
        counters.apply(.fileInstalled(path: "b", size: 100, patched: false))
        #expect(counters.completed == 200)
        #expect(counters.downloaded == 50)
        #expect(counters.filesDone == 2)
        #expect(counters.lastFile == "b")
        #expect(counters.phase == .transferring)
        counters.apply(.finalizing)
        #expect(counters.phase == .finalizing)
    }

    @Test func sinkCollectsConcurrentEvents() async {
        let sink = ProgressSink()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask { sink.record(.downloaded(bytes: 10)) }
            }
        }
        #expect(sink.snapshot.downloaded == 1000)
    }

    @Test func rateAndRemainingTimeUseTheWindow() {
        var counters = ProgressCounters()
        counters.apply(.started(files: 1, diskSize: 1000, downloadSize: 1000))
        var progress = JobProgress()
        progress.update(with: counters, at: 0)
        #expect(progress.fraction == 0)
        #expect(progress.remaining == nil)
        counters.downloaded = 200
        counters.completed = 100
        progress.update(with: counters, at: 2)
        #expect(progress.bytesPerSecond == 100)
        // 900 bytes left at 50 bytes per second.
        #expect(progress.remaining == 18)
        #expect(progress.fraction == 0.1)
        // Samples older than the window are dropped.
        counters.downloaded = 1200
        counters.completed = 600
        progress.update(with: counters, at: 10)
        progress.update(with: counters, at: 11)
        #expect(progress.bytesPerSecond == 0)
        progress.stop()
        #expect(progress.remaining == nil)
        #expect(progress.counters.completed == 600)
    }

    @Test func unknownTotalsHaveNoFraction() {
        #expect(JobProgress().fraction == nil)
        #expect(JobProgress().phaseText == "Preparing…")
    }
}
