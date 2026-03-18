import AuthenticationServices
import SwiftUI

@MainActor
@Observable
class AuthManager {
    static let shared = AuthManager()

    var isSignedIn: Bool { userId != nil }
    private(set) var userId: String?
    private(set) var isGuest: Bool = false

    private let keychainKey = "com.umddining.appleUserId"
    private let guestKey = "com.umddining.isGuest"

    init() {
        userId = loadFromKeychain()
        isGuest = UserDefaults.standard.bool(forKey: guestKey)
    }

    func handleSignIn(credential: ASAuthorizationAppleIDCredential) async {
        let userIdentifier = credential.user
        userId = userIdentifier
        isGuest = false
        saveToKeychain(userIdentifier)
        UserDefaults.standard.set(false, forKey: guestKey)
        try? await DiningAPIService.shared.registerAppleUser(userId: userIdentifier)
    }

    func continueAsGuest() {
        let guestId = "guest_\(UUID().uuidString)"
        userId = guestId
        isGuest = true
        saveToKeychain(guestId)
        UserDefaults.standard.set(true, forKey: guestKey)
    }

    func signOut() {
        userId = nil
        isGuest = false
        deleteFromKeychain()
        UserDefaults.standard.removeObject(forKey: guestKey)
    }

    // MARK: - Keychain

    private func saveToKeychain(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}
