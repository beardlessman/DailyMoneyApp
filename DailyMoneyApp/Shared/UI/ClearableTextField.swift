import SwiftUI

struct ClearableTextField: View {
    let title: String
    @Binding var text: String
    var font: Font = .system(size: 20)
    var keyboardType: UIKeyboardType = .default
    var textAlignment: TextAlignment = .leading
    var submitLabel: SubmitLabel = .done
    var disableAutocorrection: Bool = false
    var focus: FocusState<Bool>.Binding
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .trailing) {
            TextField(title, text: $text)
                .keyboardType(keyboardType)
                .font(font)
                .multilineTextAlignment(textAlignment)
                .padding()
                .focused(focus)
                .autocorrectionDisabled(disableAutocorrection)
                .textInputAutocapitalization(disableAutocorrection ? .never : .sentences)
                .submitLabel(submitLabel)
                .onSubmit {
                    onSubmit?()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .padding(.trailing, 16)
                }
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal, 32)
    }
}
