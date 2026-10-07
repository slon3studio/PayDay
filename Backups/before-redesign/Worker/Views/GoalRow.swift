import SwiftUI

/// Sets one job's monthly target. Stored in defaults, read back by the
/// projection card and the widget.
struct GoalRow: View {
    let job: Job

    @AppStorage private var target: Double
    @AppStorage private var kindRaw: String
    @State private var text: String

    init(job: Job) {
        self.job = job
        _target = AppStorage(wrappedValue: 0, MonthlyGoal.targetKey(job))
        _kindRaw = AppStorage(wrappedValue: GoalKind.money.rawValue, MonthlyGoal.kindKey(job))
        let saved = UserDefaults.standard.double(forKey: MonthlyGoal.targetKey(job))
        _text = State(initialValue: saved > 0 ? String(format: "%g", saved) : "")
    }

    private var kind: GoalKind { GoalKind(rawValue: kindRaw) ?? .money }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: job.symbol)
                    .foregroundStyle(job.tint)
                Text(job.displayName)
                    .font(.headline)

                Spacer(minLength: 12)

                TextField("None", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 110)
                    .onChange(of: text) { _, new in
                        target = Double(new.replacingOccurrences(of: ",", with: ".")) ?? 0
                    }

                Text(kind.isMoney ? "€" : "h")
                    .foregroundStyle(.secondary)
                    .frame(width: 14, alignment: .leading)
            }

            Picker("Goal in", selection: Binding(
                get: { kind },
                set: { kindRaw = $0.rawValue }
            ).animation(.default)) {
                ForEach(GoalKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }
}
