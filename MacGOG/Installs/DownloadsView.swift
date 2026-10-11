import SwiftUI
import SwiftyGOG

/// Every job with its progress, speed, time remaining, and controls.
struct DownloadsView: View {
    @Environment(DownloadQueue.self) private var downloads

    var body: some View {
        List {
            ForEach(downloads.jobs) { job in
                DownloadRow(job: job)
            }
        }
        .overlay {
            if downloads.jobs.isEmpty {
                ContentUnavailableView(
                    "No downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Installs, updates, and repairs appear here.")
                )
            }
        }
        .navigationTitle("Downloads")
        .toolbar {
            ToolbarItemGroup {
                Button("Resume All") { downloads.resumeAll() }
                    .disabled(downloads.unfinishedJobs.allSatisfy(\.isActive))
                Button("Clear Finished") { downloads.clearFinished() }
                    .disabled(!downloads.jobs.contains { !$0.isUnfinished })
            }
        }
    }
}

private struct DownloadRow: View {
    let job: DownloadJob

    @Environment(DownloadQueue.self) private var downloads
    @State private var confirmingCancel = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(job.title)
                        .font(.headline)
                    Text(job.verb)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .background(.quaternary, in: .capsule)
                    Spacer()
                    Text(detail)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                switch job.state {
                case .running:
                    if let fraction = job.progress.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                case .paused:
                    if let fraction = job.progress.fraction {
                        ProgressView(value: fraction)
                            .tint(.secondary)
                    }
                default:
                    EmptyView()
                }
                Text(status)
                    .font(.caption)
                    .foregroundStyle(isFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
            }
            controls
        }
        .padding(.vertical, 6)
        .confirmationDialog(
            "Cancel \(job.verb.lowercased()) of \(job.title)?",
            isPresented: $confirmingCancel
        ) {
            Button("Cancel \(job.verb)", role: .destructive) { Task { await cancel(deleteFiles: false) } }
            if case .install = job.kind,
                !FileManager.default.fileExists(
                    atPath: job.folder.appending(path: ".gogdl/manifest.json").path
                )
            {
                Button("Cancel and Move Files to Trash", role: .destructive) {
                    Task { await cancel(deleteFiles: true) }
                }
            }
        } message: {
            Text("Downloaded data is kept unless you move it to the Trash, so starting again is faster.")
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 4) {
            switch job.state {
            case .running, .queued:
                Button {
                    downloads.pause(job)
                } label: {
                    Label("Pause", systemImage: "pause.circle")
                }
            case .paused, .failed:
                Button {
                    downloads.resume(job)
                } label: {
                    Label("Resume", systemImage: "play.circle")
                }
            case .finished:
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([job.folder])
                } label: {
                    Label("Show in Finder", systemImage: "magnifyingglass.circle")
                }
            }
            if job.isUnfinished {
                Button {
                    confirmingCancel = true
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.title2)
    }

    private var isFailed: Bool {
        if case .failed = job.state { true } else { false }
    }

    private var symbol: String {
        switch job.state {
        case .queued: "clock"
        case .running: "arrow.down.circle.fill"
        case .paused: "pause.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .finished: "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch job.state {
        case .failed: .red
        case .finished: .green
        case .running: .accentColor
        default: .secondary
        }
    }

    private var detail: String {
        let counters = job.progress.counters
        guard counters.diskSize > 0 else { return "" }
        return "\(counters.completed.formattedBytes) of \(counters.diskSize.formattedBytes)"
    }

    private var status: String {
        switch job.state {
        case .queued:
            return "Waiting…"
        case .running:
            var parts = [job.progress.phaseText]
            if job.progress.bytesPerSecond > 0 {
                parts.append(job.progress.bytesPerSecond.formattedRate)
            }
            if let remaining = job.progress.remaining {
                parts.append("\(remaining.formattedRemaining) left")
            }
            return parts.joined(separator: " · ")
        case .paused:
            return "Paused"
        case .failed(let error):
            return "\(error.title): \(error.message)"
        case .finished(let result):
            return
                "Done · \(result.installed) files installed, \(result.downloadedBytes.formattedBytes) downloaded"
        }
    }

    private func cancel(deleteFiles: Bool) async {
        await downloads.cancel(job)
        if deleteFiles {
            try? FileManager.default.trashItem(at: job.folder, resultingItemURL: nil)
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            DownloadsView()
        }
        .modelEnvironment(.preview())
        .frame(width: 700, height: 400)
    }
#endif
