import Foundation
import Observation
import SwiftyGOG

/// One install, update, or repair, and its progress.
@MainActor @Observable final class DownloadJob: Identifiable {
    enum Kind: Sendable {
        case install(InstallPlan, folder: URL)
        /// `nil` options repeat the installed choices.
        case update(folder: URL, options: DownloadOptions?)
        case repair(folder: URL)
    }

    enum State {
        case queued
        case running
        case paused
        case failed(PresentableError)
        case finished(DownloadResult)
    }

    let id: UUID
    let productID: String
    let title: String
    let kind: Kind
    var state: State
    var progress = JobProgress()

    @ObservationIgnored fileprivate var task: Task<Void, Never>?
    @ObservationIgnored fileprivate var stopping = false

    init(id: UUID = UUID(), productID: String, title: String, kind: Kind, state: State = .queued) {
        self.id = id
        self.productID = productID
        self.title = title
        self.kind = kind
        self.state = state
    }

    var folder: URL {
        switch kind {
        case .install(_, let folder), .update(let folder, _), .repair(let folder): folder
        }
    }

    var verb: String {
        switch kind {
        case .install: "Install"
        case .update: "Update"
        case .repair: "Repair"
        }
    }

    var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    var isQueued: Bool {
        if case .queued = state { true } else { false }
    }

    /// Queued, running, paused, or failed: not yet done.
    var isUnfinished: Bool {
        if case .finished = state { false } else { true }
    }

    /// Queued or running.
    var isActive: Bool { isRunning || isQueued }
}

/// Side effects of the queue that tests replace.
struct QueueHooks {
    var notify: @MainActor (_ title: String, _ body: String) -> Void
    var setBadge: @MainActor (_ label: String?) -> Void
    /// Holds off idle sleep while `active` is true.
    var preventSleep: @MainActor (_ active: Bool) -> Void

    static let none = QueueHooks(notify: { _, _ in }, setBadge: { _ in }, preventSleep: { _ in })
}

/// Runs install, update, and repair jobs: one per game folder, and up to the configured number at once.
@MainActor @Observable final class DownloadQueue {
    private(set) var jobs: [DownloadJob] = []
    /// Unfinished jobs found at launch, offered for resumption.
    private(set) var restoredCount = 0

    /// Called on the main actor after a job succeeds.
    @ObservationIgnored var onFinished: (@MainActor (DownloadJob) async -> Void)?
    /// Called when a job fails with an error that ended the session.
    @ObservationIgnored var onSessionEnded: (@MainActor () async -> Void)?

    @ObservationIgnored private let client: GOGClient
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let file: StateFile<[SavedJob]>
    @ObservationIgnored private let hooks: QueueHooks

    init(client: GOGClient, settings: AppSettings, file: URL, hooks: QueueHooks) {
        self.client = client
        self.settings = settings
        self.file = StateFile(url: file)
        self.hooks = hooks
    }

    var hasRunningJobs: Bool { jobs.contains(where: \.isRunning) }

    var unfinishedJobs: [DownloadJob] { jobs.filter(\.isUnfinished) }

    /// The unfinished job for a game, if any.
    func job(for productID: String) -> DownloadJob? {
        jobs.last { $0.productID == productID && $0.isUnfinished }
    }

    /// Progress across running jobs, weighted by size.
    var overallFraction: Double? {
        let running = jobs.filter(\.isRunning).map(\.progress.counters)
        let total = running.reduce(0) { $0 + $1.diskSize }
        guard total > 0 else { return nil }
        return Double(running.reduce(0) { $0 + $1.completed }) / Double(total)
    }

    /// Queues a job, or returns the game's existing unfinished job.
    @discardableResult
    func enqueue(_ kind: DownloadJob.Kind, productID: String, title: String) -> DownloadJob {
        if let existing = job(for: productID) {
            if !existing.isActive {
                resume(existing)
            }
            return existing
        }
        let job = DownloadJob(productID: productID, title: title, kind: kind)
        jobs.append(job)
        persist()
        pump()
        return job
    }

    /// Stops a job; running it again resumes from verified data.
    func pause(_ job: DownloadJob) {
        switch job.state {
        case .running:
            job.stopping = true
            job.task?.cancel()
        case .queued:
            job.state = .paused
            persist()
        default:
            break
        }
    }

    func resume(_ job: DownloadJob) {
        switch job.state {
        case .paused, .failed:
            job.state = .queued
            job.progress.stop()
            persist()
            pump()
        default:
            break
        }
    }

    func resumeAll() {
        for job in jobs where !job.isActive && job.isUnfinished {
            resume(job)
        }
        restoredCount = 0
    }

    func dismissRestored() {
        restoredCount = 0
    }

    /// Stops a job and removes it. Returns when it has stopped, so its folder can be deleted.
    func cancel(_ job: DownloadJob) async {
        if let task = job.task {
            job.stopping = true
            task.cancel()
            await task.value
        }
        jobs.removeAll { $0 === job }
        persist()
        pump()
    }

    func clearFinished() {
        jobs.removeAll { !$0.isUnfinished }
    }

    /// Reloads jobs that were unfinished when the app last quit, paused.
    func restore() {
        let saved = (try? file.load()) ?? []
        jobs = saved.map {
            DownloadJob(
                id: $0.id,
                productID: $0.productID,
                title: $0.title,
                kind: $0.kind.kind,
                state: .paused
            )
        }
        restoredCount = jobs.count
    }

    #if DEBUG
        /// Seeds jobs for previews and tests without running them.
        func preload(_ jobs: [DownloadJob]) {
            self.jobs = jobs
        }
    #endif

    /// Starts queued jobs while there's capacity and their folders are free.
    private func pump() {
        var running = jobs.filter(\.isRunning)
        for job in jobs where job.isQueued {
            guard running.count < settings.concurrentJobs else { break }
            guard !running.contains(where: { $0.folder == job.folder }) else { continue }
            start(job)
            running.append(job)
        }
        hooks.preventSleep(hasRunningJobs)
        updateBadge()
    }

    private func start(_ job: DownloadJob) {
        job.state = .running
        job.stopping = false
        let sink = ProgressSink()
        let kind = job.kind
        let client = client
        let workers = settings.workers
        job.task = Task {
            let sampler = Task {
                while !Task.isCancelled {
                    job.progress.update(with: sink.snapshot, at: ProcessInfo.processInfo.systemUptime)
                    updateBadge()
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { sampler.cancel() }
            do {
                let result = try await Self.run(kind, client: client, workers: workers, sink: sink)
                job.progress.update(with: sink.snapshot, at: ProcessInfo.processInfo.systemUptime)
                job.state = .finished(result)
                hooks.notify("\(job.title) is ready", "\(job.verb) finished.")
                await onFinished?(job)
            } catch {
                job.progress.update(with: sink.snapshot, at: ProcessInfo.processInfo.systemUptime)
                if job.stopping || Task.isCancelled {
                    job.state = .paused
                } else if let presentable = presentableError(error) {
                    job.state = .failed(presentable)
                    hooks.notify("\(job.title) couldn't \(job.verb.lowercased())", presentable.message)
                    if requiresSignIn(error) {
                        await onSessionEnded?()
                    }
                } else {
                    job.state = .paused
                }
            }
            job.progress.stop()
            job.task = nil
            job.stopping = false
            persist()
            pump()
        }
    }

    @concurrent
    private nonisolated static func run(
        _ kind: DownloadJob.Kind,
        client: GOGClient,
        workers: Int,
        sink: ProgressSink
    ) async throws -> DownloadResult {
        let progress: @Sendable (DownloadEvent) -> Void = { sink.record($0) }
        switch kind {
        case .install(let plan, let folder):
            return try await Downloader(client: client).install(
                plan,
                at: folder,
                workers: workers,
                progress: progress
            )
        case .update(let folder, let options):
            let installation = try Installation(at: folder)
            var options = options ?? installation.options
            options.workers = workers
            return try await installation.update(client: client, options: options, progress: progress)
        case .repair(let folder):
            return try await Installation(at: folder).repair(
                client: client,
                workers: workers,
                progress: progress
            )
        }
    }

    private func updateBadge() {
        let running = jobs.filter(\.isRunning).count
        guard running > 0 else {
            hooks.setBadge(nil)
            return
        }
        hooks.setBadge(overallFraction.map { "\(Int($0 * 100))%" } ?? "\(running)")
    }

    private func persist() {
        try? file.save(jobs.filter(\.isUnfinished).map(SavedJob.init))
    }
}

/// A job as saved between launches. Branch passwords are never saved.
nonisolated struct SavedJob: Codable, Sendable {
    enum Kind: Codable, Sendable {
        case install(plan: InstallPlan, folder: String)
        case update(folder: String, options: SavedOptions?)
        case repair(folder: String)

        @MainActor
        init(_ kind: DownloadJob.Kind) {
            switch kind {
            case .install(let plan, let folder): self = .install(plan: plan, folder: folder.path)
            case .update(let folder, let options):
                self = .update(folder: folder.path, options: options.map(SavedOptions.init))
            case .repair(let folder): self = .repair(folder: folder.path)
            }
        }

        var kind: DownloadJob.Kind {
            switch self {
            case .install(let plan, let folder):
                .install(plan, folder: URL(filePath: folder, directoryHint: .isDirectory))
            case .update(let folder, let options):
                .update(folder: URL(filePath: folder, directoryHint: .isDirectory), options: options?.options)
            case .repair(let folder): .repair(folder: URL(filePath: folder, directoryHint: .isDirectory))
            }
        }
    }

    let id: UUID
    let productID: String
    let title: String
    let kind: Kind

    @MainActor
    init(_ job: DownloadJob) {
        id = job.id
        productID = job.productID
        title = job.title
        kind = Kind(job.kind)
    }
}

/// The parts of `DownloadOptions` an update repeats.
nonisolated struct SavedOptions: Codable, Sendable {
    let platform: GamePlatform
    let language: String
    let branch: String?
    let generation: Int
    let includeDLCs: Bool
    let dlcIDs: [String]
    let dlcOnly: Bool

    init(_ options: DownloadOptions) {
        platform = options.platform
        language = options.language
        branch = options.branch
        generation = options.generation
        includeDLCs = options.includeDLCs
        dlcIDs = options.dlcIDs.sorted()
        dlcOnly = options.dlcOnly
    }

    var options: DownloadOptions {
        DownloadOptions(
            platform: platform,
            language: language,
            branch: branch,
            generation: generation,
            includeDLCs: includeDLCs,
            dlcIDs: Set(dlcIDs),
            dlcOnly: dlcOnly
        )
    }
}
