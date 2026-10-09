import SwiftUI
import SwiftData

/// Record what actually arrived for one month, next to what the app worked out
/// it should be. The difference is the whole point — it's how a short payslip
/// gets noticed.
struct MarkPaidSheet: View {
    let job: Job
    let monthStart: Date
    /// What the logged shifts add up to.
    let expected: Double
    let existing: MonthPayment?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @State private var paidOn: Date
    @State private var note: String
    @State private var confirmingDelete = false

    init(job: Job, monthStart: Date, expected: Double, existing: MonthPayment?) {
        self.job = job
        self.monthStart = monthStart
        self.expected = expected
        self.existing = existing
        _amountText = State(initialValue: String(format: "%.2f", existing?.amount ?? expected))
        _paidOn = State(initialValue: existing?.paidOn ?? .now)
        _note = State(initialValue: existing?.note ?? "")
    }

    private var amount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var difference: Double { amount - expected }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    verdict
                    amountCard
                    noteCard
                    if existing != nil { removeButton }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existing == nil ? "Mark as paid" : "Edit payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(amount <= 0)
                }
            }
            .confirmationDialog("Remove this payment?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let existing { context.delete(existing) }
                    dismiss()
                }
                Button("Keep", role: .cancel) {}
            }
        }
        .tint(job.tint)
        .appAppearance()
    }

    // MARK: - Cards

    /// The whole point of the screen: what the shifts came to, what actually
    /// arrived, and the gap. The gap is the headline because it's the only
    /// figure you can't work out yourself.
    private var verdict: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [differenceTint, differenceTint.opacity(0.65)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: 6)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow("\(job.displayName) · \(Fmt.monthTitle(monthStart))", opacity: 1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isMatch ? "checkmark.seal.fill" : (difference < 0 ? "exclamationmark.triangle.fill" : "plus.circle.fill"))
                        .font(.footnote)
                        .foregroundStyle(differenceTint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(isMatch ? Fmt.money(amount) : (difference < 0 ? "−" : "+") + Fmt.money(abs(difference)))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(differenceTint)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(headline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 0) {
                    figure("The shifts came to", Fmt.money(expected))
                    figure("You received", Fmt.money(amount))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
        .animation(.snappy, value: difference)
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var amountCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Amount received", systemImage: "arrow.down.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("0", text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: 130)
                Text("€")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().padding(.leading, 16)

            HStack {
                Label("Paid on", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                DatePicker("", selection: $paidOn, displayedComponents: .date)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow("Note", opacity: 1).foregroundStyle(.secondary)
            TextField("Payslip number, agency, anything", text: $note, axis: .vertical)
                .lineLimit(1...4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Label("Remove payment", systemImage: "trash")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: Palette.cardRadius, style: .continuous))
    }

    /// One line under the big figure, saying what it means.
    private var headline: String {
        if isMatch { return "Matches what the logged shifts come to." }
        if difference < 0 {
            return "Less than the logged shifts come to. Worth checking — unless tax or an agency fee comes off first, in which case expect this gap every month."
        }
        return "More than the logged shifts come to. A missing shift, or a bonus."
    }

    /// A cent or two either way is rounding, not a problem.
    private var isMatch: Bool { abs(difference) < 0.01 }

    private var differenceTint: Color {
        isMatch ? Palette.money : (difference < 0 ? Palette.attention : Palette.money)
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing {
            existing.amount = amount
            existing.paidOn = paidOn
            existing.note = trimmed
        } else {
            context.insert(MonthPayment(
                job: job,
                monthStart: monthStart,
                amount: amount,
                paidOn: paidOn,
                note: trimmed
            ))
        }
        dismiss()
    }
}
