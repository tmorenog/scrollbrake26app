// Fake FamilyControls: selection (Codable, Equatable, as documented) and an
// AuthorizationCenter whose status tests can change.
import Combine
import Foundation
import ManagedSettings

public struct FamilyActivitySelection: Codable, Equatable {
    public var applicationTokens: Set<ApplicationToken> = []
    public var categoryTokens: Set<ActivityCategoryToken> = []
    public var webDomainTokens: Set<WebDomainToken> = []
    public init() {}
}

public enum FamilyControlsMember: Equatable { case child, individual }

public enum AuthorizationStatus: Equatable { case notDetermined, denied, approved }

public enum FamilyControlsError: Error {
    case invalidAccountType, authorizationConflict, authorizationCanceled, invalidArgument
    case unavailable, restricted, networkError, authenticationMethodUnavailable, unauthorized
}

public final class AuthorizationCenter {
    public static let shared = AuthorizationCenter()

    @Published public var authorizationStatus: AuthorizationStatus = .notDetermined

    /// Test hooks.
    public var nextError: Error?
    public private(set) var requestedMembers: [FamilyControlsMember] = []

    public func requestAuthorization(for member: FamilyControlsMember) async throws {
        requestedMembers.append(member)
        if let error = nextError {
            nextError = nil
            throw error
        }
        authorizationStatus = .approved
    }

    public func reset() {
        authorizationStatus = .notDetermined
        nextError = nil
        requestedMembers = []
    }
}
