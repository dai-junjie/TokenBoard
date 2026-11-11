import Foundation

public struct TeamBuddySnapshot: Decodable, Sendable {
    public let quotas: Quotas
    public let overviews: [OverviewEntry]
    public let currency: Currency
    public let current_user: User?

    public struct User: Decodable, Sendable {
        public let id: Int
        public let username: String
        public let display_name: String?
        public var name: String { display_name.flatMap { $0.isEmpty ? nil : $0 } ?? username }
    }

    public struct Quotas: Decodable, Sendable {
        public let teams: [Team]
    }

    public struct Team: Decodable, Identifiable, Sendable {
        public let team_id: Int
        public let team_name: String
        public let member_status: String
        public let team_status: String
        public let limits: [PeriodLimit]?
        public let consumed_quota: Int?
        // Older responses used one quota window instead of per-period limits.
        public let base_quota: Int?
        public let temporary_quota: Int?
        public let base_used_quota: Int?
        public let remaining_quota: Int?
        public let reserved_quota: Int
        public let team_borne_quota: Int
        public let period_end_at: TimeInterval
        public var id: Int { team_id }
        public var isActive: Bool { member_status == "active" && team_status == "active" }
        public var nextResetAt: TimeInterval? {
            if let limits {
                return limits.filter { $0.effective_mode == "limited" }
                    .map(\.period_end_at).filter { $0 > 0 }.min()
            }
            return period_end_at > 0 ? period_end_at : nil
        }
        public var temporaryRemaining: Int? {
            // Each period repeats the same temporary grant; count it once.
            limits?.map(\.temporary_remaining).max()
        }
    }

    public struct PeriodLimit: Decodable, Identifiable, Sendable {
        public let scope: String
        public let period: String
        public let effective_mode: String
        public let effective_quota: Int
        public let shared_used: Int
        public let temporary_remaining: Int
        public let remaining_quota: Int?
        public let period_end_at: TimeInterval
        public var id: String { "\(scope):\(period)" }
        public var periodName: String {
            switch period {
            case "day": return "日"
            case "week": return "周"
            case "month": return "月"
            default: return period
            }
        }
    }

    public struct OverviewEntry: Decodable, Sendable {
        public let team_id: Int
        public let data: Overview?
    }

    public struct Overview: Decodable, Sendable {
        public let daily_limit: DailyLimit?
        public let member_usage: [MemberUsage]?

        public var rankings: [RankedMember] {
            rankedMembers.prefix(5).map { $0 }
        }

        public func rank(for userID: Int) -> RankedMember? {
            rankedMembers.first { $0.member.user_id == userID }
        }

        private var rankedMembers: [RankedMember] {
            let members = (member_usage ?? []).sorted {
                $0.consumed_quota == $1.consumed_quota
                    ? $0.user_id < $1.user_id : $0.consumed_quota > $1.consumed_quota
            }
            return members.map { member in
                RankedMember(rank: members.firstIndex { $0.consumed_quota == member.consumed_quota }! + 1,
                             member: member)
            }
        }
    }

    public struct MemberUsage: Decodable, Sendable {
        public let user_id: Int
        public let username: String
        public let display_name: String?
        public let consumed_quota: Int
        public var name: String { display_name.flatMap { $0.isEmpty ? nil : $0 } ?? username }
    }

    public struct RankedMember: Identifiable, Sendable {
        public let rank: Int
        public let member: MemberUsage
        public var id: Int { member.user_id }
    }

    public struct DailyLimit: Decodable, Sendable {
        public let quota: Int?
        public let spent: Int
        public var limit: Int? { quota.flatMap { $0 < 0 ? nil : $0 } }
        public var remaining: Int? { limit.map { max(0, $0 - spent) } }
    }

    public struct Currency: Decodable, Sendable {
        public let quota_per_unit: Double
        public let quota_display_type: String
        public let usd_exchange_rate: Double?
        public let custom_currency_symbol: String?
        public let custom_currency_exchange_rate: Double?
    }

    public static func parse(_ json: String) throws -> TeamBuddySnapshot {
        let data = Data(json.utf8)
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? String {
            if error == "login_required" { throw AppError.invalidCredentials }
            throw AppError.networkFailure(object["message"] as? String ?? "TeamBuddy 数据读取失败")
        }
        let snapshot = try JSONDecoder().decode(Self.self, from: data)
        guard snapshot.currency.quota_per_unit.isFinite, snapshot.currency.quota_per_unit > 0 else {
            throw AppError.parseFailure("TeamBuddy 额度换算单位无效")
        }
        return snapshot
    }

    public func formatted(_ quota: Int) -> String {
        let value = Double(quota) / currency.quota_per_unit
        switch currency.quota_display_type {
        case "TOKENS": return quota.formatted() + " Token"
        case "CNY": return "¥" + (value * (currency.usd_exchange_rate ?? 1)).formatted(.number.precision(.fractionLength(2)))
        case "CUSTOM": return (currency.custom_currency_symbol ?? "¤") + (value * (currency.custom_currency_exchange_rate ?? 1)).formatted(.number.precision(.fractionLength(2)))
        default: return "$" + value.formatted(.number.precision(.fractionLength(2)))
        }
    }
}
