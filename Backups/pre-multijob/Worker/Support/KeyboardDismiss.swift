import SwiftUI

extension View {
    /// A "Done" button above the keyboard that puts it away.
    ///
    /// The amount fields use `.decimalPad`, which has no return key — without
    /// this there's no way to dismiss it. This used to be a tap gesture over
    /// the whole form, but since iOS 18 a tap gesture on a form swallows the
    /// taps meant for its buttons: "Delete shift" looked fine and did nothing.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
            }
        }
    }
}
