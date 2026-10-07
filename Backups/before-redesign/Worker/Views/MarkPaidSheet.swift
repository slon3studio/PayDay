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
            Form {
                Section {
                    HStack {
                        Text("Amount received")
                        Spacer()
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 130)
                        Text("€").foregroundStyle(.secondary)
                    }
                    DatePicker("Paid on", selection: $paidOn, displayedComponents: .date)
                } header: {
                    Text("\(job.displayName) · \(Fmt.monthTitle(monthStart))")
                }

                Section {
                    StatRow(label: "App expected", value: Fmt.money(expected))
                    StatRow(label: "You received", value: Fmt.money(amount))
                    StatRow(
                        label: difference < 0 ? "Short by" : "Extra",
                        value: Fmt.money(abs(difference)),
                        emphasized: true,
                        tint: differenceTint
                    )
                } footer: {
                    Text(differenceExplanation)
                }

                Section("Note") {
                    TextField("Optional — payslip number, agency, anything", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Remove payment", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
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
    }

    /// A cent or two either way is rounding, not a problem.
    private var isMatch: Bool { abs(difference) < 0.01 }

    private var differenceTint: Color {
        isMatch ? .green : (difference < 0 ? .orange : .green)
    }

    private var differenceExplanation: String {
        if isMatch {
            return "Matches what the logged shifts add up to."
        }
        if difference < 0 {
            return "You were paid less than the logged shifts come to. Worth checking — unless tax or an agency fee comes off first, in which case this gap is expected every month."
        }
        return "You were paid more than the logged shifts come to. A missing shift, or a bonus."
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
