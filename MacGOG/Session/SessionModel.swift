import Foundation
import Observation
import SwiftyGOG

/// Whether the user is signed in to GOG, and the sign-in and sign-out actions.
@MainActor @Observable final class SessionModel {
    enum State: Equatable {
        case unknown
        case signedOut
        case signingIn
        case signedIn
        case failed(GOGError)
    }

    private(set) var state = State.unknown
    /// Set while the login sheet is open.
    var isPresentingLogin = false
    /// Called after every sign-in and sign-out, so other models can load or clear account data.
    var onChange: (@MainActor (Bool) -> Void)?

    private let auth: Authorization

    init(auth: Authorization, state: State = .unknown) {
        self.auth = auth
        self.state = state
    }

    var isSignedIn: Bool { state == .signedIn }

    /// Reads the Keychain to decide whether the user is signed in. An unreadable item signs out,
    /// so the user lands on sign-in rather than a stuck error.
    func restore() async {
        do {
            state = try await auth.hasStoredCredentials ? .signedIn : .signedOut
        } catch {
            try? await auth.logout()
            state = .signedOut
        }
        onChange?(state == .signedIn)
    }

    /// Completes sign-in with the `on_login_success` redirect the login web view intercepted.
    func completeLogin(redirect: URL) async {
        state = .signingIn
        do {
            let code = try Authorization.authorizationCode(from: redirect.absoluteString)
            _ = try await auth.login(code: code)
            state = .signedIn
            isPresentingLogin = false
            onChange?(true)
        } catch let error as GOGError {
            state = .failed(error)
        } catch {
            state = .failed(.authentication(.invalidTokenResponse))
        }
    }

    func cancelLogin() {
        isPresentingLogin = false
        if state == .signingIn {
            state = .signedOut
        }
    }

    func signOut() async {
        try? await auth.logout()
        state = .signedOut
        onChange?(false)
    }

    /// Signs out when `error` means the session ended. Returns whether it did.
    @discardableResult
    func handle(_ error: any Error) async -> Bool {
        guard requiresSignIn(error) else { return false }
        await signOut()
        return true
    }
}
