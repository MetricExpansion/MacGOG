import Foundation
import SwiftyGOG
import Testing

@testable import MacGOG

@Suite struct ErrorMappingTests {
    @Test func cancellationIsSilent() {
        #expect(presentableError(CancellationError()) == nil)
        #expect(presentableError(URLError(.cancelled)) == nil)
    }

    @Test(arguments: [
        GOGError.authentication(.notSignedIn), .authentication(.invalidCredentialStore),
        .http(status: 401, host: "gog.com"),
    ])
    func endedSessionsOfferSignIn(_ error: GOGError) {
        #expect(presentableError(error)?.recoveries == [.signIn])
        #expect(requiresSignIn(error))
    }

    @Test func specialCases() {
        #expect(
            presentableError(GOGError.installation(.locked))?.message
                == "This game is being changed by another program."
        )
        #expect(presentableError(GOGError.installation(.anotherProduct))?.recoveries == [.chooseFolder])
        #expect(presentableError(GOGError.transport(host: "gog.com"))?.title == "Can't reach GOG")
        #expect(presentableError(GOGError.checksumMismatch("x"))?.recoveries == [.retry])
        #expect(presentableError(GOGError.unsupported(.noMatchingDepots))?.title == "Nothing to install")
        #expect(!requiresSignIn(GOGError.transport(host: "gog.com")))
    }

    @Test func otherErrorsGetAGenericTitle() {
        let error = presentableError(CocoaError(.fileReadNoPermission))
        #expect(error?.title == "Something went wrong")
        #expect(presentableError(AppError.wineNotConfigured)?.recoveries == [.openSettings])
    }
}
