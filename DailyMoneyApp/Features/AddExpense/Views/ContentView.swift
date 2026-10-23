import SwiftUI
import Foundation
import UIKit

struct Toast: Identifiable {
    let id = UUID()
    let message: String
}

struct ContentView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var transactionManager: TransactionManager
    @EnvironmentObject var budgetManager: BudgetManager
    @State private var amount: String = ""
    @State private var comment: String = "Продукты"
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isCommentFocused: Bool
    @State private var toasts: [Toast] = []
    @State private var focusTaskGeneration = 0

    @AppStorage("google_forms_url") private var googleFormsURL: String = ""

    private var dailyBudget: Double {
        budgetManager.dailyBudget(monthSpent: transactionManager.getMonthSpentAmount())
    }

    private var availableAmount: Double {
        budgetManager.availableAmount(
            monthSpent: transactionManager.getMonthSpentAmount(),
            todaySpent: transactionManager.getTodaySpentAmount()
        )
    }

    private var amountColor: Color {
        let available = availableAmount
        let halfDailyBudget = dailyBudget / 2.0

        if available > halfDailyBudget {
            return .green
        } else if available < 0 {
            return .red
        } else {
            return .primary
        }
    }

    private func openBudgetSettings() {
        clearFocus()
        navigationManager.showBudgetSettings = true
    }

    private func clearFocus() {
        focusTaskGeneration += 1
        isAmountFocused = false
        isCommentFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func scheduleFocusIfOnForm() {
        guard navigationManager.selectedTab == NavigationManager.formTab, !navigationManager.showBudgetSettings else { return }

        focusTaskGeneration += 1
        let generation = focusTaskGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard generation == focusTaskGeneration,
                  navigationManager.selectedTab == NavigationManager.formTab,
                  !navigationManager.showBudgetSettings else { return }
            isAmountFocused = true
        }
    }

    private func scrollToAddButton(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation {
                proxy.scrollTo("addButton", anchor: .bottom)
            }
        }
    }

    private func submitForm() {
        let categoryText = comment.isEmpty ? "Другое" : comment
        let amountToSend = amount
        let commentToSend = categoryText
        let categoryToSend = ExpenseCategories.extract(from: commentToSend)

        transactionManager.addTransaction(amount: amountToSend, category: categoryText)

        Task {
            let result = await GoogleFormsService.send(
                urlString: googleFormsURL,
                amount: amountToSend,
                comment: commentToSend,
                category: categoryToSend
            )
            await handleGoogleFormsResult(result)
        }

        let toast = Toast(message: "\(amountToSend) \(categoryText)")
        withAnimation {
            toasts.append(toast)
        }

        amount = ""
        comment = "Продукты"
        scheduleFocusIfOnForm()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                toasts.removeAll { $0.id == toast.id }
            }
        }
    }

    @MainActor
    private func handleGoogleFormsResult(_ result: GoogleFormsService.SendResult) {
        switch result {
        case .skipped, .success:
            break
        case .invalidURL:
            showToast("Некорректный URL Google Forms")
        case .httpError(let statusCode):
            showToast("Google Forms ответ: \(statusCode)")
        case .networkError:
            showToast("Ошибка отправки в Google Forms")
        }
    }

    @MainActor
    private func showToast(_ message: String) {
        let toast = Toast(message: message)
        withAnimation {
            toasts.append(toast)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                toasts.removeAll { $0.id == toast.id }
            }
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                if transactionManager.isLoading && transactionManager.transactions.isEmpty {
                    Text("...")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)
                } else {
                    Button(action: openBudgetSettings) {
                        Text("\(Int(availableAmount))")
                            .font(.system(size: 50, weight: .black))
                            .foregroundColor(amountColor)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    .buttonStyle(.plain)
                }

                ScrollViewReader { proxy in
                    ScrollView {
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
                                ForEach(ExpenseCategories.suggestions, id: \.self) { suggestion in
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
                        .id("addButton")
                    }
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.never)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: isAmountFocused) { _, focused in
                    if focused {
                        scrollToAddButton(proxy)
                    }
                }
                .onChange(of: isCommentFocused) { _, focused in
                    if focused {
                        scrollToAddButton(proxy)
                    }
                }
                }
            }
            .padding(.top, 56)

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
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.top, 50)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            if navigationManager.selectedTab == NavigationManager.formTab {
                scheduleFocusIfOnForm()
            }
        }
        .onChange(of: navigationManager.selectedTab) { _, newValue in
            if newValue == NavigationManager.formTab {
                scheduleFocusIfOnForm()
            } else {
                clearFocus()
            }
        }
        .onChange(of: navigationManager.showBudgetSettings) { _, isShowing in
            if isShowing {
                clearFocus()
            } else if navigationManager.selectedTab == NavigationManager.formTab {
                scheduleFocusIfOnForm()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(NavigationManager())
        .environmentObject(TransactionManager())
        .environmentObject(BudgetManager())
}
