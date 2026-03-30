import AuthenticationServices
import SwiftUI

@MainActor
@Observable
class AuthManager {
    static let shared = AuthManager()

    var isSignedIn: Bool { userId != nil }
    private(set) var userId: String?
    private(set) var jwtToken: String?
    private(set) var isGuest: Bool = false

    private let keychainKey = "com.umddining.appleUserId"
    private let jwtKey = "com.umddining.jwtToken"
    private let guestKey = "com.umddining.isGuest"

    init() {
        userId = loadFromKeychain(key: keychainKey)
        jwtToken = loadFromKeychain(key: jwtKey)
        isGuest = UserDefaults.standard.bool(forKey: guestKey)
    }

    func handleSignIn(credential: ASAuthorizationAppleIDCredential) async {
        let userIdentifier = credential.user
        userId = userIdentifier
        isGuest = false
        saveToKeychain(userIdentifier, key: keychainKey)
        UserDefaults.standard.set(false, forKey: guestKey)

        if let token = try? await DiningAPIService.shared.registerAppleUser(userId: userIdentifier) {
            jwtToken = token
            saveToKeychain(token, key: jwtKey)
        }
    }

    func continueAsGuest() {
        let guestId = "guest_\(UUID().uuidString)"
        userId = guestId
        isGuest = true
        jwtToken = nil
        saveToKeychain(guestId, key: keychainKey)
        UserDefaults.standard.set(true, forKey: guestKey)
    }

    func signOut() {
        userId = nil
        jwtToken = nil
        isGuest = false
        deleteFromKeychain(key: keychainKey)
        deleteFromKeychain(key: jwtKey)
        UserDefaults.standard.removeObject(forKey: guestKey)
    }

    // MARK: - Keychain

    private func saveToKeychain(_ value: String, key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
