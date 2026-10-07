import SwiftUI

/// Current-month pay projection: logged so far, plus the remaining days of the
/// month filled in at your average daily hours. If a monthly goal is set, the
/// projection is measured against it.
struct ProjectionCard: View {
    let projection: MonthProjection
    @Binding var basis: ProjectionBasis

    @AppStorage private var goalTarget: Double
    @AppStorage private var goalKindRaw: String

    init(projection: MonthProjection, basis: Binding<ProjectionBasis>) {
        self.projection = projection
        self._basis = basis
        _goalTarget = AppStorage(wrappedValue: 0, MonthlyGoal.targetKey(projection.job))
        _goalKindRaw = AppStorage(wrappedValue: GoalKind.money.rawValue, MonthlyGoal.kindKey(projection.job))
    }

    private var job: Job { projection.job }
    private var goalKind: GoalKind { GoalKind(rawValue: goalKindRaw) ?? .money }

    /// Where you are now, and where you'll land, in the goal's own units.
    private var goalNow: Double { goalKind.isMoney ? projection.payToDate : projection.hoursSoFar }
    private var goalProjected: Double { goalKind.isMoney ? projection.projectedTotal : projection.projectedHours }

    private func goalText(_ value: Double) -> String {
        goalKind.isMoney ? Fmt.money(value) : Fmt.hours(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if projection.isEmpty {
                Text("Log a shift this month to see a projection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Projected total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Fmt.money(projection.projectedTotal))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(job.tint)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("\(Fmt.hours(projection.projectedHours)) by the end of \(Fmt.monthTitle(.now))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if goalTarget > 0 {
                    Divider()
                    goalSection
                }

                Divider()

                VStack(spacing: 8) {
                    StatRow(label: "Logged so far", value: Fmt.money(projection.payToDate))
                    StatRow(label: "Hours so far", value: Fmt.hours(projection.hoursSoFar))
                    if job.tracksTips {
                        StatRow(label: "Tips so far", value: Fmt.money(projection.tipsSoFar))
                        StatRow(label: "Projected tips", value: Fmt.money(projection.projectedTips))
                    }
                    StatRow(
                        label: "Days left to work",
                        value: projection.remainingDays.rounded() == projection.remainingDays
                            ? "\(Int(projection.remainingDays))"
                            : String(format: "%.1f", projection.remainingDays)
                    )
                    StatRow(label: "At avg/day", value: Fmt.hours(projection.averageHoursPerDay))
                }

                Divider()
            }

            VStack(alignment: .leading, spacing: 6) {
                Picker("Remaining days", selection: $basis.animation(.default)) {
                    ForEach(ProjectionBasis.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Text(basis.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Goal

    private var goalSection: some View {
        let progress = min(1, max(0, goalNow / goalTarget))
        let willMake = goalProjected >= goalTarget
        let gap = abs(goalProjected - goalTarget)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Monthly goal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(goalText(goalNow)) of \(goalText(goalTarget))")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }

            ProgressView(value: progress)
                .tint(job.tint)

            HStack(spacing: 4) {
                Image(systemName: willMake ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(willMake ? .green : .orange)
                Text(willMake
                     ? "On track — projected to clear it by \(goalText(gap))."
                     : "Projected to fall \(goalText(gap)) short.")
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
