import Foundation
import Security

public struct MicuWebSession: Codable, Sendable {
    public let userID: Int
    private let cookies: [Cookie]

    private struct Cookie: Codable, Sendable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let secure: Bool
        let expires: Date?
    }

    public init(userID: Int, cookies: [HTTPCookie]) {
        self.userID = userID
        self.cookies = cookies.map {
            Cookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path,
                   secure: $0.isSecure, expires: $0.expiresDate)
        }
    }

    public func validatedCookies() throws -> [HTTPCookie] {
        guard userID > 0, !cookies.isEmpty else { throw MicuError.unauthorized }
        return try cookies.map { cookie in
            guard Self.isMicuHost(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))),
                  cookie.expires.map({ $0 > Date() }) ?? true else { throw MicuError.unauthorized }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name, .value: cookie.value, .domain: cookie.domain,
                .path: cookie.path, .secure: cookie.secure ? "TRUE" : "FALSE"
            ]
            if let expires = cookie.expires { properties[.expires] = expires }
            guard let result = HTTPCookie(properties: properties) else { throw MicuError.invalidData }
            return result
        }
    }

    public static func isMicuHost(_ host: String) -> Bool {
        ["micuapi.ai", "www.micuapi.ai"].contains(host.lowercased())
    }
}

public struct MicuWebSessionStore: Sendable {
    public init() {}

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "cc.labforge.menubar.micu",
         kSecAttrAccount as String: "web-session"]
    }

    public func load() throws -> MicuWebSession? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return try JSONDecoder().decode(MicuWebSession.self, from: data)
    }

    public func save(_ session: MicuWebSession) throws {
        _ = try session.validatedCookies()
        let data = try JSONEncoder().encode(session)
        let attributes = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
