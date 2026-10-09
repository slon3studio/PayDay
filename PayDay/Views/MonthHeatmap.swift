import SwiftUI

/// A month as a calendar grid, each worked day shaded by how long you worked
/// it. Tapping a day logs or edits its shift.
struct MonthHeatmap: View {
    let month: MonthTotal
    let job: Job
    /// Days currently expanded in the list, so the grid can show where you are.
    let openDays: Set<Date>
    let onSelect: (Date) -> Void

    private var calendar: Calendar { Calendar.current }

    private var hoursByDay: [Date: Double] {
        Dictionary(uniqueKeysWithValues: month.days.map { ($0.date, $0.hours) })
    }

    private var longest: Double {
        max(1, month.days.map(\.hours).max() ?? 1)
    }

    /// Leading blanks so the 1st lands under the right weekday, then the days.
    private var cells: [Date?] {
        guard let start = calendar.dateInterval(of: .month, for: month.date)?.start,
              let count = calendar.range(of: .day, in: .month, for: month.date)?.count
        else { return [] }

        let weekday = calendar.component(.weekday, from: start)
        let lead = (weekday - calendar.firstWeekday + 7) % 7

        var out: [Date?] = Array(repeating: nil, count: lead)
        for offset in 0..<count {
            out.append(calendar.date(byAdding: .day, value: offset, to: start))
        }
        return out
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(day)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func cell(_ day: Date) -> some View {
        let hours = hoursByDay[day] ?? 0
        let worked = hours > 0
        let isOpen = openDays.contains(day)
        let isToday = calendar.isDateInToday(day)

        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.caption2.weight(worked ? .semibold : .regular))
                    .foregroundStyle(worked ? Color.primary : .secondary)
                if worked {
                    Text(Fmt.hours(hours))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(job.tint.opacity(worked ? 0.15 + 0.55 * (hours / longest) : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    // Today is ringed in the job's colour, the same as it is
                    // on the week strip — grey read as "disabled".
                    .strokeBorder(isOpen ? job.tint : (isToday ? job.tint.opacity(0.9) : .clear),
                                  lineWidth: isOpen ? 2 : 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(worked
            ? "\(Fmt.dayInMonth(day)), \(Fmt.hours(hours))"
            : "\(Fmt.dayInMonth(day)), not worked")
        .accessibilityHint(worked ? "Edit shift" : "Log a shift")
    }
}
