import SwiftUI
import SwiftData

@main
struct WorkerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Shift.self, MonthPayment.self])
    }
}
