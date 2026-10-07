import SwiftUI

extension View {
    /// Tapping anywhere in this view drops the keyboard.
    ///
    /// The amount fields use `.decimalPad`, which has no return key — without
    /// this there's no way to put the keyboard away. `simultaneousGesture` so
    /// buttons, rows and pickers underneath still get the tap.
    func dismissesKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
    }
}
