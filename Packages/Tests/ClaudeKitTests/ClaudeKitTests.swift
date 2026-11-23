import ClaudeKit
import TallyCore
import XCTest

final class ClaudeKitTests: XCTestCase {
    func testAPIKeyHintAndWorkspaceValidation() {
        XCTAssertEqual(APIKeyDetails.hint(for: "sk-ant-api03-abcdef1234"), "sk-ant-…1234")
        XCTAssertTrue(ClaudeClient.looksLikeWorkspaceID("wrkspc_01AbCdEf"))
        XCTAssertFalse(ClaudeClient.looksLikeWorkspaceID("sk-ant-123"))
    }

    func testAPIProblemClassification() {
        XCTAssertEqual(APIProblem.classify(status: 401, type: "authentication_error", message: "bad key"), .keyRejected)
        XCTAssertEqual(APIProblem.classify(status: 400, type: "invalid_request_error", message: "Your credit balance is too low"), .outOfCredit)
        XCTAssertEqual(APIProblem.classify(status: 400, type: "invalid_request_error", message: "Key is not scoped to a workspace"), .workspaceRequired)
    }
}
