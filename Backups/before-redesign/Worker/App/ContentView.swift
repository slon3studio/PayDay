import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selection: Tab = .ijs

    @Environment(\.scenePhase) private var scenePhase

    enum Tab: Hashable {
        case ijs, macek, profile
    }

    var body: some View {
        TabView(selection: $selection) {
            JobView(job: .ijs)
                .tag(Tab.ijs)
                .tabItem { Label(Job.ijs.displayName, systemImage: Job.ijs.symbol) }

            JobView(job: .macek)
                .tag(Tab.macek)
                .tabItem { Label(Job.macek.displayName, systemImage: Job.macek.symbol) }

            ProfileView()
                .tag(Tab.profile)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(tint)
        .onChange(of: scenePhase) { _, phase in
            // Catch the Live Activity's € figure up after time has passed.
            if phase == .active { ShiftClock.shared.refreshActivity() }
        }
    }

    private var tint: Color {
        switch selection {
        case .ijs: return Job.ijs.tint
        case .macek: return Job.macek.tint
        case .profile: return .accentColor
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
