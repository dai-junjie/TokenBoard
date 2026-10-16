import Foundation

public protocol LabforgeClientProtocol: Sendable {
    func login(credentials: Credentials) async throws
    func fetchQuotaData() async throws -> Data
    func fetchModelsData() async throws -> Data
    func fetchTodayUsageData() async throws -> Data
    func fetchDailyRankingsData() async throws -> Data
    func validateSession() async throws -> Bool
}

public extension LabforgeClientProtocol {
    func fetchTodayUsageData() async throws -> Data {
        Data(#"{"success":true,"data":[]}"#.utf8)
    }

    func fetchDailyRankingsData() async throws -> Data {
        Data(#"{"success":true,"data":{"items":[]}}"#.utf8)
    }
}

public enum LabforgeEndpoints {
    public static let baseURL = URL(string: "https://labforge.cc")!
    public static let modelsDashboardURL = URL(string: "https://labforge.cc/dashboard/models")!
    public static let loginURL = URL(string: "https://labforge.cc/api/user/login?turnstile=")!
    public static let selfURL = URL(string: "https://labforge.cc/api/user/self")!
    public static let quotaURL = URL(string: "https://labforge.cc/api/labforge/quota/self")!
    public static let modelsURL = URL(string: "https://labforge.cc/api/labforge/models/status")!
    public static let usageURL = URL(string: "https://labforge.cc/api/data/self")!
    public static let rankingsURL = URL(string: "https://labforge.cc/api/labforge/rankings?period=daily")!
}

public final class LiveLabforgeClient: LabforgeClientProtocol, @unchecked Sendable {
    private let session: URLSession
    private var currentUserID: String?
    private let retryDelaysNanoseconds: [UInt64] = [
        2_000_000_000,
        5_000_000_000,
        10_000_000_000
    ]

    public init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    public func login(credentials: Credentials) async throws {
        var request = URLRequest(url: LabforgeEndpoints.loginURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "username": credentials.username,
                "password": credentials.password
            ]
        )

        let (data, response) = try await perform(request: request)
        try ensureSuccess(response)
        currentUserID = try parseUserID(from: data)
    }

    public func fetchQuotaData() async throws -> Data {
        try await fetch(url: LabforgeEndpoints.quotaURL)
    }

    public func fetchModelsData() async throws -> Data {
        try await fetch(url: LabforgeEndpoints.modelsURL)
    }

    public func fetchTodayUsageData() async throws -> Data {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        var components = URLComponents(url: LabforgeEndpoints.usageURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_timestamp", value: String(Int(startOfDay.timeIntervalSince1970))),
            URLQueryItem(name: "end_timestamp", value: String(Int(now.timeIntervalSince1970))),
            URLQueryItem(name: "time_granularity", value: "hour")
        ]
        return try await fetch(url: components.url!)
    }

    public func fetchDailyRankingsData() async throws -> Data {
        try await fetch(url: LabforgeEndpoints.rankingsURL)
    }

    public func validateSession() async throws -> Bool {
        let request = URLRequest(url: LabforgeEndpoints.selfURL)
        do {
            let (data, response) = try await perform(request: request)
            try ensureSuccess(response)
            currentUserID = try? parseUserID(from: data)
            return true
        } catch {
            return false
        }
    }

    private func fetch(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        if let currentUserID {
            request.setValue(currentUserID, forHTTPHeaderField: "New-Api-User")
        }
        let (data, response) = try await perform(request: request)
        try ensureSuccess(response)
        return data
    }

    private func perform(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            if let recovered = try await retryIfTransientNetworkFailure(request: request, error: error) {
                return recovered
            }
            throw mapNetworkError(error)
        }
    }

    private func retryIfTransientNetworkFailure(
        request: URLRequest,
        error: Error
    ) async throws -> (Data, URLResponse)? {
        guard isTransientNetworkError(error) else {
            return nil
        }

        for delay in retryDelaysNanoseconds {
            try? await Task.sleep(nanoseconds: delay)
            do {
                return try await session.data(for: request)
            } catch {
                guard isTransientNetworkError(error) else {
                    throw mapNetworkError(error)
                }
            }
        }

        return nil
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }

        switch urlError.code {
        case .cannotFindHost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .networkConnectionLost,
             .cannotConnectToHost,
             .timedOut:
            return true
        default:
            return false
        }
    }

    private func mapNetworkError(_ error: Error) -> Error {
        if let appError = error as? AppError {
            return appError
        }
        if let urlError = error as? URLError {
            return AppError.networkFailure(urlError.localizedDescription)
        }
        return error
    }

    private func parseUserID(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard
            let dictionary = object as? [String: Any],
            let data = dictionary["data"] as? [String: Any],
            let id = data["id"]
        else {
            throw AppError.parseFailure("missing user id in login response")
        }
        return String(describing: id)
    }

    private func ensureSuccess(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkFailure("missing HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw AppError.invalidCredentials
            }
            throw AppError.invalidResponse(httpResponse.statusCode)
        }
    }
}
