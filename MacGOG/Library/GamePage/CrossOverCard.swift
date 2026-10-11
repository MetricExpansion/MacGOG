import SwiftUI
import SwiftyGOG

/// Which CrossOver bottle a Windows game runs in, and its graphics settings.
struct CrossOverCard: View {
    let record: InstalledGameRecord

    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(CrossOverModel.self) private var crossOver
    @Environment(LaunchController.self) private var launcher

    var body: some View {
        Card("CrossOver", systemImage: "wineglass") {
            if crossOver.isInstalled {
                installed
            } else {
                Text(
                    "CrossOver runs this Windows game on your Mac. Install it, or choose another Wine in Settings."
                )
                .foregroundStyle(.secondary)
                Link("Get CrossOver", destination: URL(string: "https://www.codeweavers.com/crossover")!)
            }
        }
        .task { crossOver.refresh() }
    }

    @ViewBuilder private var installed: some View {
        let bottle = crossOver.bottle(for: record.id)
        let busy = launcher.isRunning(record.id) || launcher.isPreparing(record.id)
        bottlePicker(current: bottle)
            .disabled(busy || crossOver.creating.contains(record.id))
        if crossOver.creating.contains(record.id) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Creating a bottle…")
                    .foregroundStyle(.secondary)
            }
        } else if let bottle {
            if crossOver.canEditSettings(for: record.id) {
                SettingsEditor(settings: bottle.settings) { updated in
                    do {
                        try crossOver.updateSettings(updated, for: record.id)
                    } catch {
                        model.present(error)
                    }
                }
                .disabled(busy)
                .id(bottle.name)
                if busy {
                    Text("Changes apply the next time the game starts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text("Graphics").foregroundStyle(.secondary)
                        Text(bottle.settings.graphics?.displayName ?? "Automatic")
                    }
                    GridRow {
                        Text("MSync").foregroundStyle(.secondary)
                        Text(bottle.settings.msync ? "On" : "Off")
                    }
                }
                Text("This bottle is yours, so change its settings in CrossOver.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Open CrossOver") { crossOver.openCrossOver() }
                    .buttonStyle(.glass)
                Button("Show C: Drive") {
                    NSWorkspace.shared.activateFileViewerSelecting([bottle.url.appending(path: "drive_c")])
                }
                .buttonStyle(.glass)
            }
        } else {
            Text("MacGOG creates a bottle for this game the first time you play it.")
                .foregroundStyle(.secondary)
            Button("Create Bottle Now") {
                Task {
                    do {
                        try await crossOver.createBottle(
                            for: record.id,
                            title: record.title,
                            settings: settings.newBottleSettings
                        )
                    } catch {
                        model.present(error)
                    }
                }
            }
            .buttonStyle(.glass)
        }
    }

    private func bottlePicker(current: CrossOverBottle?) -> some View {
        HStack {
            Text("Bottle")
                .foregroundStyle(.secondary)
            bottleMenu(current: current)
        }
    }

    private func bottleMenu(current: CrossOverBottle?) -> some View {
        Menu {
            ForEach(crossOver.bottles, id: \.name) { bottle in
                Button {
                    crossOver.assign(bottle.name, to: record.id)
                } label: {
                    if bottle.name == current?.name {
                        Label(bottle.name, systemImage: "checkmark")
                    } else {
                        Text(bottle.name)
                    }
                }
            }
            if !crossOver.bottles.isEmpty {
                Divider()
            }
            Button("New Bottle for This Game") {
                Task {
                    do {
                        try await crossOver.createBottle(
                            for: record.id,
                            title: record.title,
                            settings: settings.newBottleSettings
                        )
                    } catch {
                        model.present(error)
                    }
                }
            }
        } label: {
            Text(current?.name ?? "None yet")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// Graphics backend, MSync, and MetalFX controls for a bottle.
struct SettingsEditor: View {
    @State var settings: CrossOverSettings
    let apply: (CrossOverSettings) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Graphics", selection: $settings.graphics) {
                Text("Automatic").tag(CrossOverSettings.Graphics?.none)
                ForEach(CrossOverSettings.Graphics.allCases, id: \.self) { graphics in
                    Text(graphics.displayName).tag(CrossOverSettings.Graphics?.some(graphics))
                }
            }
            Toggle("MSync", isOn: $settings.msync)
                .help("Faster thread synchronization; most games run better with it on.")
            Toggle("MetalFX upscaling", isOn: $settings.metalFX)
                .disabled(settings.graphics != .d3dMetal && settings.graphics != nil)
                .help("Upscales with Apple's MetalFX. Needs D3DMetal.")
        }
        .onChange(of: settings) { apply(settings) }
    }
}

extension CrossOverSettings.Graphics {
    var displayName: String {
        switch self {
        case .d3dMetal: "D3DMetal"
        case .dxvk: "DXVK"
        case .wined3d: "WineD3D"
        }
    }

    /// When to pick it, for help text.
    var summary: String {
        switch self {
        case .d3dMetal: "Apple's translation to Metal. Best for most DirectX 11 and 12 games."
        case .dxvk: "Translation through Vulkan. Often best for DirectX 9 to 11 games."
        case .wined3d: "Wine's OpenGL translation. For older games that misbehave with the others."
        }
    }
}
