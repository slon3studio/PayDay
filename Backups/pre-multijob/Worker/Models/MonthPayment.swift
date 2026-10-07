import Foundation
import SwiftData

/// What actually landed in your account for one job in one month.
///
/// The app already knows what a month *should* pay; recording what it really
/// paid is what turns that into something you can check an employer against.
@Model
final class MonthPayment {
    var id: UUID = UUID()
    var jobRaw: String = Job.ijs.rawValue
    /// First day of the month this payment covers.
    var monthStart: Date = Date()
    var amount: Double = 0
    var paidOn: Date = Date()
    var note: String = ""

    init(job: Job, monthStart: Date, amount: Double, paidOn: Date = .now, note: String = "") {
        self.id = UUID()
        self.jobRaw = job.rawValue
        self.monthStart = Calendar.current.startOfMonth(for: monthStart)
        self.amount = amount
        self.paidOn = paidOn
        self.note = note
    }

    var job: Job {
        get { Job(rawValue: jobRaw) ?? .ijs }
        set { jobRaw = newValue.rawValue }
    }

    /// Paid minus expected. Negative means you were shorted.
    func difference(from expected: Double) -> Double { amount - expected }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? startOfDay(for: date)
    }
}
