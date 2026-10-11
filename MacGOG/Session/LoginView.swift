import AppKit
import SwiftUI
import SwiftyGOG
import WebKit

/// GOG's sign-in page in a web view. The `on_login_success` redirect is intercepted and never loaded.
struct LoginView: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to GOG")
                    .font(.headline)
                Spacer()
                if session.state == .signingIn {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Cancel") { session.cancelLogin() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            if case .failed(let error) = session.state, let presentable = presentableError(error) {
                Label(presentable.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            Divider()
            if let url = try? Authorization.loginURL() {
                LoginWebView(url: url) { redirect in
                    Task { await session.completeLogin(redirect: redirect) }
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 640, idealHeight: 720)
    }
}

private struct LoginWebView: NSViewRepresentable {
    let url: URL
    let onRedirect: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onRedirect: onRedirect) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // GOG's web cookies shouldn't outlive the sheet.
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onRedirect = onRedirect
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onRedirect: (URL) -> Void

        init(onRedirect: @escaping (URL) -> Void) {
            self.onRedirect = onRedirect
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = action.request.url, Self.isLoginRedirect(url) else { return .allow }
            onRedirect(url)
            return .cancel
        }

        static func isLoginRedirect(_ url: URL) -> Bool {
            url.host()?.lowercased() == "embed.gog.com" && url.path() == "/on_login_success"
        }
    }
}

/// The screen shown while signed out.
struct SignInView: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Welcome to MacGOG")
                .font(.largeTitle.bold())
            Text("Sign in with your GOG account to see your library.")
                .foregroundStyle(.secondary)
            Button("Sign In…") { session.isPresentingLogin = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            Text("Installed games stay on disk when you sign out.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
    #Preview("Sign in") {
        SignInView()
            .modelEnvironment(.preview(signedIn: false))
            .frame(width: 700, height: 500)
    }

    #Preview("Login sheet") {
        LoginView()
            .modelEnvironment(.preview(signedIn: false))
    }
#endif
