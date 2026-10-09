import UIKit

/// The small physical confirmations that make an app feel finished.
///
/// Used sparingly and only where something actually happened — a shift saved,
/// a goal reached. Buzzing on every tap is noise, and people turn it off.
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// For something small and reversible, like repeating a shift.
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Heavier, for crossing the monthly goal.
    static func milestone() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
}
