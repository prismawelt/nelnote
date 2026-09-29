import SwiftUI
import UIKit

/// A number pad with its own Done accessory also works inside the custom page controller.
struct BookProgressInput: UIViewRepresentable {
    let item: Item
    let ink: Color
    let onCommit: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .numberPad
        field.textAlignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        field.placeholder = "미기록"
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.field = field

        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "입력 완료", style: .done, target: context.coordinator,
                            action: #selector(Coordinator.done))
        ]
        toolbar.sizeToFit()
        field.inputAccessoryView = toolbar
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if !field.isFirstResponder { field.text = item.progressRecorded ? String(item.cur) : "" }
        field.textColor = UIColor(ink)
        field.tintColor = UIColor(ink)
        field.accessibilityLabel = item.effectiveUnit?.curLabel ?? "읽은 페이지"
        field.accessibilityIdentifier = "book-progress-\(item.id)"
    }

    static func dismantleUIView(_ field: UITextField, coordinator: Coordinator) {
        field.resignFirstResponder()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: BookProgressInput
        weak var field: UITextField?

        init(_ parent: BookProgressInput) { self.parent = parent }

        @objc func done() { field?.resignFirstResponder() }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                if textField.isFirstResponder { textField.selectAll(nil) }
            }
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            let next = ((textField.text ?? "") as NSString).replacingCharacters(in: range, with: string)
            return next.count <= 5 && next.unicodeScalars.allSatisfy { (48...57).contains($0.value) }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            guard var value = Int(textField.text ?? "") else {
                textField.text = parent.item.progressRecorded ? String(parent.item.cur) : ""
                return
            }
            if let total = parent.item.total, total > 0 { value = min(value, total) }
            textField.text = String(value)
            parent.onCommit(value)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
