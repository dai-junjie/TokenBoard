import Foundation
import LabforgeCore

@main
struct MicuVerify {
    static func main() async throws {
        try testCurrencyConversionAndSeparateUsageWindows()
        testMissingDataIsNotDisplayedAsZero()
        testMalformedUsageIsRejected()
        testTodayStartsAtShanghaiMidnight()
        try await testClientRequestsAndAuthenticationFailure()
        try await testWebSessionDoesNotUsePasswordLogin()
        print("MicuVerify: PASS")
    }
    static func testCurrencyConversionAndSeparateUsageWindows() throws {
        let snapshot = try MicuSnapshot.parse(
            user: ["quota": 64_990_000, "used_quota": 610_010_000],
            status: ["quota_per_unit": 500_000, "quota_display_type": "CNY", "usd_exchange_rate": 1],
            recent: [["quota": 5_000_000], ["quota": 2_865_000]],
            today: ["quota": 1_500_000]
        )
        checkEqual(snapshot.balance, 129.98, accuracy: 0.00001)
        checkEqual(snapshot.last24Hours, 15.73, accuracy: 0.00001)
        checkEqual(snapshot.today, 3, accuracy: 0.00001)
        checkEqual(snapshot.total, 1220.02, accuracy: 0.00001)
        checkEqual(snapshot.symbol, "¥")
    }

    static func testMissingDataIsNotDisplayedAsZero() {
        checkThrows(try MicuSnapshot.parse(user: [:], status: [:], recent: [], today: [:]))
    }

    static func testMalformedUsageIsRejected() {
        checkThrows(try MicuSnapshot.parse(
            user: ["quota": 0, "used_quota": 0],
            status: ["quota_per_unit": 500_000, "quota_display_type": "CNY", "usd_exchange_rate": 1],
            recent: [["quota": "bad"]], today: ["quota": 0]
        ))
    }

    static func testTodayStartsAtShanghaiMidnight() {
        let now = ISO8601DateFormatter().date(from: "2026-10-17T01:30:00Z")!
        checkEqual(MicuSnapshot.startOfToday(now: now), ISO8601DateFormatter().date(from: "2026-10-16T16:00:00Z")!)
    }

    static func testClientRequestsAndAuthenticationFailure() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MicuMockProtocol.self]
        let client = MicuClient(session: URLSession(configuration: configuration))
        let now = ISO8601DateFormatter().date(from: "2026-10-17T01:30:00Z")!
        let snapshot = try await client.refresh(credentials: Credentials(username: "test", password: "test"), now: now)
        checkEqual(snapshot.today, 3, accuracy: 0.00001)
        checkEqual(snapshot.last24Hours, 15.73, accuracy: 0.00001)
        await client.resetSession()
        do {
            _ = try await client.refresh(credentials: Credentials(username: "invalid", password: "test"))
            fatalError("Invalid login must fail")
        } catch MicuError.unauthorized {}
    }

    static func testWebSessionDoesNotUsePasswordLogin() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MicuMockProtocol.self]
        let client = MicuClient(session: URLSession(configuration: configuration))
        let cookie = HTTPCookie(properties: [.domain: "www.micuapi.ai", .path: "/", .name: "session", .value: "test-session", .secure: "TRUE"])!
        let saved = MicuWebSession(userID: 789, cookies: [cookie])
        let restored = try JSONDecoder().decode(MicuWebSession.self, from: JSONEncoder().encode(saved))
        try await client.useWebSession(restored)
        let now = ISO8601DateFormatter().date(from: "2026-10-17T01:30:00Z")!
        let snapshot = try await client.refresh(credentials: nil, now: now)
        checkEqual(snapshot.balance, 129.98, accuracy: 0.00001)
        try await client.useWebSession(MicuWebSession(userID: 999, cookies: [cookie]))
        do {
            _ = try await client.refresh(credentials: nil, now: now)
            fatalError("Expired web session must require reauthorization")
        } catch MicuError.unauthorized {}
        await client.resetSession()
        do {
            _ = try await client.refresh(credentials: nil, now: now)
            fatalError("Missing web session must require sign-in")
        } catch MicuError.missingCredentials {}
        let foreignCookie = HTTPCookie(properties: [.domain: "github.com", .path: "/", .name: "session", .value: "foreign"])!
        checkThrows(try MicuWebSession(userID: 123, cookies: [foreignCookie]).validatedCookies())
        checkThrows(try MicuWebSession(userID: 0, cookies: [cookie]).validatedCookies())
        precondition(!MicuWebSession.isMicuHost("micuapi.ai.evil.example"))
    }
    static func checkEqual(_ lhs: Double, _ rhs: Double, accuracy: Double) {
        precondition(abs(lhs - rhs) < accuracy)
    }
    static func checkEqual<T: Equatable>(_ lhs: T, _ rhs: T) {
        precondition(lhs == rhs)
    }
    static func checkThrows<T>(_ expression: @autoclosure () throws -> T) {
        do { _ = try expression(); fatalError("Expected an error") } catch {}
    }
}

final class MicuMockProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        precondition(url.host == "www.micuapi.ai")
        var payload: Any
        var success = true
        switch url.path {
        case "/api/user/login":
            precondition(request.httpMethod == "POST")
            var bodyData = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    guard count > 0 else { break }
                    bodyData.append(contentsOf: bytes.prefix(count))
                }
            }
            let body = try! JSONSerialization.jsonObject(with: bodyData) as! [String: String]
            success = body["username"] != "invalid"
            payload = ["id": 123]
        case "/api/user/self":
            let userID = request.value(forHTTPHeaderField: "New-Api-User")
            precondition(["123", "789", "999"].contains(userID))
            if userID == "789" {
                precondition(request.value(forHTTPHeaderField: "Cookie")?.contains("session=test-session") == true)
            }
            success = userID != "999"
            payload = ["quota": 64_990_000, "used_quota": 610_010_000]
        case "/api/status":
            payload = ["quota_per_unit": 500_000, "quota_display_type": "CNY", "usd_exchange_rate": 1]
        case "/api/data/self", "/api/log/self/stat":
            precondition(["123", "789"].contains(request.value(forHTTPHeaderField: "New-Api-User")))
            let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
            let now = ISO8601DateFormatter().date(from: "2026-10-17T01:30:00Z")!
            let isRecent = url.path == "/api/data/self"
            let start = isRecent ? now.addingTimeInterval(-86400) : MicuSnapshot.startOfToday(now: now)
            precondition(query["start_timestamp"] == String(Int(start.timeIntervalSince1970)))
            precondition(query["end_timestamp"] == String(Int(now.timeIntervalSince1970)))
            if isRecent {
                precondition(query["default_time"] == "hour")
                payload = [["quota": 7_865_000]]
            } else {
                precondition(query["type"] == "2")
                payload = ["quota": 1_500_000]
            }
        default: fatalError("Unexpected endpoint")
        }
        let data = try! JSONSerialization.data(withJSONObject: ["success": success, "data": payload])
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
