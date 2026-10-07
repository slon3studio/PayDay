import SwiftUI

/// Clock in, watch the shift run, clock out. Mirrors onto the Lock Screen and
/// Dynamic Island through `ShiftClock`'s Live Activity.
struct ClockCard: View {
    let job: Job
    /// The shift "repeat" would copy, or `nil` when there's nothing logged yet.
    let lastShift: Shift?
    /// Called with the real check-in/check-out times so the caller can open the
    /// editor — nothing is saved until you confirm there.
    let onClockOut: (Date, Date) -> Void
    let onRepeat: () -> Void

    private var clock: ShiftClock { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let running = clock.running, running.job == job {
                onTheClock(running)
            } else if let running = clock.running {
                busyElsewhere(running)
            } else {
                idle
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Idle

    /// Both ways to log a shift live in one card — on a phone, two stacked
    /// cards push the numbers below the fold.
    private var idle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { clock.start(job) }
            } label: {
                // Plain text, not a Label: an icon here throws the title off
                // centre inside a full-width button.
                Text("Clock in")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(job.tint)

            if let last = lastShift {
                Button(action: onRepeat) {
                    Label(
                        "Repeat \(Fmt.time(last.checkIn)) → \(Fmt.time(last.checkOut))",
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
                    )
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.bordered)
                .tint(job.tint)
            }

            Text("Live timer on your Lock Screen — times stay editable.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    // MARK: - Running

    private func onTheClock(_ running: RunningShift) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(job.tint)
                    .frame(width: 8, height: 8)
                Text("On the clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(job.tint)
                Spacer()
                Text("since \(Fmt.time(running.startedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Redrawn every second so the timer and the running total move
            // together.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.stopwatch(context.date.timeIntervalSince(running.startedAt)))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(job.tint)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.money(running.earned(now: context.date)))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                        Text("so far")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    if let times = clock.stop() {
                        onClockOut(times.checkIn, times.checkOut)
                    }
                } label: {
                    Text("Clock out")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(job.tint)

                Button(role: .destructive) {
                    withAnimation(.snappy) { clock.discard() }
                } label: {
                    Image(systemName: "trash")
                        .font(.headline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Clocked in somewhere else

    private func busyElsewhere(_ running: RunningShift) -> some View {
        HStack(spacing: 10) {
            Image(systemName: running.job.symbol)
                .foregroundStyle(running.job.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're on the clock at \(running.job.displayName)")
                    .font(.subheadline.weight(.medium))
                Text("Clock out there before starting a shift here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
