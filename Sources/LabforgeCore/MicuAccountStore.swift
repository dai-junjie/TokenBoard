import Foundation
import Security

public struct MicuAccount: Codable, Identifiable, Sendable {
    public enum Login: Codable, Sendable {
        case password(Credentials)
        case web(MicuWebSession)
    }

    public let id: UUID
    public var name: String
    public let login: Login

    public init(id: UUID = UUID(), name: String, login: Login) {
        self.id = id
        self.name = name
        self.login = login
    }

    public var loginDescription: String {
        switch login {
        case .password(let credentials): "账号密码 · \(credentials.username)"
        case .web(let session): "GitHub · ID \(session.userID)"
        }
    }
}

public struct MicuAccountStore: Sendable {
    private let service: String

    public init(service: String = "cc.labforge.menubar.micu") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "accounts"]
    }

    // nil means not migrated; an empty list means the user removed all accounts.
    public func load() throws -> [MicuAccount]? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return try JSONDecoder().decode([MicuAccount].self, from: data)
    }

    public func save(_ accounts: [MicuAccount]) throws {
        let data = try JSONEncoder().encode(accounts)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public func loadOrMigrateLegacy() throws -> [MicuAccount] {
        if let accounts = try load() { return accounts }
        let accounts: [MicuAccount]
        if UserDefaults.standard.bool(forKey: "micuUsesWebLogin") {
            if let session = try MicuWebSessionStore().load() {
                accounts = [MicuAccount(name: "GitHub 账号", login: .web(session))]
            } else { accounts = [] }
        } else if let credentials = try MicuCredentialsStore().load() {
            accounts = [MicuAccount(name: credentials.username, login: .password(credentials))]
        } else {
            accounts = []
        }
        try save(accounts)
        return accounts
    }
}
