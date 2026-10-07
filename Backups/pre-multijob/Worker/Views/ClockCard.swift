import SwiftUI

/// Repeat the last shift — or, if a timer is still running, watch it and
/// clock out. Mirrors onto the Lock Screen and Dynamic Island through
/// `ShiftClock`'s Live Activity.
struct ClockCard: View {
    let job: Job
    /// The shift "repeat" would copy, or `nil` when there's nothing logged yet.
    let lastShift: Shift?
    /// Today's shift once there is one — repeating again would just log a
    /// duplicate, so the button gives way to a confirmation.
    let todayShift: Shift?
    /// Called with the real check-in/check-out times so the caller can open the
    /// editor — nothing is saved until you confirm there.
    let onClockOut: (Date, Date) -> Void
    let onRepeat: () -> Void
    /// Set only right after a repeat, so a mis-tap can be taken back.
    var onUndo: (() -> Void)? = nil

    private var clock: ShiftClock { .shared }

    var body: some View {
        if let running = clock.running, running.job == job {
            card { onTheClock(running) }
        } else if let running = clock.running {
            card { busyElsewhere(running) }
        } else if let today = todayShift {
            card { loggedToday(today) }
        } else if let last = lastShift {
            // The button is its own card — wrapping it in another just adds
            // a frame around a frame.
            repeatButton(last)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Idle

    /// Repeating the last shift is the one quick way to log; anything else
    /// goes through the + in the toolbar.
    private func repeatButton(_ last: Shift) -> some View {
        Button(action: onRepeat) {
            // Plain text, not a Label: the button hides the icon but keeps
            // its space, which pushed the title off centre.
            Text("Repeat \(Fmt.time(last.checkIn)) → \(Fmt.time(last.checkOut))")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .tint(job.tint)
    }

    private func loggedToday(_ shift: Shift) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Logged today")
                    .font(.headline)
                Text("\(Fmt.time(shift.checkIn)) → \(Fmt.time(shift.checkOut)) · \(Fmt.hours(shift.hours))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if let onUndo {
                Button("Undo", action: onUndo)
                    .buttonStyle(.bordered)
                    .tint(job.tint)
            }
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
