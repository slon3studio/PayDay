import SwiftUI

/// Current-month pay projection: logged so far, plus the remaining days of the
/// month filled in at your average daily hours. If a monthly goal is set, the
/// projection is measured against it.
struct ProjectionCard: View {
    let projection: MonthProjection
    @Binding var basis: ProjectionBasis

    private var job: Job { projection.job }
    private var goalTarget: Double { job.goalTarget }
    private var goalKind: GoalKind { job.goalKind }

    /// Where you are now, and where you'll land, in the goal's own units.
    private var goalNow: Double { goalKind.isMoney ? projection.payToDate : projection.hoursSoFar }
    private var goalProjected: Double { goalKind.isMoney ? projection.projectedTotal : projection.projectedHours }

    private func goalText(_ value: Double) -> String {
        goalKind.isMoney ? Fmt.money(value) : Fmt.hours(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Profile stacks both jobs' cards, so each says whose it is.
            HStack(spacing: 5) {
                Image(systemName: job.symbol)
                Text(job.displayName)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(job.tint)
            .padding(.bottom, -10)

            if projection.isEmpty {
                Text("Log a shift this month to see a projection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Fmt.money(projection.projectedTotal))
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            // Money is green wherever it appears, even on a
                            // card belonging to a job of another colour.
                            .foregroundStyle(Palette.money)
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("\(Fmt.hours(projection.projectedHours)) by the end of \(Fmt.monthTitle(.now))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if goalTarget > 0 {
                        Spacer(minLength: 0)
                        GoalRing(progress: goalNow / goalTarget, tint: job.tint)
                    }
                }

                if goalTarget > 0 {
                    Divider()
                    goalSection
                }

                Divider()

                // Split three ways on purpose. Worked is a fact, planned is
                // a rota you entered, estimated is the app guessing — and
                // adding them into one number would hide which is which.
                VStack(spacing: 8) {
                    part("Worked", projection.payToDate, Fmt.hours(projection.hoursSoFar), Palette.money)
                    if projection.hasPlan {
                        part("Planned", projection.plannedPay, Fmt.hours(projection.plannedHours), job.tint)
                    }
                    part("Estimated", projection.estimatedPay,
                         estimatedDaysText, .secondary)
                }

                if projection.hasPlan {
                    Text("Planned shifts don't count as earned until you confirm them.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    /// One line of the split: what it comes to, and what it rests on.
    private func part(_ label: String, _ amount: Double, _ detail: String, _ tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .offset(y: -2)
            Text(label)
                .font(.subheadline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            Text(Fmt.money(amount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint == .secondary ? Color.secondary : tint)
        }
    }

    private var estimatedDaysText: String {
        let days = projection.estimatedDays
        let count = days.rounded() == days ? "\(Int(days))" : String(format: "%.1f", days)
        return "\(count) day\(days == 1 ? "" : "s") at \(Fmt.hours(projection.averageHoursPerDay))"
    }

    // MARK: - Goal

    private var goalSection: some View {
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

            HStack(spacing: 4) {
                Image(systemName: willMake ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(willMake ? Palette.money : Palette.attention)
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

/// How far through the monthly goal you already are, as a ring.
struct GoalRing: View {
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((progress * 100).rounded()))%")
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
        .frame(width: 64, height: 64)
        .animation(.snappy, value: progress)
        .accessibilityLabel("\(Int((progress * 100).rounded())) percent of monthly goal")
    }
}
