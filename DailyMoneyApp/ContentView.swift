import SwiftUI

struct ContentView: View {
    @State private var amount: String = ""
    @State private var comment: String = ""

    var body: some View {
        VStack(spacing: 24) {
            TextField("Введите сумму", text: $amount)
                .keyboardType(.numberPad)
                .font(.system(size: 28))
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal, 32)

            TextField("Комментарий", text: $comment)
                .font(.system(size: 20))
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.top, 100)
    }
}

#Preview {
    ContentView()
}
