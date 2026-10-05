//
//  ParentPasscode.swift
//  BreakScroll
//
//  While rules are configured on the child's iPhone (until CloudKit sync in
//  Phase 10), editing them there needs a parent passcode. Apple offers no way
//  to re-authenticate the parent on the child's device after authorization,
//  so this is app-level protection: a salted SHA-256 in the Keychain, never
//  the passcode itself. It's weaker than CloudKit permissions and is replaced
//  by them once rules are edited from the parent's phone.
//

import CryptoKit
import Foundation
import Security

enum ParentPasscode {
    private static let service = "com.breakscroll.parent-passcode"
    private static let account = "parent"

    static var isSet: Bool {
        load() != nil
    }

    static func set(_ passcode: String) -> Bool {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { return false }
        let stored = salt + hash(passcode, salt: salt)
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = stored
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func verify(_ passcode: String) -> Bool {
        guard let stored = load(), stored.count > 16 else { return false }
        let salt = stored.prefix(16)
        return hash(passcode, salt: Data(salt)) == stored.dropFirst(16)
    }

    static func remove() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func load() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func hash(_ passcode: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(passcode.utf8)))
    }
}
