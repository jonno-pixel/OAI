import Foundation
import Security

enum Keychain {
    private static let service = "ClockChat.APIKey"
    static func read(_ provider: Provider) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func write(_ value: String, for provider: Provider) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: provider.rawValue]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw AppFailure.message("API-sleutel verwijderen mislukt (\(status)).")
            }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary,
                                  [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw AppFailure.message("API-sleutel opslaan mislukt (\(added)).") }
        } else if status != errSecSuccess {
            throw AppFailure.message("API-sleutel bijwerken mislukt (\(status)).")
        }
    }
}
