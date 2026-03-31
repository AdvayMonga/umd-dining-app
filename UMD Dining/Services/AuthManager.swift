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
    private let hasLaunchedKey = "com.umddining.hasLaunched"

    init() {
        // Keychain persists across app deletes — clear it on fresh install
        if !UserDefaults.standard.bool(forKey: hasLaunchedKey) {
            deleteFromKeychain(key: keychainKey)
            deleteFromKeychain(key: jwtKey)
            UserDefaults.standard.removeObject(forKey: guestKey)
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
        }
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

    /// Refreshes the JWT if it expires within 7 days. Call on app launch.
    func refreshTokenIfNeeded() async {
        guard let token = jwtToken, !isGuest else { return }
        // Decode the exp claim from the JWT payload (base64-encoded middle segment)
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payloadData = Data(base64URLEncoded: String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else { return }
        let expiryDate = Date(timeIntervalSince1970: exp)
        guard expiryDate.timeIntervalSinceNow < 7 * 24 * 60 * 60 else { return } // more than 7 days left
        // Refresh
        if let newToken = try? await DiningAPIService.shared.refreshToken() {
            jwtToken = newToken
            saveToKeychain(newToken, key: jwtKey)
        }
    }

    func checkAppleCredentialState() async {
        guard let userId, !isGuest else { return }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: userId)
            if state == .revoked || state == .notFound {
                signOut()
            }
        } catch {
            // Network error — don't sign out
        }
    }

    func signOut() {
        userId = nil
        jwtToken = nil
        isGuest = false
        deleteFromKeychain(key: keychainKey)
        deleteFromKeychain(key: jwtKey)
        UserDefaults.standard.removeObject(forKey: guestKey)
        FavoritesManager.shared.clearAll()
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

private extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        self.init(base64Encoded: base64)
    }
}
