import Foundation

public struct MicuSnapshot: Sendable {
    public let balance: Double
    public let last24Hours: Double
    public let today: Double
    public let total: Double
    public let symbol: String
    public let updatedAt: Date

    public static func startOfToday(now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.startOfDay(for: now)
    }

    public static func parse(
        user: [String: Any], status: [String: Any],
        recent: [[String: Any]], today: [String: Any], now: Date = Date()
    ) throws -> MicuSnapshot {
        func number(_ value: Any?) throws -> Double {
            let result: Double?
            if let string = value as? String { result = Double(string) }
            else { result = (value as? NSNumber)?.doubleValue }
            guard let result, result.isFinite else { throw MicuError.invalidData }
            return result
        }
        let units = try number(status["quota_per_unit"])
        guard units > 0 else { throw MicuError.invalidData }
        let rate: Double
        let symbol: String
        switch status["quota_display_type"] as? String {
        case "CNY":
            rate = try number(status["usd_exchange_rate"])
            symbol = "¥"
        case "USD":
            rate = 1
            symbol = "$"
        case "CUSTOM":
            rate = try number(status["custom_currency_exchange_rate"])
            guard let custom = status["custom_currency_symbol"] as? String, !custom.isEmpty else {
                throw MicuError.invalidData
            }
            symbol = custom
        default: throw MicuError.invalidData
        }
        guard rate > 0 else { throw MicuError.invalidData }
        let recentQuota = try recent.reduce(0.0) { try $0 + number($1["quota"]) }
        return try MicuSnapshot(
            balance: number(user["quota"]) / units * rate,
            last24Hours: recentQuota / units * rate,
            today: number(today["quota"]) / units * rate,
            total: number(user["used_quota"]) / units * rate,
            symbol: symbol, updatedAt: now
        )
    }

    public func formatted(_ value: Double) -> String {
        symbol + value.formatted(.number.precision(.fractionLength(2)))
    }
}

public enum MicuError: LocalizedError {
    case missingCredentials, unauthorized, invalidData, requestFailed

    public var errorDescription: String? {
        switch self {
        case .missingCredentials: "请在设置中通过 GitHub 授权或账号密码登录米醋"
        case .unauthorized: "米醋登录失败或已失效，请重新进行 GitHub 授权或检查账号密码"
        case .invalidData: "米醋返回的数据格式异常"
        case .requestFailed: "米醋请求失败，请稍后重试"
        }
    }
}
