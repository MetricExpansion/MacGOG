import SwiftUI
import SwiftyGOG

/// The Settings window.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Windows Games", systemImage: "pc") { WindowsSettings() }
            Tab("Account", systemImage: "person.crop.circle") { AccountSettings() }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Installing") {
                LabeledContent("Library folder") {
                    HStack {
                        Text(settings.libraryFolder.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") {
                            if let folder = FolderPicker.choose(
                                message: "Choose where new games are installed.",
                                directory: settings.libraryFolder
                            ) {
                                settings.libraryFolder = folder
                            }
                        }
                    }
                }
                Picker("Default platform", selection: $settings.defaultPlatform) {
                    ForEach(GamePlatform.allCases, id: \.self) { platform in
                        Text(platform.displayName).tag(platform)
                    }
                }
                Picker("Default language", selection: $settings.defaultLanguage) {
                    ForEach(Language.all, id: \.code) { language in
                        Text(language.displayName).tag(language.code)
                    }
                }
            }
            Section("Downloads") {
                Stepper(value: $settings.workers, in: 1...32) {
                    LabeledContent("Connections per download", value: "\(settings.workers)")
                }
                Stepper(value: $settings.concurrentJobs, in: 1...4) {
                    LabeledContent("Downloads at once", value: "\(settings.concurrentJobs)")
                }
                Toggle("Check for updates when MacGOG opens", isOn: $settings.checkUpdatesAtLaunch)
            }
            Section("Cloud saves") {
                Toggle(
                    "Sync saves before playing and after quitting a game",
                    isOn: $settings.syncSavesAroundLaunch
                )
            }
        }
        .formStyle(.grouped)
    }
}

private struct WindowsSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                LabeledContent("Wine binary") {
                    HStack {
                        TextField(
                            "Wine binary",
                            text: $settings.winePath,
                            prompt: Text("/opt/homebrew/bin/wine64")
                        )
                        .labelsHidden()
                        Button("Choose…") {
                            if let file = FolderPicker.chooseExecutable(
                                message: "Choose Wine or a compatible launcher."
                            ) {
                                settings.winePath = file.path
                            }
                        }
                    }
                }
                if !settings.winePath.isEmpty, !settings.isWineConfigured {
                    Label("No executable file is at that path.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text(
                    "MacGOG doesn't include Wine. Install Wine, CrossOver, or a similar tool, then choose its binary."
                )
            }
            Section {
                LabeledContent("Prefixes folder") {
                    HStack {
                        Text(settings.winePrefixesFolder.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") {
                            if let folder = FolderPicker.choose(
                                message: "Choose where Wine prefixes are kept.",
                                directory: settings.winePrefixesFolder
                            ) {
                                settings.winePrefixesFolder = folder
                            }
                        }
                    }
                }
                TextField(
                    "Launch wrapper",
                    text: $settings.launchWrapper,
                    prompt: Text("Optional, such as gamemoderun")
                )
            } footer: {
                Text(
                    "Each Windows game gets its own Wine prefix in this folder. The wrapper command runs before every game."
                )
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccountSettings: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        Form {
            Section {
                LabeledContent("GOG account") {
                    Text(session.isSignedIn ? "Signed in" : "Signed out")
                }
                if session.isSignedIn {
                    Button("Sign Out") { Task { await session.signOut() } }
                } else {
                    Button("Sign In…") { session.isPresentingLogin = true }
                }
            } footer: {
                Text("MacGOG keeps its sign-in in your Keychain, separate from the gogdl command-line tool.")
            }
        }
        .formStyle(.grouped)
    }
}

#if DEBUG
    #Preview {
        SettingsView()
            .modelEnvironment(.preview())
    }
#endif
