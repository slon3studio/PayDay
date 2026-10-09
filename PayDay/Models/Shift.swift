import Foundation
import SwiftData

/// A single logged shift. `checkOut` is a full date, so an overnight shift that
/// ends after midnight simply lands on the following calendar day.
@Model
final class Shift {
    var id: UUID = UUID()
    var checkIn: Date = Date()
    var checkOut: Date = Date()
    /// Tips earned on this shift, in €. Only used by jobs that track them.
    var tips: Double?
    var note: String = ""
    /// €/h this shift was logged at, so changing a job's rate doesn't rewrite
    /// months that are already paid. `nil` on shifts from before the rate was
    /// recorded, which fall back to the job's current rate.
    var rate: Double?
    /// Unpaid break taken on this shift, in minutes. Stored per shift
    /// rather than read off the job, so a shift logged before the job
    /// started deducting breaks keeps the hours it was logged with.
    var breakMinutes: Int = 0
    /// The job this shift belongs to. Optional so that adding jobs to a store
    /// that predates them is a migration SwiftData can do on its own; the
    /// first launch after the update fills it in.
    var job: Job?
    /// Which job a shift belonged to back when the two jobs were fixed
    /// ("ijs" / "macek"). Only read by `AppSetup` to link old shifts to their
    /// job; empty on anything logged since.
    var jobRaw: String = ""

    init(
        job: Job?,
        checkIn: Date,
        checkOut: Date,
        tips: Double? = nil,
        note: String = "",
        rate: Double? = nil,
        breakMinutes: Int = 0
    ) {
        self.id = UUID()
        self.job = job
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.tips = tips
        self.note = note
        self.rate = rate ?? job?.hourlyRate
        self.breakMinutes = breakMinutes
    }

    /// Hours actually worked: the span, less any unpaid break. Always
    /// positive, and never negative even if the break outlasts the shift.
    var hours: Double {
        max(0, span - Double(breakMinutes) * 60) / 3600
    }

    /// Check-in to check-out, break included. What the clock says.
    var span: Double {
        max(0, checkOut.timeIntervalSince(checkIn))
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

    var hourlyRate: Double { rate ?? job?.hourlyRate ?? 0 }

    /// Base pay for the shift, excluding tips.
    var basePay: Double { hours * hourlyRate }

    /// Everything earned on this shift, tips included.
    var totalPay: Double { basePay + tipsAmount }
}
