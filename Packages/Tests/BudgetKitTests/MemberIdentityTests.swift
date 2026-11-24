import BudgetKit
import XCTest

final class MemberIdentityTests: XCTestCase {
    private let mac = "9E6595E6-FC66-45FB-81D5-B7E2135A132B"
    private let phone = "E616A422-11E6-43E7-80F6-853C270DCD40"

    func testTwoDevicesOfOnePersonAgreeOnTheSameID() {
        let records = [(memberID: mac, memberName: "Khoa"), (memberID: phone, memberName: "khoa ")]
        let onMac = MemberIdentity.canonicalID(currentID: mac, name: "Khoa", records: records)
        let onPhone = MemberIdentity.canonicalID(currentID: phone, name: "Khoa", records: records)
        XCTAssertEqual(onMac, mac)
        XCTAssertEqual(onPhone, mac)
    }

    func testOtherNamesAndSyntheticIDsAreIgnored() {
        let records = [
            (memberID: "00000000-AAAA", memberName: "Linh"),
            (memberID: "member-khoa", memberName: "Khoa"),
            (memberID: "member-partner", memberName: "Khoa"),
        ]
        XCTAssertEqual(MemberIdentity.canonicalID(currentID: phone, name: "Khoa", records: records), phone)
    }

    func testEmptyNameKeepsTheCurrentID() {
        let records = [(memberID: mac, memberName: "")]
        XCTAssertEqual(MemberIdentity.canonicalID(currentID: phone, name: "  ", records: records), phone)
    }
}
