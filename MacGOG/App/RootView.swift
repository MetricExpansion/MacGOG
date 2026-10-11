import SwiftUI
import SwiftyGOG

/// Sign-in or the library, plus app-wide sheets and alerts.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(SessionModel.self) private var session
    @Environment(CloudSaveModel.self) private var cloudSaves
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var session = session
        Group {
            switch session.state {
            case .unknown:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedIn:
                MainView()
            case .signedOut, .signingIn, .failed:
                SignInView()
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .sheet(isPresented: $session.isPresentingLogin) {
            LoginView()
        }
        .alert(
            model.presentedError?.error.title ?? "",
            isPresented: Binding(
                get: { model.presentedError != nil },
                set: { if !$0 { model.presentedError = nil } }
            ),
            presenting: model.presentedError
        ) { presented in
            ForEach(presented.error.recoveries, id: \.self) { recovery in
                switch recovery {
                case .signIn:
                    Button("Sign In") {
                        Task {
                            await session.signOut()
                            session.isPresentingLogin = true
                        }
                    }
                case .retry:
                    if let retry = presented.retry {
                        Button("Try Again", action: retry)
                    }
                case .openSettings:
                    Button("Open Settings") { openSettings() }
                case .chooseFolder:
                    EmptyView()
                }
            }
            Button("OK", role: .cancel) {}
        } message: { presented in
            Text(presented.error.message)
        }
        .alert(
            "Cloud saves conflict",
            isPresented: Binding(
                get: { cloudSaves.pendingConflict != nil },
                set: {
                    if !$0, let conflict = cloudSaves.pendingConflict {
                        cloudSaves.resolve(conflict, with: nil)
                    }
                }
            ),
            presenting: cloudSaves.pendingConflict
        ) { conflict in
            Button("Keep This Mac's Saves") { cloudSaves.resolve(conflict, with: .forceUpload) }
            Button("Keep Cloud Saves") { cloudSaves.resolve(conflict, with: .forceDownload) }
            Button("Skip", role: .cancel) { cloudSaves.resolve(conflict, with: nil) }
        } message: { conflict in
            Text(
                "\(conflict.title)'s saves changed on this Mac and in the cloud since the last sync. "
                    + "The saves you don't keep are replaced."
            )
        }
    }
}

#if DEBUG
    #Preview("Signed in") {
        RootView()
            .modelEnvironment(.preview())
            .frame(width: 1100, height: 720)
    }

    #Preview("Signed out") {
        RootView()
            .modelEnvironment(.preview(signedIn: false))
    }
#endif
