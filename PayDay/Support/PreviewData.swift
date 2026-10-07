import Foundation
import SwiftData

/// In-memory container with two jobs and a couple of months of shifts, for
/// Xcode previews only: an evening bar job Thursday to Sunday, with tips, and
/// a weekday desk job.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: Shift.self, MonthPayment.self, Job.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let bar = Job(name: "M🐱ček", color: .orange, symbol: "fork.knife", hourlyRate: 9,
                      tracksTips: true, worksWeekends: true,
                      defaultCheckInMinutes: 16 * 60, defaultCheckOutMinutes: 23 * 60 + 30, sortOrder: 0)
        let desk = Job(name: "IJS 👨‍💻", color: .blue, symbol: "chevron.left.forwardslash.chevron.right",
                       hourlyRate: 9.25, defaultCheckInMinutes: 8 * 60, defaultCheckOutMinutes: 16 * 60, sortOrder: 1)
        context.insert(bar)
        context.insert(desk)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        for offset in 0..<56 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            // 1 = Sunday … 7 = Saturday.
            let weekday = calendar.component(.weekday, from: day)

            if [5, 6, 7, 1].contains(weekday) {
                let start = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: day)!
                // Fridays and Saturdays run past midnight.
                let late = weekday == 6 || weekday == 7
                let end = late
                    ? calendar.date(bySettingHour: 1, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: 1, to: day)!)!
                    : calendar.date(bySettingHour: 23, minute: 30, second: 0, of: day)!
                context.insert(Shift(job: bar, checkIn: start, checkOut: end, tips: Double(18 + (offset * 7) % 45)))
            }

            if (2...5).contains(weekday) {
                let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
                let end = calendar.date(bySettingHour: offset % 3 == 0 ? 16 : 17, minute: 30, second: 0, of: day)!
                context.insert(Shift(job: desk, checkIn: start, checkOut: end))
            }
        }
        return container
    }()
}
