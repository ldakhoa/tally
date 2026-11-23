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

    func testToolUseMessageRoundTrip() throws {
        let toolUse = ClaudeToolUse(id: "toolu_123", name: "add_transactions", input: ["items": [["name": "Rent", "amount": 3000]]])
        let assistantMsg = ClaudeMessage.assistant(blocks: [.text("Adding now"), .toolUse(toolUse)])
        let encoded = try JSONEncoder().encode(assistantMsg)
        let decoded = try JSONDecoder().decode(ClaudeMessage.self, from: encoded)
        XCTAssertEqual(decoded.role, .assistant)
        XCTAssertEqual(decoded.content, "Adding now")
        XCTAssertEqual(decoded.blocks?.count, 2)

        let resultMsg = ClaudeMessage.toolResults([(id: "toolu_123", content: "Saved Rent", isError: false)])
        let resData = try JSONEncoder().encode(resultMsg)
        let resJSON = String(decoding: resData, as: UTF8.self)
        XCTAssertTrue(resJSON.contains("tool_result"))
        XCTAssertTrue(resJSON.contains("toolu_123"))
    }
}
