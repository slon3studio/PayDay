import SwiftUI
import SwiftData

@main
struct PayDayApp: App {
    /// How far the store got at launch.
    ///
    /// This used to be a force-unwrapped `ModelContainer`, which meant that
    /// anything the container disliked — no iCloud account, iCloud Drive off,
    /// a container not yet provisioned, a disk with no room — killed the app
    /// on launch with no message. None of those are reasons to lose the app,
    /// and the first two are the normal state of a device App Review runs on.
    private enum Store {
        case ready(ModelContainer)
        case unavailable(String)
    }

    private let store: Store

    init() {
        store = Self.open()
        if case .ready(let container) = store {
            // Before the first frame, so an updated install opens straight
            // onto its job rather than flashing the empty, add-a-job Profile.
            AppSetup.migrateIfNeeded(container.mainContext)
        }
    }

    private static func open() -> Store {
        let schema = Schema([Shift.self, MonthPayment.self, Job.self])

        // What we want: on disk, mirrored to iCloud.
        do {
            let synced = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic))
            StoreStatus.record(syncing: true)
            return .ready(synced)
        } catch {
            let cloudProblem = error.localizedDescription

            // iCloud being unavailable says nothing about whether the shifts
            // belong on this phone. Keep the app working, unsynced, and let
            // Settings explain why.
            do {
                let local = try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
                StoreStatus.record(syncing: false, problem: cloudProblem)
                return .ready(local)
            } catch {
                return .unavailable(error.localizedDescription)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            switch store {
            case .ready(let container):
                ContentView()
                    .modelContainer(container)
            case .unavailable(let reason):
                StoreUnavailableView(reason: reason)
            }
        }
    }
}

/// Shown only when the store could not be opened at all — which means the
/// shifts are still on disk, but this launch can't reach them. Saying so beats
/// a crash, and beats an empty app that looks like the data is gone.
struct StoreUnavailableView: View {
    let reason: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.orange)

            Text("Can't open your shifts")
                .font(.title2.bold())

            Text("Your data is still on this phone — PayDay just couldn't load it this time. Closing the app and opening it again usually fixes it. If your phone is low on storage, freeing some space will too.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(reason)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(32)
        .fontDesign(.rounded)
    }
}
