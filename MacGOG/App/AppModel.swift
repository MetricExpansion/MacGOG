import AppKit
import Foundation
import Observation
import SwiftyGOG
import UserNotifications

/// Owns the app's single `GOGClient` and every feature model.
@MainActor @Observable final class AppModel {
    let client: GOGClient
    let settings: AppSettings
    let session: SessionModel
    let library: LibraryModel
    let registry: InstallRegistry
    let downloads: DownloadQueue
    let launcher: LaunchController
    let cloudSaves: CloudSaveModel
    let artwork: ArtworkLoader

    /// An error to show in an alert, with what Retry should do.
    var presentedError: PresentedError?

    struct PresentedError: Identifiable {
        let error: PresentableError
        let retry: (@MainActor () -> Void)?

        var id: UUID { error.id }
    }

    init(
        http: HTTPClient,
        store: any CredentialStore,
        defaults: UserDefaults,
        supportFolder: URL,
        artwork: ArtworkLoader,
        hooks: QueueHooks,
        sessionState: SessionModel.State = .unknown
    ) {
        let auth = Authorization(store: store, http: http)
        let client = GOGClient(auth: auth, http: http)
        let settings = AppSettings(defaults: defaults)
        self.client = client
        self.settings = settings
        self.artwork = artwork
        session = SessionModel(auth: auth, state: sessionState)
        library = LibraryModel(client: client, cache: supportFolder.appending(path: "library.json"))
        registry = InstallRegistry(file: supportFolder.appending(path: "installations.json"))
        downloads = DownloadQueue(
            client: client,
            settings: settings,
            file: supportFolder.appending(path: "jobs.json"),
            hooks: hooks
        )
        launcher = LaunchController(settings: settings)
        cloudSaves = CloudSaveModel(
            client: client,
            settings: settings,
            file: supportFolder.appending(path: "cloudsaves.json")
        )
        launcher.beforeLaunch = { [weak self] record in await self?.syncSavesAroundLaunch(record) }
        launcher.afterExit = { [weak self] record in await self?.syncSavesAroundLaunch(record) }
        session.onChange = { [weak self] signedIn in self?.sessionChanged(signedIn: signedIn) }
        downloads.onFinished = { [weak self] job in await self?.jobFinished(job) }
        downloads.onSessionEnded = { [weak self] in await self?.session.signOut() }
    }

    /// The app as it runs for the user: real network, Keychain, and system integration.
    static func live() -> AppModel {
        AppModel(
            http: HTTPClient(),
            store: credentialStore(),
            defaults: .standard,
            supportFolder: .macGOGSupport,
            artwork: ArtworkLoader(cache: URL.macGOGCaches.appending(path: "Artwork")),
            hooks: .live
        )
    }

    /// The Keychain, or in Debug builds, the `gogdl` CLI's sign-in when asked for.
    private static func credentialStore() -> any CredentialStore {
        #if DEBUG
            if let store = CLICredentialStore.requested() {
                return store
            }
        #endif
        return KeychainCredentialStore()
    }

    /// Restores state from disk and the Keychain. Called once at launch.
    func start() async {
        library.loadCached()
        downloads.restore()
        await registry.load()
        await session.restore()
    }

    private func sessionChanged(signedIn: Bool) {
        guard signedIn else {
            library.clear()
            return
        }
        Task {
            await refreshLibrary()
            if settings.checkUpdatesAtLaunch {
                await checkForUpdates()
            }
        }
    }

    func refreshLibrary() async {
        if let error = await library.refresh() {
            await handle(error) { [weak self] in Task { await self?.refreshLibrary() } }
        }
    }

    func checkForUpdates() async {
        if let error = await registry.checkForUpdates(client: client) {
            await handle(error, retry: nil)
        }
    }

    /// Shows an error, or returns to sign-in when the session ended. Cancellation shows nothing.
    func handle(_ error: any Error, retry: (@MainActor () -> Void)?) async {
        if await session.handle(error) {
            return
        }
        guard let presentable = presentableError(error) else { return }
        presentedError = PresentedError(error: presentable, retry: retry)
    }

    func present(_ error: any Error) {
        guard let presentable = presentableError(error) else { return }
        presentedError = PresentedError(error: presentable, retry: nil)
    }

    private func jobFinished(_ job: DownloadJob) async {
        registry.clearUpdate(for: job.productID)
        await registry.register(
            productID: job.productID,
            folder: job.folder,
            title: library.game(job.productID)?.title ?? job.title
        )
        // An install or change may have left an older build in place.
        await registry.checkForUpdate(job.productID, client: client)
    }

    /// Syncs saves before a game starts and after it exits. A failure is shown but never blocks play.
    private func syncSavesAroundLaunch(_ record: InstalledGameRecord) async {
        guard settings.syncSavesAroundLaunch, session.isSignedIn else { return }
        do {
            try await cloudSaves.sync(record)
        } catch {
            await handle(error, retry: nil)
        }
    }

    // MARK: Installed-game actions

    /// Queues a repair of an installed game.
    func repair(_ record: InstalledGameRecord) {
        downloads.enqueue(.repair(folder: record.entry.folder), productID: record.id, title: record.title)
    }

    /// Queues an update that repeats the installed choices, or uses `options` when given.
    func update(_ record: InstalledGameRecord, options: DownloadOptions? = nil) {
        downloads.enqueue(
            .update(folder: record.entry.folder, options: options),
            productID: record.id,
            title: record.title
        )
    }

    /// Moves a game's folder to the Trash and forgets it.
    func uninstall(_ record: InstalledGameRecord) async {
        guard downloads.job(for: record.id)?.isRunning != true, !launcher.isRunning(record.id) else {
            present(AppError.gameIsBusy)
            return
        }
        if let job = downloads.job(for: record.id) {
            await downloads.cancel(job)
        }
        do {
            if FileManager.default.fileExists(atPath: record.entry.path) {
                try FileManager.default.trashItem(at: record.entry.folder, resultingItemURL: nil)
            }
            registry.remove(record.id)
        } catch {
            present(error)
        }
    }

    /// Adds a game folder installed by this app, `gogdl`, or Galaxy.
    func addExistingGame(at folder: URL) async {
        do {
            switch try await InstallRegistry.inspectFolder(folder) {
            case .installation(let installation, let info):
                let id = installation.plan.product
                await registry.register(
                    productID: id,
                    folder: folder,
                    title: library.game(id)?.title ?? info?.title ?? folder.lastPathComponent
                )
            case .foreign(let info):
                guard let id = info.appName else { throw GOGError.installation(.missingMetadata) }
                await registry.register(
                    productID: id,
                    folder: folder,
                    title: library.game(id)?.title ?? info.title
                )
            }
        } catch {
            present(error)
        }
    }

    /// Points a missing game at a new folder, if it holds the same game.
    func locate(_ record: InstalledGameRecord, at folder: URL) async {
        do {
            let product =
                switch try await InstallRegistry.inspectFolder(folder) {
                case .installation(let installation, _): installation.plan.product
                case .foreign(let info): info.appName
                }
            guard product == record.id else { throw GOGError.installation(.anotherProduct) }
            await registry.register(productID: record.id, folder: folder, title: record.title)
        } catch {
            present(error)
        }
    }
}

extension QueueHooks {
    /// Notifications, the Dock badge, and sleep prevention.
    static var live: QueueHooks {
        let activity = SleepAssertion()
        return QueueHooks(
            notify: { title, body in
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                let center = UNUserNotificationCenter.current()
                Task {
                    _ = try? await center.requestAuthorization(options: [.alert, .sound])
                    try? await center.add(
                        UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    )
                }
            },
            setBadge: { label in NSApp?.dockTile.badgeLabel = label },
            preventSleep: { active in activity.set(active) }
        )
    }
}

/// Holds an activity that keeps the Mac awake while downloads run.
@MainActor final class SleepAssertion {
    private var token: (any NSObjectProtocol)?

    func set(_ active: Bool) {
        if active, token == nil {
            token = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Downloading games"
            )
        } else if !active, let token {
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        }
    }
}
