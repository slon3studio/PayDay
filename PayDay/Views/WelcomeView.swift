import SwiftUI
import SwiftData

/// What a brand new install opens on, in place of a Profile tab with nothing
/// in it.
///
/// The old first screen was a settings page: it asked for your name before it
/// had told you what the app was for, and everything below the fold was empty.
/// This says what PayDay does in three lines, then asks for the one thing it
/// actually needs. Deliberately not a paged walkthrough — those get swiped
/// past without being read.
struct WelcomeView: View {
    @State private var addingJob = false
    @State private var editingProfile = false

    @AppStorage(UserProfile.nameKey) private var name = ""

    private let accent = UserProfile.defaultColor

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                mark
                    .padding(.top, 48)
                    .padding(.bottom, 28)

                VStack(spacing: 10) {
                    Text(name.isEmpty ? "Welcome to PayDay" : "Welcome, \(name)")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Know what you've worked, and what you're owed.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 34)

                VStack(spacing: 20) {
                    point("square.grid.2x2.fill", "A tab for every job",
                          "Each one keeps its own rate, hours and colour.")
                    point("chart.line.uptrend.xyaxis", "See the month coming",
                          "PayDay works out what it will pay before it does.")
                    point("checkmark.seal.fill", "Check the payslip",
                          "Record what actually landed, and spot a short month.")
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)

                Button {
                    Haptics.tap()
                    addingJob = true
                } label: {
                    Text("Add your first job")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .tint(accent.color)
                .padding(.horizontal, 24)

                Button {
                    editingProfile = true
                } label: {
                    Text(name.isEmpty ? "Add your name" : "Edit your profile")
                        .font(.subheadline.weight(.medium))
                        .padding(.vertical, 14)
                }
                .tint(accent.color)

                Text("Nothing leaves your phone except to your own iCloud. No account, no ads.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $addingJob) { JobEditorView(target: .new) }
        .sheet(isPresented: $editingProfile) { ProfileEditorView() }
        .fontDesign(.rounded)
    }

    // MARK: - Pieces

    /// The app's own mark, so the first screen and the icon agree.
    private var mark: some View {
        VStack(spacing: 0) {
            Text("Pay").foregroundStyle(.white)
            Text("Day").foregroundStyle(Color(white: 0.09))
        }
        .font(.system(size: 30, weight: .heavy, design: .rounded))
        .frame(width: 104, height: 104)
        .background(
            LinearGradient(colors: [Color(red: 0.29, green: 0.87, blue: 0.50),
                                    Color(red: 0.09, green: 0.64, blue: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(accent.color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    WelcomeView()
        .modelContainer(PreviewData.container)
}
