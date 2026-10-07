import Foundation

/// Shared display formatting. Money follows the currency set in Settings,
/// always with two decimals.
enum Fmt {
    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: AppSettings.currencyCode).precision(.fractionLength(2)))
    }

    /// "7h 30m" — the primary way hours are shown.
    static func hours(_ value: Double) -> String {
        let totalMinutes = Int((value * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// "7.5 h" — used where a compact numeric reads better.
    static func decimalHours(_ value: Double) -> String {
        String(format: "%.2f h", value)
    }

    /// "2:34:07" — a running clock, for a shift in progress.
    static func stopwatch(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dayHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }

    /// "Wed, 5 Aug" — a day inside a month that's already named above it.
    static func dayInMonth(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "1 shift" / "3 shifts".
    static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    static func monthTitle(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    static func shortMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated))
    }

    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}
