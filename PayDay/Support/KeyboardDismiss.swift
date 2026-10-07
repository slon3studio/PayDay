import SwiftUI
import UIKit

/// Tapping anywhere outside a text field puts the keyboard away.
///
/// The amount fields use `.decimalPad`, which has no return key, so without
/// something like this there is no way to dismiss it.
///
/// The obvious version — a tap gesture on the `Form` — was tried and removed:
/// since iOS 18 it swallows the taps meant for the form's own controls, which
/// is how "Delete shift" ended up looking fine and doing nothing. This one is
/// a recognizer on the window with `cancelsTouchesInView = false`, so the tap
/// still travels on to whatever is underneath it. Buttons keep working; the
/// keyboard just happens to close on the way.
///
/// Touches that land in a text field are ignored, or tapping from one field
/// straight into another would close the keyboard and immediately reopen it.
final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()

    private var recognizer: UITapGestureRecognizer?

    /// Safe to call repeatedly — it attaches once, to the first window that
    /// exists. Called from `ContentView.onAppear`, by which point there is one.
    func install() {
        guard recognizer == nil else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else { return }

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismiss))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        recognizer = tap
    }

    @objc private func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - UIGestureRecognizerDelegate

    /// Never take a tap that landed on a text field — that tap is the one
    /// opening the keyboard.
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    /// Run alongside whatever else is listening, rather than instead of it.
    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
