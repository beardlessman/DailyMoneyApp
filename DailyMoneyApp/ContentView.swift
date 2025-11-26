import SwiftUI

struct ContentView: View {
    @State private var amount: String = ""
    @State private var comment: String = ""
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            TextField("Сумма", text: $amount)
                .keyboardType(.numberPad)
                .font(.system(size: 28))
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal, 32)
                .focused($isAmountFocused)

            TextField("Категория", text: $comment)
                .font(.system(size: 20))
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.top, 100)
        .onAppear {
            isAmountFocused = true
        }
    }
}

#Preview {
    ContentView()
}
