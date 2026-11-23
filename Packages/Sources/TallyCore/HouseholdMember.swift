import Foundation

/// A person in the household (e.g., Me / Khoa and Partner / Vợ).
/// Each device holds its own `memberID` and display name so transactions automatically record
/// who spent or logged them across iCloud Household Sharing.
public struct HouseholdMember: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var avatarSymbol: String

    public init(id: String, name: String, avatarSymbol: String = "person.fill") {
        self.id = id
        self.name = name
        self.avatarSymbol = avatarSymbol
    }

    public static let defaultMeID = "member-primary"
    public static let defaultPartnerID = "member-partner"
}
