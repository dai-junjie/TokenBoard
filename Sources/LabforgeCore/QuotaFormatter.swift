import Foundation

public enum QuotaFormatter {
    public static let quotaPerPoint = 500_000.0

    public static func pointsString(_ quota: Int) -> String {
        let points = Double(quota) / quotaPerPoint
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = points >= 100 ? 0 : 2
        formatter.numberStyle = .decimal
        let value = formatter.string(from: NSNumber(value: points)) ?? String(format: "%.2f", points)
        return "\(value) 积分"
    }
}
