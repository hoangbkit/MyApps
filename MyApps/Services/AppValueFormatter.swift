import Foundation

enum AppValueFormatter {
    static func normalizedCurrencyCode(_ code: String) -> String {
        let value = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return value.count == 3 ? value : "USD"
    }

    static func currency(_ amount: Double, code: String, compact: Bool) -> String {
        let currencyCode = normalizedCurrencyCode(code)
        let absoluteAmount = abs(amount)

        let scaledValue: Double
        let suffix: String

        if compact, absoluteAmount >= 1_000_000 {
            scaledValue = amount / 1_000_000
            suffix = "M"
        } else if compact, absoluteAmount >= 1_000 {
            scaledValue = amount / 1_000
            suffix = "K"
        } else {
            scaledValue = amount
            suffix = ""
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        if currencyCode == "USD" {
            formatter.currencySymbol = "$"
        }
        formatter.maximumFractionDigits = suffix.isEmpty ? defaultFractionDigits(for: currencyCode) : 1
        formatter.minimumFractionDigits = 0

        let formatted = formatter.string(from: NSNumber(value: scaledValue))
            ?? "\(currencyCode) \(scaledValue.formatted(.number.precision(.fractionLength(0...1))))"

        return formatted + suffix
    }

    static func relativeDate(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))

        if seconds < 60 {
            return "now"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60))m"
        } else if seconds < 86_400 {
            return "\(Int(seconds / 3_600))h"
        } else if seconds < 604_800 {
            return "\(Int(seconds / 86_400))d"
        }

        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func parseAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal

        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }

        let fallback = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Double(fallback)
    }

    static func editableAmount(_ amount: Double?) -> String {
        guard let amount else { return "" }
        return amount.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func defaultFractionDigits(for currencyCode: String) -> Int {
        ["VND", "JPY", "KRW"].contains(currencyCode) ? 0 : 2
    }
}
