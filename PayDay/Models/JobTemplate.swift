import SwiftUI

/// A starting point for a new job.
///
/// Adding a job used to mean an empty form and twenty-six icons to choose
/// between, which is a lot to ask of someone who has had the app for nine
/// seconds. A template fills all of it in; everything stays editable
/// afterwards, so a wrong guess costs nothing.
struct JobTemplate: Identifiable {
    let id: String
    /// What the tile says — the kind of work, not a job name.
    let label: String
    let symbol: String
    let color: JobColor
    /// Minutes past midnight.
    let checkIn: Int
    let checkOut: Int
    let tracksTips: Bool
    let worksWeekends: Bool
    let tracksBreaks: Bool
    let breakMinutes: Int
    /// Goes in the name field as a placeholder-ish starting point.
    let suggestedName: String

    static let all: [JobTemplate] = [
        JobTemplate(id: "hospitality", label: "Bar or café", symbol: "wineglass.fill",
                    color: .orange, checkIn: 17 * 60, checkOut: 23 * 60 + 30,
                    tracksTips: true, worksWeekends: true, tracksBreaks: false,
                    breakMinutes: 30, suggestedName: ""),

        JobTemplate(id: "restaurant", label: "Restaurant", symbol: "fork.knife",
                    color: .red, checkIn: 11 * 60, checkOut: 20 * 60,
                    tracksTips: true, worksWeekends: true, tracksBreaks: true,
                    breakMinutes: 30, suggestedName: ""),

        JobTemplate(id: "office", label: "Office", symbol: "desktopcomputer",
                    color: .blue, checkIn: 9 * 60, checkOut: 17 * 60,
                    tracksTips: false, worksWeekends: false, tracksBreaks: true,
                    breakMinutes: 30, suggestedName: ""),

        JobTemplate(id: "retail", label: "Shop", symbol: "cart.fill",
                    color: .teal, checkIn: 9 * 60, checkOut: 17 * 60,
                    tracksTips: false, worksWeekends: true, tracksBreaks: true,
                    breakMinutes: 30, suggestedName: ""),

        JobTemplate(id: "delivery", label: "Delivery", symbol: "bicycle",
                    color: .green, checkIn: 18 * 60, checkOut: 22 * 60,
                    tracksTips: true, worksWeekends: true, tracksBreaks: false,
                    breakMinutes: 0, suggestedName: ""),

        JobTemplate(id: "care", label: "Care or health", symbol: "cross.case.fill",
                    color: .pink, checkIn: 7 * 60, checkOut: 19 * 60,
                    tracksTips: false, worksWeekends: true, tracksBreaks: true,
                    breakMinutes: 45, suggestedName: ""),

        JobTemplate(id: "teaching", label: "Teaching", symbol: "graduationcap.fill",
                    color: .indigo, checkIn: 15 * 60, checkOut: 18 * 60,
                    tracksTips: false, worksWeekends: false, tracksBreaks: false,
                    breakMinutes: 0, suggestedName: ""),

        JobTemplate(id: "trade", label: "On site", symbol: "hammer.fill",
                    color: .brown, checkIn: 7 * 60, checkOut: 15 * 60,
                    tracksTips: false, worksWeekends: false, tracksBreaks: true,
                    breakMinutes: 30, suggestedName: ""),
    ]

    /// What a job looks like with nothing assumed about it.
    static let blank = JobTemplate(
        id: "blank", label: "Something else", symbol: JobSymbol.fallback,
        color: .blue, checkIn: 9 * 60, checkOut: 17 * 60,
        tracksTips: false, worksWeekends: false, tracksBreaks: false,
        breakMinutes: 30, suggestedName: "")
}
