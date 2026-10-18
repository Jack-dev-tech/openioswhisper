import Foundation
import Security

/// Stores the Groq API key in the app's own Keychain. The keyboard never reads it:
/// all network calls happen in the app.
enum Keychain {
    private static let service = "com.jackmatsuzaki.OpenWhisper"
    private static let groqAccount = "groq-api-key"

    static var groqAPIKey: String? {
        get { read(account: groqAccount) }
        set {
            if let newValue, !newValue.isEmpty {
                save(newValue, account: groqAccount)
            } else {
                delete(account: groqAccount)
            }
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        // After first unlock, so dictation keeps working in the background while the phone is locked.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery(account: account)
            query.merge(attributes) { $1 }
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
