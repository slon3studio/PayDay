import Foundation
import SwiftData

/// A single logged shift. `checkOut` is a full date, so an overnight shift that
/// ends after midnight simply lands on the following calendar day.
@Model
final class Shift {
    var id: UUID = UUID()
    /// Stored as a raw string so SwiftData keeps a plain, migration-friendly column.
    var jobRaw: String = Job.ijs.rawValue
    var checkIn: Date = Date()
    var checkOut: Date = Date()
    /// Tips earned on this shift, in €. Only used by Maček.
    var tips: Double?
    var note: String = ""
    /// €/h this shift was logged at, so changing a rate in Settings doesn't
    /// rewrite months that are already paid. `nil` on shifts from before the
    /// rate was a setting.
    var rate: Double?

    init(job: Job, checkIn: Date, checkOut: Date, tips: Double? = nil, note: String = "", rate: Double? = nil) {
        self.id = UUID()
        self.jobRaw = job.rawValue
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.tips = tips
        self.note = note
        self.rate = rate ?? job.hourlyRate
    }

    var job: Job {
        get { Job(rawValue: jobRaw) ?? .ijs }
        set { jobRaw = newValue.rawValue }
    }

    /// Worked hours, always positive.
    var hours: Double {
        max(0, checkOut.timeIntervalSince(checkIn)) / 3600
    }

    /// The calendar day the shift is attributed to (the day it started).
    var day: Date {
        Calendar.current.startOfDay(for: checkIn)
    }

    /// True when the shift runs past midnight into the next day.
    var isOvernight: Bool {
        !Calendar.current.isDate(checkIn, inSameDayAs: checkOut)
    }

    var tipsAmount: Double { tips ?? 0 }

    /// Base pay for the shift, excluding tips.
    var basePay: Double { hours * hourlyRate }

    var hourlyRate: Double { rate ?? job.defaultHourlyRate }

    /// Everything earned on this shift, tips included.
    var totalPay: Double { basePay + tipsAmount }
}
