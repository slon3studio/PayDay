import SwiftUI
import SwiftData

/// A tab per job, then Profile. With no jobs yet there's only Profile — which
/// is where a fresh install adds its first one.
struct ContentView: View {
    @Query(sort: [SortDescriptor(\Job.sortOrder), SortDescriptor(\Job.createdAt)]) private var jobs: [Job]

    /// A job's id, or `profileTag`. Stored, so the app reopens where you left
    /// it — and so the job editor can switch to a job it just created.
    @AppStorage("selectedTab") private var selectedTab = ""
    @AppStorage(Appearance.key) private var appearanceRaw: String = Appearance.system.rawValue
    @AppStorage(UserProfile.colorKey) private var profileColorRaw = UserProfile.defaultColor.rawValue
    /// Not read here on purpose. Holding it at the root means changing the
    /// currency in Settings invalidates the whole tab tree, so every amount
    /// below redraws in the new one.
    @AppStorage(AppSettings.currencyKey) private var currencyCode = AppSettings.deviceDefault

    private static let profileTag = "profile"

    /// The stored tab, or a sensible one when nothing's stored yet or that
    /// job has since been deleted.
    private var selection: Binding<String> {
        Binding(
            get: {
                if selectedTab == Self.profileTag || jobs.contains(where: { $0.id.uuidString == selectedTab }) {
                    return selectedTab
                }
                return jobs.first?.id.uuidString ?? Self.profileTag
            },
            set: { selectedTab = $0 }
        )
    }

    private var tint: Color {
        jobs.first { $0.id.uuidString == selection.wrappedValue }?.tint
            ?? (JobColor(rawValue: profileColorRaw) ?? UserProfile.defaultColor).color
    }

    var body: some View {
        Group {
            // With no jobs there is nothing for the tabs to show, and Profile
            // on its own is a settings page standing in for a first screen.
            if jobs.isEmpty {
                WelcomeView()
            } else {
                tabs
            }
        }
        .animation(.snappy, value: jobs.isEmpty)
        .tint(tint)
        .fontDesign(.rounded)
        .preferredColorScheme(Appearance(rawValue: appearanceRaw)?.colorScheme)
        // One recognizer on the window covers every screen, so tapping away
        // from a field closes the keyboard anywhere in the app.
        .onAppear { KeyboardDismisser.shared.install() }
    }

    private var tabs: some View {
        TabView(selection: selection) {
            ForEach(jobs) { job in
                JobView(job: job)
                    .tag(job.id.uuidString)
                    .tabItem { Label(job.displayName, systemImage: job.symbol) }
            }

            ProfileView()
                .tag(Self.profileTag)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
