import SwiftUI
import SwiftyGOG

/// The main buttons for a game, which depend on its installation status. They sit over the hero
/// art, so they use glass.
struct GameActions: View {
    let id: String
    @Binding var sheet: InstallSheet.Request?

    @Environment(AppModel.self) private var model
    @Environment(LaunchController.self) private var launcher
    @Environment(\.openSettings) private var openSettings
    @State private var confirmingUninstall = false

    var body: some View {
        let record = model.registry.record(for: id)
        HStack(spacing: 10) {
            switch model.status(of: id) {
            case .notInstalled:
                Button {
                    sheet = InstallSheet.Request(mode: .install)
                } label: {
                    Label("Install…", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.glassProminent)
            case .installing(let job):
                JobControls(job: job)
            case .running:
                Button(role: .destructive) {
                    launcher.stop(id)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                Text("Playing")
                    .foregroundStyle(.white.opacity(0.8))
            case .installed, .updateAvailable:
                if let record {
                    PlayButton(record: record)
                    if let update = model.registry.updates[id] {
                        Button {
                            model.update(record)
                        } label: {
                            Label(
                                "Update to \(update.version.flatMap { $0.isEmpty ? nil : $0 } ?? "the Latest Build")",
                                systemImage: "arrow.down.circle"
                            )
                        }
                        .buttonStyle(.glass)
                    }
                    moreMenu(record)
                }
            case .foreign:
                if let record {
                    PlayButton(record: record)
                    Button("Verify with GOG…") { sheet = InstallSheet.Request(mode: .adopt(record)) }
                        .buttonStyle(.glass)
                        .help("Check this game's files against GOG so MacGOG can update and repair it.")
                    moreMenu(record)
                }
            case .needsRepair:
                if let record {
                    Button("Reinstall…") { sheet = InstallSheet.Request(mode: .adopt(record)) }
                        .buttonStyle(.glassProminent)
                    Label(
                        "This game's install data is damaged.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    moreMenu(record)
                }
            case .missing:
                if let record {
                    Button("Locate…") {
                        if let folder = FolderPicker.choose(message: "Find the folder of \(record.title).") {
                            Task { await model.locate(record, at: folder) }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    Button("Remove from Library") { model.registry.remove(id) }
                        .buttonStyle(.glass)
                    Label("The game folder is missing.", systemImage: "questionmark.folder.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .controlSize(.large)
        .confirmationDialog("Uninstall \(record?.title ?? "this game")?", isPresented: $confirmingUninstall) {
            Button("Move to Trash", role: .destructive) {
                if let record {
                    Task { await model.uninstall(record) }
                }
            }
        } message: {
            Text("The game folder moves to the Trash. Cloud saves aren't affected.")
        }
    }

    private func moreMenu(_ record: InstalledGameRecord) -> some View {
        Menu {
            if record.installation != nil {
                Button("Verify and Repair") { model.repair(record) }
                Button("Change Version, Language, or DLC…") {
                    sheet = InstallSheet.Request(mode: .modify(record))
                }
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([record.entry.folder])
            }
            if record.platform == .windows {
                if record.installation != nil {
                    Button("Run Setup Again") {
                        Task {
                            do {
                                try await launcher.runSetup(record)
                            } catch {
                                model.present(error)
                            }
                        }
                    }
                    .help("Install the game's runtimes and run its install script again in its bottle.")
                }
                Button("Windows Game Settings…") { openSettings() }
            }
            Divider()
            Button("Uninstall…", role: .destructive) { confirmingUninstall = true }
            Button("Remove from Library") { model.registry.remove(record.id) }
                .help("Forget this game without deleting its files.")
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More")
    }
}

/// Play, with a menu of the game's other play tasks.
private struct PlayButton: View {
    let record: InstalledGameRecord

    @Environment(AppModel.self) private var model
    @Environment(LaunchController.self) private var launcher

    private var tasks: [PlayTask] { record.info?.playTasks.filter { $0.kind == .file } ?? [] }

    private var links: [PlayTask] { record.info?.playTasks.filter { $0.kind == .url } ?? [] }

    var body: some View {
        let blocker = launcher.blocker(for: record)
        let preparing = launcher.isPreparing(record.id)
        HStack(spacing: 4) {
            Button {
                play(nil)
            } label: {
                if preparing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(launcher.preparingStatus[record.id] ?? "Starting…")
                    }
                    .padding(.horizontal, 6)
                } else {
                    Label("Play", systemImage: "play.fill")
                        .padding(.horizontal, 6)
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(preparing)
            if tasks.count > 1 || !links.isEmpty {
                Menu {
                    ForEach(tasks, id: \.index) { task in
                        Button(task.name ?? "Task \(task.index + 1)") { play(task.index) }
                    }
                    if !links.isEmpty {
                        Divider()
                        ForEach(links, id: \.index) { task in
                            if let link = task.link {
                                Link(task.name ?? link.host() ?? "Link", destination: link)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuIndicator(.hidden)
                .buttonStyle(.glassProminent)
                .fixedSize()
                .help("Other ways to start the game")
                .accessibilityLabel("Other ways to start the game")
            }
        }
        .disabled(blocker != nil)
        .help(blocker?.presentable.message ?? "")
    }

    private func play(_ task: Int?) {
        Task {
            do {
                try await launcher.launch(record, task: task)
            } catch {
                model.present(error)
            }
        }
    }
}

/// Progress and controls for a game's job, in a glass panel over the art.
private struct JobControls: View {
    let job: DownloadJob

    @Environment(DownloadQueue.self) private var downloads

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.headline)
                    if let detail {
                        Text(detail)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 24)
                switch job.state {
                case .running, .queued:
                    Button("Pause") { downloads.pause(job) }
                        .buttonStyle(.glass)
                case .paused, .failed:
                    Button("Resume") { downloads.resume(job) }
                        .buttonStyle(.glassProminent)
                case .finished:
                    EmptyView()
                }
                Button("Cancel", role: .destructive) { Task { await downloads.cancel(job) } }
                    .buttonStyle(.glass)
            }
            if let fraction = job.progress.fraction {
                ProgressView(value: fraction)
            } else if job.isRunning {
                ProgressView()
                    .progressViewStyle(.linear)
            }
        }
        .controlSize(.regular)
        .padding(14)
        .frame(width: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var statusText: String {
        switch job.state {
        case .queued: "\(job.verb) queued"
        case .running: "\(job.verb): \(job.progress.phaseText)"
        case .paused: "\(job.verb) paused"
        case .failed(let error): error.title
        case .finished: "\(job.verb) finished"
        }
    }

    private var detail: String? {
        if case .failed(let error) = job.state {
            return error.message
        }
        let progress = job.progress
        guard job.isRunning, progress.counters.diskSize > 0 else { return nil }
        var parts = [
            "\(progress.counters.completed.formattedBytes) of \(progress.counters.diskSize.formattedBytes)"
        ]
        if progress.bytesPerSecond > 0 {
            parts.append(progress.bytesPerSecond.formattedRate)
        }
        if let remaining = progress.remaining {
            parts.append("\(remaining.formattedRemaining) left")
        }
        return parts.joined(separator: " · ")
    }
}
