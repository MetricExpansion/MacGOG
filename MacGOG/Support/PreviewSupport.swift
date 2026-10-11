#if DEBUG
    import Foundation
    import Synchronization
    import SwiftyGOG

    /// Credentials kept in memory, for previews and tests.
    nonisolated final class InMemoryCredentialStore: CredentialStore {
        private let credentials: Mutex<[String: OAuthToken]>

        init(_ credentials: [String: OAuthToken] = [:]) {
            self.credentials = Mutex(credentials)
        }

        /// A store holding a long-lived fake account token.
        static func signedIn() -> InMemoryCredentialStore {
            InMemoryCredentialStore([
                Authorization.clientID: OAuthToken(
                    accessToken: "preview-token",
                    refreshToken: "preview-refresh",
                    expiresIn: 60 * 60 * 24 * 365,
                    userID: "1"
                )
            ])
        }

        func load() throws -> [String: OAuthToken] { credentials.withLock { $0 } }

        func save(_ credentials: [String: OAuthToken]) throws {
            self.credentials.withLock { $0 = credentials }
        }

        func delete() throws { credentials.withLock { $0 = [:] } }
    }

    /// Answers GOG API requests with canned JSON, keyed by URL path. Unknown paths get a 404, and
    /// downloads fail as if offline.
    nonisolated struct FixtureTransport: HTTPTransport {
        let routes: [String: String]

        func send(_ request: URLRequest) async throws -> HTTPResponse {
            guard let body = routes[request.url?.path() ?? ""] else {
                return HTTPResponse(data: Data("{}".utf8), status: 404)
            }
            return HTTPResponse(data: Data(body.utf8))
        }

        func download(_ request: URLRequest) async throws -> HTTPDownload {
            throw GOGError.transport(host: request.url?.host() ?? "")
        }
    }

    /// A small fake GOG account: three games, one with DLC.
    nonisolated enum PreviewData {
        static let witcherID = "1207658924"
        static let gwentID = "1971477531"
        static let tyrianID = "1207658959"
        static let dlcID = "1207659900"

        static let routes: [String: String] = [
            "/account/getFilteredProducts": """
            {"totalPages": 1, "products": [
              {"id": 1207658924, "title": "The Witcher: Enhanced Edition", "image": "//images-1.gog-statics.com/witcher",
               "worksOn": {"Windows": true, "Mac": true, "Linux": false}},
              {"id": 1971477531, "title": "Gwent: The Witcher Card Game", "image": "//images-1.gog-statics.com/gwent",
               "worksOn": {"Windows": true, "Mac": false, "Linux": false}},
              {"id": 1207658959, "title": "Tyrian 2000", "image": "//images-1.gog-statics.com/tyrian",
               "worksOn": {"Windows": true, "Mac": true, "Linux": true}}
            ]}
            """,
            "/user/data/games": #"{"owned": [1207658924, 1971477531, 1207658959, 1207659900]}"#,
            "/products/\(witcherID)": """
            {"id": 1207658924, "title": "The Witcher: Enhanced Edition", "release_date": "2008-10-30T00:00:00+0200",
             "images": {"background": "//images-1.gog-statics.com/witcher_bg.jpg",
                        "logo2x": "//images-1.gog-statics.com/witcher_logo.jpg",
                        "icon": "//images-1.gog-statics.com/witcher_icon.png"},
             "content_system_compatibility": {"windows": true, "osx": true, "linux": false},
             "description": {"lead": "<p>Become The Witcher, Geralt of Rivia, a legendary monster slayer.</p>",
               "full": "<p>Become <b>The Witcher</b>, Geralt of Rivia, a legendary monster slayer caught in a web of intrigue.</p><ul><li>Over 200 new animations</li><li>Improved dialogue</li></ul>"},
             "expanded_dlcs": [{"id": 1207659900, "title": "Adventure Pack", "images": {"icon": "//images-1.gog-statics.com/dlc_icon.png"}},
               {"id": 1207659901, "title": "Soundtrack Edition", "images": {}}],
             "languages": {"en": "English", "fr": "français", "de": "Deutsch", "pl": "polski"},
             "links": {"product_card": "https://www.gog.com/game/the_witcher", "forum": "https://www.gog.com/forum/the_witcher",
               "support": "https://www.gog.com/support/the_witcher"},
             "changelog": "<h4>Update 1.5.1</h4><ul><li>Fixed a crash when loading saves</li><li>Improved controller support</li></ul>",
             "downloads": {"installers": [
               {"os": "mac", "language": "en", "total_size": 9000000000}, {"os": "windows", "language": "en", "total_size": 10177478656},
               {"os": "windows", "language": "fr"}, {"os": "windows", "language": "de"}],
               "bonus_content": [{"name": "manual", "type": "manuals", "count": 1, "total_size": 12582912},
                 {"name": "soundtrack (MP3)", "type": "audio", "count": 2, "total_size": 180000000},
                 {"name": "artbook", "type": "artworks", "count": 1, "total_size": 76546048}]}}
            """,
            "/products/\(gwentID)": """
            {"id": 1971477531, "title": "Gwent: The Witcher Card Game", "images": {},
             "content_system_compatibility": {"windows": true, "osx": false, "linux": false},
             "description": {"lead": "<p>A card game set in the world of The Witcher.</p>"},
             "expanded_dlcs": [], "downloads": {"installers": [{"os": "windows", "language": "en"}]}}
            """,
            "/products/\(tyrianID)": """
            {"id": 1207658959, "title": "Tyrian 2000", "images": {}, "release_date": "1999-11-30T00:00:00+0200",
             "content_system_compatibility": {"windows": true, "osx": true, "linux": true},
             "description": {"lead": "<p>A vertical scrolling shooter.</p>"}, "expanded_dlcs": [],
             "downloads": {"installers": [{"os": "mac", "language": "en"}, {"os": "windows", "language": "en"},
               {"os": "linux", "language": "en"}]}}
            """,
            "/products/\(gwentID)/os/windows/builds": """
            {"items": [{"build_id": "7", "generation": 2, "branch": null, "version_name": "9.6", "public": true},
              {"build_id": "8", "generation": 2, "branch": "beta", "version_name": "9.7-beta", "public": true}],
             "has_private_branches": true}
            """,
            "/platforms/gog/external_releases/\(witcherID)": """
            {"game": {"summary": {"*": "Become Geralt of Rivia, a monster slayer caught in a web of intrigue."},
              "first_release_date": "2007-10-26T00:00:00+0000",
              "background": {"url_format": "https://images.gog.com/witcher-hero{formatter}.{ext}"},
              "screenshots": [{"url_format": "https://images.gog.com/witcher-shot-1{formatter}.{ext}"},
                {"url_format": "https://images.gog.com/witcher-shot-2{formatter}.{ext}"},
                {"url_format": "https://images.gog.com/witcher-shot-3{formatter}.{ext}"}],
              "artworks": [{"url_format": "https://images.gog.com/witcher-art-1{formatter}.{ext}"}],
              "videos": [{"provider": "youtube", "video_id": "preview1", "name": "Launch Trailer"},
                {"provider": "youtube", "video_id": "preview2", "name": "Gameplay"}],
              "developers": [{"name": "CD PROJEKT RED"}], "publishers": [{"name": "CD PROJEKT"}],
              "genres": [{"name": {"*": "Role-playing (RPG)"}}, {"name": {"*": "Adventure"}}],
              "themes": [{"name": {"*": "Fantasy"}}], "game_modes": [{"name": "Single player"}],
              "series": {"name": "The Witcher"}, "aggregated_rating": 86.2}}
            """,
            "/components/galaxy_client/clients/12345": """
            {"content": {"MacOS": {"cloudStorage": {"enabled": true, "locations": [
              {"name": "__default", "location": "<?INSTALL?>/saves"}]}},
             "Windows": {"cloudStorage": {"enabled": false, "locations": []}}}}
            """,
            "/products/\(witcherID)/os/osx/builds": """
            {"items": [
              {"build_id": "56", "generation": 2, "branch": null, "version_name": "1.5.1", "date_published": "2024-03-01T10:00:00+0000", "public": true},
              {"build_id": "55", "generation": 2, "branch": null, "version_name": "1.5", "date_published": "2023-06-01T10:00:00+0000", "public": true},
              {"build_id": "57", "generation": 2, "branch": "beta", "version_name": "1.6-beta", "date_published": "2024-05-01T10:00:00+0000", "public": true},
              {"build_id": "54", "generation": 2, "branch": null, "version_name": "1.4", "date_published": "2022-02-01T10:00:00+0000", "public": true},
              {"build_id": "12", "generation": 1, "branch": null, "version_name": "1.0", "date_published": "2012-09-01T10:00:00+0000", "public": true}
            ], "has_private_branches": false}
            """,
        ]

        /// Library games as `searchLibrary` returns them.
        static let gamesJSON = """
            [{"id": "1207658924", "title": "The Witcher: Enhanced Edition", "platforms": ["windows", "osx"]},
             {"id": "1971477531", "title": "Gwent: The Witcher Card Game", "platforms": ["windows"]},
             {"id": "1207658959", "title": "Tyrian 2000", "platforms": ["windows", "osx", "linux"]}]
            """

        static var games: [OwnedGame] {
            (try? JSONDecoder().decode([OwnedGame].self, from: Data(gamesJSON.utf8))) ?? []
        }

        static var update: AvailableUpdate? {
            try? JSONDecoder().decode(
                AvailableUpdate.self,
                from: Data(#"{"buildId": "56", "versionName": "1.5.1"}"#.utf8)
            )
        }

        static var witcherPlan: InstallPlan {
            InstallPlan(
                product: witcherID,
                platform: .osx,
                buildID: "55",
                version: "1.5",
                folder: "The Witcher Enhanced Edition",
                language: "en-US",
                files: []
            )
        }

        /// Writes a macOS installation of The Witcher, with two play tasks, under `folder`.
        static func writeInstallation(in folder: URL) throws -> URL {
            let root = folder.appending(path: witcherPlan.folder, directoryHint: .isDirectory)
            let resources = root.appending(path: "Contents/Resources", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: root.appending(path: ".gogdl"),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(witcherPlan).write(to: root.appending(path: ".gogdl/manifest.json"))
            let info = """
                {"gameId": "\(witcherID)", "rootGameId": "\(witcherID)", "clientId": "12345", "name": "The Witcher: Enhanced Edition",
                 "languages": ["en-US"], "playTasks": [
                   {"type": "FileTask", "name": "The Witcher", "path": "Contents/MacOS/Witcher", "isPrimary": true, "category": "game"},
                   {"type": "FileTask", "name": "Configuration", "path": "Contents/MacOS/Config", "category": "tool"},
                   {"type": "URLTask", "name": "Website", "link": "https://www.thewitcher.com", "category": "document"}]}
                """
            try Data(info.utf8).write(to: resources.appending(path: "goggame-\(witcherID).info"))
            return root
        }
    }

    extension AppModel {
        /// A model backed by fakes, for SwiftUI previews: no network, Keychain, or notifications.
        static func preview(
            signedIn: Bool = true,
            installed: Bool = true,
            downloading: Bool = true
        ) -> AppModel {
            let folder = FileManager.default.temporaryDirectory.appending(
                path: "MacGOG-Preview-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            let defaults = UserDefaults(suiteName: "MacGOG-Preview") ?? .standard
            defaults.removePersistentDomain(forName: "MacGOG-Preview")
            let model = AppModel(
                http: HTTPClient(transport: FixtureTransport(routes: PreviewData.routes), attempts: 1),
                store: signedIn ? InMemoryCredentialStore.signedIn() : InMemoryCredentialStore(),
                defaults: defaults,
                supportFolder: folder,
                artwork: ArtworkLoader(cache: folder.appending(path: "Artwork")),
                hooks: .none,
                sessionState: signedIn ? .signedIn : .signedOut
            )
            model.settings.libraryFolder = folder.appending(path: "Games", directoryHint: .isDirectory)
            guard signedIn else { return model }
            model.library.preload(games: PreviewData.games, ownedIDs: [PreviewData.dlcID])
            if installed, let root = try? PreviewData.writeInstallation(in: model.settings.libraryFolder),
                let installation = try? Installation(at: root)
            {
                let record = InstalledGameRecord(
                    entry: RegistryEntry(
                        productID: PreviewData.witcherID,
                        path: root.path,
                        title: "The Witcher: Enhanced Edition"
                    ),
                    status: .ready(installation),
                    info: try? InstalledGame.read(at: root)
                )
                model.registry.preload(
                    [record],
                    updates: PreviewData.update.map { [PreviewData.witcherID: $0] } ?? [:]
                )
            }
            if downloading {
                model.downloads.preload([PreviewData.downloadingJob(in: model.settings.libraryFolder)])
            }
            return model
        }
    }

    extension PreviewData {
        /// A job halfway through installing Tyrian 2000.
        @MainActor
        static func downloadingJob(in folder: URL) -> DownloadJob {
            let plan = InstallPlan(
                product: tyrianID,
                platform: .osx,
                buildID: "10",
                version: "2.1",
                folder: "Tyrian 2000",
                language: "en-US",
                files: []
            )
            let job = DownloadJob(
                productID: tyrianID,
                title: "Tyrian 2000",
                kind: .install(plan, folder: folder.appending(path: "Tyrian 2000")),
                state: .running
            )
            var counters = ProgressCounters()
            counters.apply(.started(files: 120, diskSize: 400_000_000, downloadSize: 380_000_000))
            job.progress.update(with: counters, at: 0)
            counters.downloaded = 150_000_000
            counters.completed = 160_000_000
            counters.filesDone = 48
            job.progress.update(with: counters, at: 10)
            return job
        }
    }
#endif
