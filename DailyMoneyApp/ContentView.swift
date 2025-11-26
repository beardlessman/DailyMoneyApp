import SwiftUI

struct Toast: Identifiable {
    let id = UUID()
    let message: String
}

struct ContentView: View {
    @State private var amount: String = ""
    @State private var comment: String = "Продукты"
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isCommentFocused: Bool
    @State private var toasts: [Toast] = []
    
    let categorySuggestions = ["Продукты", "Доставка", "Алкоголь", "Кальян"]
    
    private func submitForm() {
        // Если категория не выбрана, подставляем "что-то"
        let categoryText = comment.isEmpty ? "что-то" : comment
        
        // Формируем сообщение и добавляем тост
        let toast = Toast(message: "\(amount) \(categoryText)")
        withAnimation {
            toasts.append(toast)
        }
        
        // Очистка формы после сабмита
        amount = ""
        comment = "Продукты"
        isAmountFocused = true
        
        // Автоматически удаляем тост через 3 секунды
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                toasts.removeAll { $0.id == toast.id }
            }
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                ZStack(alignment: .trailing) {
                    TextField("Сумма", text: $amount)
                        .keyboardType(.numberPad)
                        .font(.system(size: 28))
                        .multilineTextAlignment(.center)
                        .padding()
                        .focused($isAmountFocused)
                        .submitLabel(.next)
                        .onSubmit {
                            isAmountFocused = false
                            isCommentFocused = true
                        }
                    
                    if !amount.isEmpty {
                        Button(action: {
                            amount = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal, 32)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(categorySuggestions, id: \.self) { suggestion in
                            Button(action: {
                                comment = suggestion
                            }) {
                                Text(suggestion)
                                    .font(.system(size: 16))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(comment == suggestion ? Color.blue : Color(.systemGray5))
                                    .foregroundColor(comment == suggestion ? .white : .primary)
                                    .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                }

                ZStack(alignment: .trailing) {
                    TextField("Категория", text: $comment)
                        .font(.system(size: 20))
                        .padding()
                        .focused($isCommentFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isCommentFocused = false
                        }
                    
                    if !comment.isEmpty {
                        Button(action: {
                            comment = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal, 32)

                Button(action: submitForm) {
                    Text("Добавить")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .disabled(amount.isEmpty)

                Spacer()
            }
            .padding(.top, 213)
            .onAppear {
                isAmountFocused = true
            }
            
            // Всплывающие сообщения сверху в стопке
            if !toasts.isEmpty {
                VStack(spacing: 8) {
                    ForEach(toasts) { toast in
                        Text(toast.message)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                }
                .padding(.top, 50)
            }
        }
    }
}

#Preview {
    ContentView()
}
