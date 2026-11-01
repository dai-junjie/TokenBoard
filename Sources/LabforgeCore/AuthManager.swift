import Foundation

public final class AuthManager: @unchecked Sendable {
    private let credentialsStore: LocalCredentialsStore
    private let client: LabforgeClientProtocol

    public init(
        credentialsStore: LocalCredentialsStore = LocalCredentialsStore(),
        client: LabforgeClientProtocol = LiveLabforgeClient()
    ) {
        self.credentialsStore = credentialsStore
        self.client = client
    }

    public func storedCredentials() throws -> Credentials? {
        try credentialsStore.loadCredentials()
    }

    public func saveCredentials(username: String, password: String) throws {
        try credentialsStore.saveCredentials(username: username, password: password)
    }

    public func clearCredentials() throws {
        try credentialsStore.deleteCredentials()
    }

    public func ensureAuthenticated() async throws {
        if try await client.validateSession() {
            return
        }
        guard let credentials = try storedCredentials() else {
            throw AppError.missingCredentials
        }
        try await client.login(credentials: credentials)
    }
}
