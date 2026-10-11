import AppKit
import SwiftUI

@main
struct MacGOGApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("MacGOG", id: "main") {
            RootView()
                .modelEnvironment(delegate.model)
        }
        .defaultSize(width: 1100, height: 720)
        .commands { AppCommands(model: delegate.model) }

        Settings {
            SettingsView()
                .modelEnvironment(delegate.model)
        }
    }
}

/// AppKit lifecycle: start-up, and confirming before quitting during downloads.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel = {
        #if DEBUG
            // `-UsePreviewData YES` runs the app on the SwiftUI preview fakes, for UI work without an account.
            if UserDefaults.standard.bool(forKey: "UsePreviewData") {
                return .preview()
            }
        #endif
        return .live()
    }()

    private var usesPreviewData: Bool {
        #if DEBUG
            UserDefaults.standard.bool(forKey: "UsePreviewData")
        #else
            false
        #endif
    }

    /// Unit tests run inside the app; they build their own models and mustn't touch the Keychain.
    private var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isTesting, !usesPreviewData else { return }
        Task { await model.start() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.downloads.hasRunningJobs else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit while downloading?"
        alert.informativeText = "Downloads will stop. MacGOG offers to resume them the next time it opens."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !model.downloads.hasRunningJobs
    }
}

extension View {
    /// Puts the app model and each feature model in the environment.
    func modelEnvironment(_ model: AppModel) -> some View {
        environment(model)
            .environment(model.settings)
            .environment(model.session)
            .environment(model.library)
            .environment(model.registry)
            .environment(model.downloads)
            .environment(model.launcher)
            .environment(model.cloudSaves)
            .environment(model.crossOver)
            .environment(\.artworkLoader, model.artwork)
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About MacGOG") { AboutPanel.show() }
        }
        CommandGroup(after: .newItem) {
            Button("Add Existing Game…") {
                if let folder = FolderPicker.choose(
                    message: "Choose a game folder installed by GOG Galaxy, gogdl, or MacGOG."
                ) {
                    Task { await model.addExistingGame(at: folder) }
                }
            }
            .keyboardShortcut("o")
            .disabled(!model.session.isSignedIn)
        }
        CommandMenu("Library") {
            Button("Refresh Library") { Task { await model.refreshLibrary() } }
                .keyboardShortcut("r")
                .disabled(!model.session.isSignedIn || model.library.isLoading)
            Button("Check for Updates") { Task { await model.checkForUpdates() } }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(!model.session.isSignedIn || model.registry.isCheckingForUpdates)
            Divider()
            Button("Resume All Downloads") { model.downloads.resumeAll() }
                .disabled(model.downloads.unfinishedJobs.allSatisfy(\.isActive))
            Divider()
            if model.session.isSignedIn {
                Button("Sign Out") { Task { await model.session.signOut() } }
            } else {
                Button("Sign In…") { model.session.isPresentingLogin = true }
            }
        }
    }
}

enum AboutPanel {
    static func show() {
        let credits = NSMutableAttributedString(
            string: """
                MacGOG is free software under the GNU General Public License, version 3. \
                It is built on SwiftyGOG (GPL-3.0).
                Source code:
                """,
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        )
        let link = "https://github.com/MetricExpansion/MacGOG"
        credits.append(
            NSAttributedString(
                string: link,
                attributes: [
                    .link: URL(string: link) as Any,
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                ]
            )
        )
        credits.append(
            NSAttributedString(
                string: "\nMacGOG isn't affiliated with GOG or CD PROJEKT.",
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
            )
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }
}

enum FolderPicker {
    /// Asks for one folder, starting in `directory`.
    static func choose(message: String, directory: URL? = nil, prompt: String = "Choose") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = prompt
        panel.directoryURL = directory
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Asks for one executable file.
    static func chooseExecutable(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }
}
