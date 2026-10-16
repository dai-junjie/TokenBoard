import Foundation

public actor MicuClient {
    public static let dashboardURL = URL(string: "https://www.micuapi.ai/dashboard/overview")!
    private let session: URLSession
    private var userID: Int?
    private var webSessionCookies: [HTTPCookie] = []

    public init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        self.session = session ?? URLSession(configuration: configuration)
    }

    public func resetSession() {
        userID = nil
        webSessionCookies = []
        session.configuration.httpCookieStorage?.cookies?.forEach {
            session.configuration.httpCookieStorage?.deleteCookie($0)
        }
    }

    public func useWebSession(_ webSession: MicuWebSession) throws {
        let cookies = try webSession.validatedCookies()
        resetSession()
        for cookie in cookies { session.configuration.httpCookieStorage?.setCookie(cookie) }
        webSessionCookies = cookies
        userID = webSession.userID
    }

    public func refresh(credentials: Credentials?, now: Date = Date()) async throws -> MicuSnapshot {
        if userID == nil {
            guard let credentials else { throw MicuError.missingCredentials }
            try await login(credentials)
        }
        do { return try await fetchSnapshot(now: now) }
        catch MicuError.unauthorized {
            guard let credentials else { throw MicuError.unauthorized }
            try await login(credentials)
            return try await fetchSnapshot(now: now)
        }
    }

    private func login(_ credentials: Credentials) async throws {
        userID = nil
        let data = try await request(path: "/api/user/login", body: [
            "username": credentials.username, "password": credentials.password
        ])
        guard let user = data as? [String: Any], let id = user["id"] as? Int else {
            throw MicuError.unauthorized
        }
        userID = id
    }

    private func fetchSnapshot(now: Date) async throws -> MicuSnapshot {
        guard let user = try await request(path: "/api/user/self") as? [String: Any],
              let status = try await request(path: "/api/status") as? [String: Any] else {
            throw MicuError.invalidData
        }
        func parameters(since: Date) -> [URLQueryItem] {
            [URLQueryItem(name: "start_timestamp", value: String(Int(since.timeIntervalSince1970))),
             URLQueryItem(name: "end_timestamp", value: String(Int(now.timeIntervalSince1970)))]
        }
        // Match the overview's rolling window and hourly aggregate endpoint.
        guard let recent = try await request(path: "/api/data/self", query:
            parameters(since: now.addingTimeInterval(-86400)) + [URLQueryItem(name: "default_time", value: "hour")]
        ) as? [[String: Any]],
              let today = try await request(path: "/api/log/self/stat", query:
            parameters(since: MicuSnapshot.startOfToday(now: now)) + [URLQueryItem(name: "type", value: "2")]
        ) as? [String: Any] else { throw MicuError.invalidData }
        return try MicuSnapshot.parse(user: user, status: status, recent: recent, today: today, now: now)
    }

    private func request(path: String, query: [URLQueryItem] = [], body: [String: String]? = nil) async throws -> Any {
        var components = URLComponents(string: "https://www.micuapi.ai")!
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        if !webSessionCookies.isEmpty {
            let applicable = webSessionCookies.filter {
                path.hasPrefix($0.path) && ($0.expiresDate.map { $0 > Date() } ?? true)
            }
            for (name, value) in HTTPCookie.requestHeaderFields(with: applicable) {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        if let userID { request.setValue(String(userID), forHTTPHeaderField: "New-Api-User") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw MicuError.requestFailed }
        if response.statusCode == 401 || response.statusCode == 403 { throw MicuError.unauthorized }
        guard (200..<300).contains(response.statusCode) else { throw MicuError.requestFailed }
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = envelope["success"] as? Bool else { throw MicuError.invalidData }
        guard success else {
            // Do not expose server response bodies or credentials in UI/logs.
            throw path == "/api/user/login" || path == "/api/user/self" ? MicuError.unauthorized : MicuError.requestFailed
        }
        guard let payload = envelope["data"] else { throw MicuError.invalidData }
        return payload
    }
}
