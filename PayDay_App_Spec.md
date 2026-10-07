# PayDay — Shift & Pay Tracker

A SwiftUI iOS app for logging work hours across two jobs, with automatic pay
and tip stats. Built in Xcode, project folder: `PayDay`.

## Jobs

1. **IJS** — programming job
   - Rate: **9.25 €/h**
   - Log check-in / check-out only

2. **Maček** — waiter job
   - Rate: **9.00 €/h**
   - Log check-in / check-out **plus tips earned that day**

## Core structure

Three tabs: **IJS**, **Maček**, **Profile**.

### Per-job tab (IJS / Maček)
- Button or form to log a shift: check-in time + check-out time (defaults to
  today, but editable date for backfilling a missed entry)
- Maček only: numeric field for tips earned that shift (€)
- List of logged shifts, most recent first, grouped by day
- Stats panel for that job:
  - Total hours worked (this month / all-time toggle)
  - List of days worked with hours per day
  - Average hours per shift/day
  - Maček only: total tips this month, average tip/shift
  - **Projected pay for the current month**: hours logged so far × rate
    (+ tips for Maček), extrapolated using the average daily hours over the
    remaining working days in the month
  - Edit/delete existing shift entries

### Profile tab
- Combined stats across both jobs:
  - Total hours: IJS, Maček, and combined
  - Total earnings: IJS, Maček, and combined (Maček includes tips)
  - Optional: simple bar/line view comparing the two jobs by week or month

## Data model (suggested)

```swift
struct Shift: Identifiable, Codable {
    let id: UUID
    let job: Job              // .ijs or .macek
    var date: Date
    var checkIn: Date
    var checkOut: Date
    var tips: Double?         // only used for .macek
}

enum Job: String, Codable {
    case ijs, macek

    var hourlyRate: Double {
        switch self {
        case .ijs: return 9.25
        case .macek: return 9.00
        }
    }
}
```

Store locally first (e.g. SwiftData or a JSON file) — no backend needed
for v1.

## Notes / open questions to decide before building
- Currency formatting: always show € with 2 decimals
- Overnight shifts (check-out past midnight) — handle date rollover
- "Current month" projection: decide whether to count only weekdays,
  or all days logged historically as the pattern
- Should shift editing require confirmation before delete (non-destructive
  by default, per your usual preference)

## Suggested build order for Claude Code
1. Data model + local persistence (SwiftData)
2. IJS tab: log shift, list shifts, basic stats
3. Maček tab: same as IJS + tips field and tip stats
4. Profile tab: combined stats
5. Polish: monthly pay projection logic, editing/deleting entries
