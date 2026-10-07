import Foundation

/// Settings that apply to the whole app rather than to one job.
enum AppSettings {
    static let currencyKey = "currencyCode"

    /// A curated list rather than all ~150 ISO codes, which would be a picker
    /// nobody scrolls to the end of. Anything missing can be added here.
    static let currencies = [
        "EUR", "USD", "GBP", "CHF", "SEK", "NOK", "DKK",
        "PLN", "CZK", "HUF", "RON", "BGN", "RSD",
        "CAD", "AUD", "NZD", "JPY",
    ]

    /// The phone's own currency when it is one of the above, euros otherwise.
    static var deviceDefault: String {
        let code = Locale.current.currency?.identifier ?? "EUR"
        return currencies.contains(code) ? code : "EUR"
    }

    /// What amounts are shown in. Purely a display setting: changing it does
    /// not convert anything, because nothing stored carries a currency.
    static var currencyCode: String {
        UserDefaults.standard.string(forKey: currencyKey) ?? deviceDefault
    }

    /// "Euro", "Swiss Franc" — the reader's own name for the currency.
    static func name(for code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }
}

/// How the store came up at launch, for Settings to report. Set once, before
/// the first frame.
enum StoreStatus {
    private(set) static var isSyncing = true
    /// `nil` unless iCloud was asked for and refused.
    private(set) static var syncProblem: String?

    static func record(syncing: Bool, problem: String? = nil) {
        isSyncing = syncing
        syncProblem = problem
    }
}
