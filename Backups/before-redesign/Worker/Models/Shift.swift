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

    init(job: Job, checkIn: Date, checkOut: Date, tips: Double? = nil, note: String = "") {
        self.id = UUID()
        self.jobRaw = job.rawValue
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.tips = tips
        self.note = note
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
    var basePay: Double { hours * job.hourlyRate }

    /// Everything earned on this shift, tips included.
    var totalPay: Double { basePay + tipsAmount }
}
