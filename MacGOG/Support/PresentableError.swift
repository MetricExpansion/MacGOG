import Foundation
import SwiftyGOG

/// An error as the UI shows it: a title, a message, and the actions that can recover from it.
nonisolated struct PresentableError: Identifiable, Sendable {
    enum Recovery: Hashable, Sendable {
        case signIn
        case retry
        case chooseFolder
        case openSettings
    }

    let id = UUID()
    let title: String
    let message: String
    let recoveries: [Recovery]

    init(title: String, message: String, recoveries: [Recovery] = []) {
        self.title = title
        self.message = message
        self.recoveries = recoveries
    }
}

/// Failures that come from the app rather than from SwiftyGOG.
nonisolated enum AppError: Error, Hashable, Sendable {
    case keychain(OSStatus)
    case notEnoughSpace(needed: Int64, available: Int64)
    case wineNotConfigured
    case crossOverNotInstalled
    case folderMissing(String)
    case gameIsBusy
    case notInstalled

    var presentable: PresentableError {
        switch self {
        case .keychain(let status):
            PresentableError(
                title: "Keychain error",
                message: "MacGOG couldn't use its Keychain item (error \(status)). Sign in again.",
                recoveries: [.signIn]
            )
        case .notEnoughSpace(let needed, let available):
            PresentableError(
                title: "Not enough disk space",
                message:
                    "This needs \(needed.formattedBytes), but only \(available.formattedBytes) is free. "
                    + "Free some space or choose another folder.",
                recoveries: [.chooseFolder]
            )
        case .wineNotConfigured:
            PresentableError(
                title: "Wine isn't set up",
                message: "Windows games need Wine or a compatible wrapper. Choose one in Settings.",
                recoveries: [.openSettings]
            )
        case .crossOverNotInstalled:
            PresentableError(
                title: "CrossOver isn't installed",
                message: "Install CrossOver from codeweavers.com, or choose another Wine in Settings.",
                recoveries: [.openSettings]
            )
        case .folderMissing(let path):
            PresentableError(
                title: "Game folder is missing",
                message: "Nothing was found at \(path). Locate the folder or remove the game from MacGOG.",
                recoveries: [.chooseFolder]
            )
        case .gameIsBusy:
            PresentableError(
                title: "Game is busy",
                message: "Wait for the current download or the running game to finish, then try again."
            )
        case .notInstalled:
            PresentableError(title: "Not installed", message: "This game isn't installed.")
        }
    }
}

/// Maps any error to what the UI shows, or `nil` when the user cancelled.
nonisolated func presentableError(_ error: any Error) -> PresentableError? {
    if error is CancellationError {
        return nil
    }
    if let error = error as? URLError, error.code == .cancelled {
        return nil
    }
    if let error = error as? AppError {
        return error.presentable
    }
    if let error = error as? CocoaError, error.code == .fileWriteOutOfSpace {
        return PresentableError(
            title: "Disk full",
            message: "The disk ran out of space. Free some space, then resume.",
            recoveries: [.retry]
        )
    }
    guard let error = error as? GOGError else {
        return PresentableError(
            title: "Something went wrong",
            message: error.localizedDescription,
            recoveries: [.retry]
        )
    }
    return presentable(error)
}

private nonisolated func presentable(_ error: GOGError) -> PresentableError {
    switch error {
    case .authentication(.notSignedIn), .authentication(.invalidCredentialStore), .http(status: 401, _):
        PresentableError(
            title: "Sign in to GOG",
            message: "Your GOG session has ended. Sign in again to continue.",
            recoveries: [.signIn]
        )
    case .authentication(.loginDenied):
        PresentableError(
            title: "Sign-in was cancelled",
            message: "GOG didn't authorize this sign-in. Try again."
        )
    case .authentication:
        PresentableError(title: "Couldn't sign in", message: error.description, recoveries: [.signIn])
    case .transport:
        PresentableError(
            title: "Can't reach GOG",
            message: "Check your internet connection, then try again.",
            recoveries: [.retry]
        )
    case .http(let status, _) where status >= 500:
        PresentableError(
            title: "GOG is having trouble",
            message: "GOG's servers returned an error (\(status)). Try again later.",
            recoveries: [.retry]
        )
    case .installation(.locked):
        PresentableError(
            title: "Game is busy",
            message: "This game is being changed by another program.",
            recoveries: [.retry]
        )
    case .installation(.anotherProduct):
        PresentableError(
            title: "Folder holds another game",
            message: "That folder already contains a different game. Choose another folder.",
            recoveries: [.chooseFolder]
        )
    case .installation(.missingMetadata), .installation(.invalidPlan):
        PresentableError(
            title: "Not a GOG game folder",
            message: "MacGOG couldn't find GOG installation data in that folder.",
            recoveries: [.chooseFolder]
        )
    case .unsupported(.buildUnavailable):
        PresentableError(
            title: "Build unavailable",
            message: "The selected build or branch is no longer available, or it needs a password."
        )
    case .unsupported(.noMatchingDepots):
        PresentableError(
            title: "Nothing to install",
            message: "This game has no files for the chosen language and DLC. Choose another language."
        )
    case .cloudSaves(.conflict):
        PresentableError(
            title: "Cloud save conflict",
            message: "Saves changed both on this Mac and in the cloud. Choose which to keep."
        )
    case .crossOver(let problem):
        PresentableError(title: "CrossOver problem", message: problem.description, recoveries: [.retry])
    case .checksumMismatch:
        PresentableError(
            title: "Download was damaged",
            message: "Some data didn't match its checksum. Try again; verified data is kept.",
            recoveries: [.retry]
        )
    default:
        PresentableError(title: "GOG error", message: error.description, recoveries: [.retry])
    }
}

/// True when an error means the user has to sign in again.
nonisolated func requiresSignIn(_ error: any Error) -> Bool {
    switch error as? GOGError {
    case .authentication(.notSignedIn), .authentication(.invalidCredentialStore), .http(status: 401, _): true
    default: false
    }
}
