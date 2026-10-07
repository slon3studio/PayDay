import Foundation
import SwiftData

/// In-memory container with a couple of weeks of shifts, for Xcode previews only.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: Shift.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        for offset in 0..<21 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)

            if weekday != 1 && weekday != 7 {
                let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
                let end = calendar.date(bySettingHour: offset % 3 == 0 ? 16 : 17, minute: 30, second: 0, of: day)!
                container.mainContext.insert(Shift(job: .ijs, checkIn: start, checkOut: end))
            }

            if weekday == 6 || weekday == 7 {
                let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day)!
                let end = calendar.date(bySettingHour: 1, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: 1, to: day)!)!
                container.mainContext.insert(
                    Shift(job: .macek, checkIn: start, checkOut: end, tips: Double(20 + (offset * 7) % 45))
                )
            }
        }
        return container
    }()
}
