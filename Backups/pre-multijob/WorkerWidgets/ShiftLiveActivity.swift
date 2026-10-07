import ActivityKit
import SwiftUI
import WidgetKit

/// The Lock Screen banner and Dynamic Island presentation for a shift that's
/// currently running.
struct ShiftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftActivityAttributes.self) { context in
            ShiftLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(context.attributes.job.tint)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.job.displayName)
                            .font(.caption.weight(.semibold))
                    } icon: {
                        Image(systemName: context.attributes.job.symbol)
                    }
                    .foregroundStyle(context.attributes.job.tint)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(Fmt.money(context.state.earnedSoFar))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                }

                DynamicIslandExpandedRegion(.center) {
                    ElapsedText(start: context.attributes.startedAt)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(context.attributes.job.tint)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text("Clocked in at \(Fmt.time(context.attributes.startedAt)) · \(Fmt.money(context.attributes.hourlyRate))/h")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: context.attributes.job.symbol)
                    .foregroundStyle(context.attributes.job.tint)
            } compactTrailing: {
                ElapsedText(start: context.attributes.startedAt)
                    .frame(maxWidth: 52)
                    .monospacedDigit()
                    .foregroundStyle(context.attributes.job.tint)
            } minimal: {
                Image(systemName: context.attributes.job.symbol)
                    .foregroundStyle(context.attributes.job.tint)
            }
            .keylineTint(context.attributes.job.tint)
        }
    }
}

/// The Lock Screen banner. Pulled out of the widget so it's an ordinary view —
/// renderable in a preview without an activity to hand.
struct ShiftLockScreenView: View {
    let attributes: ShiftActivityAttributes
    let state: ShiftActivityAttributes.ContentState

    private var job: Job { attributes.job }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: job.symbol)
                    .foregroundStyle(job.tint)
                Text(job.displayName)
                    .font(.headline)
                Text("on the clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Fmt.money(attributes.hourlyRate) + "/h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(alignment: .firstTextBaseline) {
                ElapsedText(start: attributes.startedAt)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(job.tint)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.money(state.earnedSoFar))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                    Text("earned so far")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Since \(Fmt.time(attributes.startedAt))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

/// A self-ticking elapsed clock — the system redraws it, so the app doesn't
/// have to push an update every second.
struct ElapsedText: View {
    let start: Date

    var body: some View {
        Text(
            timerInterval: start...start.addingTimeInterval(24 * 3600),
            pauseTime: nil,
            countsDown: false,
            showsHours: true
        )
    }
}
