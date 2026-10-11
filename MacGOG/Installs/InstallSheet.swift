import SwiftUI
import SwiftyGOG

/// Chooses platform, language, DLC, branch, build, and destination, shows the planned sizes, and
/// queues the job. Choosing an older build of an installed game downgrades it.
struct InstallSheet: View {
    /// A build to preselect, such as one picked from a game's build list.
    struct BuildRequest: Hashable {
        let platform: GamePlatform
        let id: String
    }

    /// What a sheet is opened for.
    struct Request: Identifiable {
        let mode: Mode
        var build: BuildRequest?

        var id: String { "\(mode.id)-\(build?.id ?? "latest")" }
    }

    enum Mode: Identifiable {
        /// A new install into the library folder.
        case install
        /// An update or downgrade of an installed game, optionally with different language or DLC.
        case modify(InstalledGameRecord)
        /// Installs over an existing folder, such as one from Galaxy or one with a damaged manifest.
        case adopt(InstalledGameRecord)

        var id: String {
            switch self {
            case .install: "install"
            case .modify(let record): "modify-\(record.id)"
            case .adopt(let record): "adopt-\(record.id)"
            }
        }
    }

    let id: String
    let title: String
    let mode: Mode
    var requestedBuild: BuildRequest?

    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var platform = GamePlatform.osx
    @State private var language = "en-US"
    @State private var selectedDLCs: Set<String> = []
    @State private var branch: String?
    @State private var password = ""
    @State private var libraryFolder = URL.homeDirectory
    @State private var details: ProductDetails?
    @State private var branches: [String] = []
    /// Every build for the platform, newest first.
    @State private var buildList: BuildList?
    /// `nil` installs the newest build on the branch.
    @State private var selectedBuild: String?
    @State private var appliedRequest = false
    @State private var hasPrivateBranches = false
    /// The latest plan and the choices it was made for.
    @State private var planned: (inputs: PlanInputs, plan: InstallPlan)?
    @State private var planError: PresentableError?
    @State private var confirmError: PresentableError?
    @State private var isReady = false

    private struct PlanInputs: Hashable {
        let isReady: Bool
        let platform: GamePlatform
        let language: String
        let dlcs: Set<String>
        let branch: String?
        let build: String?
        let password: String
    }

    private var inputs: PlanInputs {
        PlanInputs(
            isReady: isReady,
            platform: platform,
            language: language,
            dlcs: selectedDLCs,
            branch: branch,
            build: selectedBuild,
            password: password
        )
    }

    /// The plan for the current choices; `nil` while they're being planned, so an earlier plan is
    /// never shown or installed for newer choices.
    private var plan: InstallPlan? {
        guard let planned, planned.inputs == inputs else { return nil }
        return planned.plan
    }

    private var options: DownloadOptions {
        DownloadOptions(
            platform: platform,
            language: language,
            build: selectedBuild,
            branch: branch,
            password: password.isEmpty ? nil : password,
            includeDLCs: !selectedDLCs.isEmpty,
            dlcIDs: selectedDLCs,
            workers: settings.workers
        )
    }

    private var record: InstalledGameRecord? {
        switch mode {
        case .install: nil
        case .modify(let record), .adopt(let record): record
        }
    }

    private var isModifying: Bool {
        if case .modify = mode { true } else { false }
    }

    private var availablePlatforms: [GamePlatform] {
        if isModifying, let platform = record?.platform {
            return [platform]
        }
        let listed = details?.platforms ?? library.game(id)?.platforms ?? []
        return listed.isEmpty ? GamePlatform.allCases : listed
    }

    /// Builds on the chosen branch, newest first.
    private var branchBuilds: [GameBuild] {
        (buildList?.builds ?? []).filter { $0.branch == branch }
    }

    private var installedBuildID: String? {
        if case .modify(let record) = mode { record.installation?.plan.buildID } else { nil }
    }

    /// Whether the chosen build is older than the installed one.
    private var isDowngrade: Bool {
        guard let target = selectedBuild ?? branchBuilds.first?.id, let installedBuildID else { return false }
        return buildList?.isBuild(target, olderThan: installedBuildID) ?? false
    }

    private var languages: [Language] {
        let shipped = details?.languages(for: platform) ?? []
        return shipped.isEmpty ? Language.all : shipped
    }

    private var ownedDLCs: [ProductDLC] {
        details.map(library.ownedDLCs) ?? []
    }

    private var destination: URL? {
        if let record {
            return record.entry.folder
        }
        return plan.map { libraryFolder.appending(path: $0.folder, directoryHint: .isDirectory) }
    }

    private var heading: String {
        switch mode {
        case .install: "Install \(title)"
        case .modify: "Change \(title)"
        case .adopt: "Verify \(title)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heading)
                .font(.title2.bold())
                .padding([.horizontal, .top], 20)
            Form {
                Section {
                    Picker("Platform", selection: $platform) {
                        ForEach(availablePlatforms, id: \.self) { platform in
                            Label(platform.displayName, systemImage: platform.symbolName).tag(platform)
                        }
                    }
                    .disabled(availablePlatforms.count < 2)
                    Picker("Language", selection: $language) {
                        ForEach(languages, id: \.code) { language in
                            Text(language.displayName).tag(language.code)
                        }
                    }
                    if platform != .linux {
                        Picker("Branch", selection: $branch) {
                            Text("Default").tag(String?.none)
                            ForEach(branches, id: \.self) { branch in
                                Text(branch).tag(String?.some(branch))
                            }
                        }
                        if !branchBuilds.isEmpty {
                            Picker("Build", selection: $selectedBuild) {
                                Text("Latest (\(branchBuilds.first.map(label) ?? ""))").tag(String?.none)
                                Divider()
                                ForEach(branchBuilds, id: \.id) { build in
                                    Text(label(build)).tag(String?.some(build.id))
                                }
                            }
                        }
                        if hasPrivateBranches || !password.isEmpty {
                            SecureField("Branch password", text: $password)
                        }
                    }
                } footer: {
                    if isDowngrade {
                        Text(
                            "This installs an older build. MacGOG keeps offering the newest build as an update."
                        )
                    }
                }
                if !ownedDLCs.isEmpty {
                    Section("DLC") {
                        ForEach(ownedDLCs, id: \.id) { dlc in
                            Toggle(
                                dlc.title,
                                isOn: Binding(
                                    get: { selectedDLCs.contains(dlc.id) },
                                    set: { selected in
                                        if selected {
                                            selectedDLCs.insert(dlc.id)
                                        } else {
                                            selectedDLCs.remove(dlc.id)
                                        }
                                    }
                                )
                            )
                        }
                    }
                }
                Section("Destination") {
                    if case .install = mode {
                        LabeledContent("Library folder") {
                            HStack {
                                Text(libraryFolder.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button("Choose…") {
                                    if let folder = FolderPicker.choose(
                                        message: "Choose where to install \(title).",
                                        directory: libraryFolder
                                    ) {
                                        libraryFolder = folder
                                    }
                                }
                            }
                        }
                    }
                    LabeledContent("Game folder") {
                        Text(destination?.path ?? "—")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                Section {
                    sizes
                }
            }
            .formStyle(.grouped)
            if let error = confirmError ?? planError {
                ErrorBanner(error: error)
                    .padding(.horizontal, 20)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(plan == nil)
            }
            .padding(20)
        }
        .frame(width: 520)
        .task { await prepare() }
        .task(id: inputs) { await replan() }
        .task(id: BranchQuery(platform: platform, password: password)) { await loadBranches() }
        .onChange(of: branch) {
            if let selectedBuild, !branchBuilds.contains(where: { $0.id == selectedBuild }) {
                self.selectedBuild = nil
            }
        }
        .onChange(of: platform) {
            if !languages.contains(where: { $0.code == language }), let first = languages.first {
                language = first.code
            }
        }
    }

    @ViewBuilder private var sizes: some View {
        if let plan {
            LabeledContent("Download", value: plan.downloadSize.formattedBytes)
            LabeledContent("Size on disk", value: plan.diskSize.formattedBytes)
            if let version = plan.version.flatMap({ $0.isEmpty ? nil : $0 }) ?? plan.buildID {
                LabeledContent("Version", value: version)
            }
            if let available = destination?.availableCapacity {
                LabeledContent("Available", value: available.formattedBytes)
            }
        } else if planError == nil {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Calculating size…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var confirmTitle: String {
        switch mode {
        case .install:
            return "Install"
        case .adopt:
            return "Verify"
        case .modify:
            let target = selectedBuild ?? branchBuilds.first?.id
            if target != nil, target == installedBuildID {
                return "Apply"
            }
            return isDowngrade ? "Downgrade" : "Update"
        }
    }

    /// A build's version, date, and whether it's installed, for the picker.
    private func label(_ build: GameBuild) -> String {
        var parts = [build.version ?? "Build \(build.id)"]
        if let date = build.publishedDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if build.generation == 1 {
            parts.append("legacy")
        }
        if build.id == installedBuildID {
            parts.append("installed")
        }
        return parts.joined(separator: " · ")
    }

    /// Sets the starting choices from settings or the installed game.
    private func prepare() async {
        libraryFolder = settings.libraryFolder
        language = settings.defaultLanguage
        switch mode {
        case .install:
            break
        case .modify(let record):
            if let installed = record.installation {
                let options = installed.options
                platform = options.platform
                language = options.language
                branch = options.branch
            }
        case .adopt(let record):
            if let platform = record.platform {
                self.platform = platform
            }
            if let code = record.info.flatMap({ Language.match($0.installedLanguage)?.code }) {
                language = code
            }
        }
        if let requestedBuild, !isModifying {
            platform = requestedBuild.platform
        } else if case .install = mode {
            let listed = library.game(id)?.platforms ?? []
            platform =
                if listed.contains(settings.defaultPlatform) {
                    settings.defaultPlatform
                } else if listed.contains(.osx) {
                    .osx
                } else {
                    listed.first ?? .osx
                }
        }
        do {
            details = try await library.details(for: id)
        } catch {
            await model.handle(error, retry: nil)
        }
        selectedDLCs = initialDLCs()
        if !languages.contains(where: { $0.code == language }), let first = languages.first {
            language = first.code
        }
        isReady = true
    }

    /// The DLC to start with: the installed selection when changing a game, otherwise every owned
    /// DLC. Saved choices list no IDs when every owned DLC was included.
    private func initialDLCs() -> Set<String> {
        let owned = Set(ownedDLCs.map(\.id))
        guard case .modify(let record) = mode, let options = record.installation?.options else {
            return owned
        }
        guard options.includeDLCs else { return [] }
        return options.dlcIDs.isEmpty ? owned : options.dlcIDs
    }

    private func replan() async {
        guard isReady else { return }
        let requested = inputs
        planError = nil
        confirmError = nil
        // Let quick successive changes settle before asking GOG.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let plan = try await ManifestService(client: model.client).plan(id, options: options)
            guard !Task.isCancelled else { return }
            planned = (requested, plan)
        } catch {
            guard !Task.isCancelled else { return }
            if await model.session.handle(error) {
                dismiss()
                return
            }
            planError = presentableError(error)
        }
    }

    private struct BranchQuery: Hashable {
        let platform: GamePlatform
        let password: String
    }

    private func loadBranches() async {
        guard platform != .linux,
            let list = try? await model.client.buildList(
                id,
                platform: platform,
                password: password.isEmpty ? nil : password
            )
        else {
            branches = []
            buildList = nil
            return
        }
        buildList = list
        var seen: [String] = []
        for build in list.builds {
            if let branch = build.branch, !seen.contains(branch) {
                seen.append(branch)
            }
        }
        branches = seen
        hasPrivateBranches = list.hasPrivateBranches
        if let branch, !seen.contains(branch) {
            self.branch = nil
        }
        // Preselect a requested build once, on its branch.
        if !appliedRequest, let requestedBuild, requestedBuild.platform == platform {
            appliedRequest = true
            if let build = list.builds.first(where: { $0.id == requestedBuild.id }) {
                branch = build.branch
                selectedBuild = build.id
            }
        }
    }

    private func confirm() {
        guard let plan, let destination else { return }
        switch mode {
        case .install, .adopt:
            if let available = destination.availableCapacity, plan.diskSize > available {
                confirmError =
                    AppError.notEnoughSpace(needed: plan.diskSize, available: available).presentable
                return
            }
            if case .install = mode, settings.libraryFolder != libraryFolder {
                settings.libraryFolder = libraryFolder
            }
            model.downloads.enqueue(.install(plan, folder: destination), productID: id, title: title)
        case .modify(let record):
            model.update(record, options: options)
        }
        dismiss()
    }
}

#if DEBUG
    #Preview("Install") {
        InstallSheet(id: PreviewData.witcherID, title: "The Witcher: Enhanced Edition", mode: .install)
            .modelEnvironment(.preview(installed: false))
    }

    #Preview("Downgrade") {
        let model = AppModel.preview()
        if let record = model.registry.record(for: PreviewData.witcherID) {
            InstallSheet(
                id: PreviewData.witcherID,
                title: "The Witcher: Enhanced Edition",
                mode: .modify(record),
                requestedBuild: InstallSheet.BuildRequest(platform: .osx, id: "54")
            )
            .modelEnvironment(model)
        }
    }
#endif
