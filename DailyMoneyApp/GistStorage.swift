import Foundation
import Security
import Combine

struct GistCreateRequest: Codable {
    var description: String
    var `public`: Bool
    var files: [String: GistFile]
}

struct GistFile: Codable {
    let content: String
}

struct GistUpdateRequest: Codable {
    let files: [String: GistFile]
}

// Вспомогательная структура для правильной сериализации
struct GistFilesWrapper: Codable {
    let files: [String: GistFile]
}

enum GistStorageError: LocalizedError, Equatable {
    case invalidToken
    case networkError
    case gistNotFound
    case parseError
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Неверный токен GitHub. Проверьте токен в настройках."
        case .networkError:
            return "Ошибка сети. Проверьте подключение к интернету."
        case .gistNotFound:
            return "Gist не найден. Будет создан новый."
        case .parseError:
            return "Ошибка парсинга данных."
        case .unknownError(let message):
            return message
        }
    }
    
    static func == (lhs: GistStorageError, rhs: GistStorageError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidToken, .invalidToken),
             (.networkError, .networkError),
             (.gistNotFound, .gistNotFound),
             (.parseError, .parseError):
            return true
        case (.unknownError(let lhsMessage), .unknownError(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

enum SyncStatus {
    case connected
    case offline
    case tokenError
    case conflict
    case syncing
}

class GistStorage: ObservableObject {
    static let shared = GistStorage()
    
    private let tokenKey = "github_token"
    private let gistIdKey = "github_gist_id"
    private let cacheFileName = "DailyMoneyLog_cache.md"
    
    private var token: String? {
        get {
            return KeychainHelper.get(key: tokenKey)
        }
        set {
            if let value = newValue {
                KeychainHelper.save(key: tokenKey, value: value)
            } else {
                KeychainHelper.delete(key: tokenKey)
            }
        }
    }
    
    private var gistId: String? {
        get {
            return UserDefaults.standard.string(forKey: gistIdKey)
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: gistIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: gistIdKey)
            }
        }
    }
    
    @Published var syncStatus: SyncStatus = .offline
    
    var gistURL: URL? {
        guard let gistId = gistId else { return nil }
        return URL(string: "https://gist.github.com/\(gistId)")
    }
    
    private init() {
        // Токен должен быть установлен пользователем через UI
        // Не храним токен в коде для безопасности
    }
    
    func setToken(_ newToken: String) {
        token = newToken
    }
    
    func clearToken() {
        token = nil
        gistId = nil // Очищаем gist_id при удалении токена
    }
    
    var hasToken: Bool {
        return token != nil
    }
    
    // MARK: - Инициализация
    
    func initializeIfNeeded() async throws {
        if gistId == nil {
            print("📝 No gist ID found, creating new gist...")
            try await createNewGist()
        } else {
            print("✅ Gist ID found: \(gistId ?? "nil")")
        }
    }
    
    private func createNewGist() async throws {
        guard let token = token else {
            throw GistStorageError.invalidToken
        }
        
        let url = URL(string: "https://api.github.com/gists")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // GitHub API требует формат "token <token>" для Personal Access Tokens
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        // Используем Codable структуру для гарантии правильного формата
        let body = GistCreateRequest(
            description: "DailyMoneyApp log file",
            public: false,
            files: [
                "DailyMoneyLog.md": GistFile(content: "# DailyMoneyApp Log\n")
            ]
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [] // Компактный формат
            request.httpBody = try encoder.encode(body)
            
            // Проверяем результат через JSONSerialization
            if let jsonObject = try? JSONSerialization.jsonObject(with: request.httpBody!, options: []) as? [String: Any],
               let files = jsonObject["files"] as? [String: Any] {
                print("✅ Files field exists: \(files.keys)")
            }
            
            if let bodyString = String(data: request.httpBody!, encoding: .utf8) {
                print("📤 Request body: \(bodyString)")
            }
        } catch {
            print("❌ JSON encoding error: \(error)")
            // Fallback на JSONSerialization
            var filesDict = [String: [String: String]]()
            filesDict["DailyMoneyLog.md"] = ["content": "# DailyMoneyApp Log\n"]
            var bodyDict: [String: Any] = [
                "description": "DailyMoneyApp log file",
                "public": false,
                "files": filesDict
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: bodyDict, options: [])
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            await MainActor.run {
                syncStatus = .offline
            }
            throw GistStorageError.networkError
        }
        
        if httpResponse.statusCode == 401 {
            await MainActor.run {
                syncStatus = .tokenError
            }
            throw GistStorageError.invalidToken
        }
        
        guard httpResponse.statusCode == 201 else {
            let errorMessage = "Ошибка создания Gist: \(httpResponse.statusCode)"
            if let responseData = String(data: data, encoding: .utf8) {
                print("❌ Gist creation error response: \(responseData)")
            }
            
            // Логируем заголовки для отладки
            print("📋 Response headers: \(httpResponse.allHeaderFields)")
            print("📋 Request headers: \(request.allHTTPHeaderFields ?? [:])")
            
            await MainActor.run {
                syncStatus = .offline
            }
            throw GistStorageError.unknownError(errorMessage)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        if let id = json["id"] as? String {
            gistId = id
            await MainActor.run {
                syncStatus = .connected
            }
            print("✅ Gist created successfully! ID: \(id)")
            print("🔗 URL: https://gist.github.com/\(id)")
        }
    }
    
    // MARK: - Загрузка
    
    func loadLog() async throws -> [Transaction] {
        // Сначала пытаемся загрузить из Gist
        if let gistId = gistId, let token = token {
            do {
                let content = try await fetchGistContent(gistId: gistId, token: token)
                let transactions = try parseMarkdown(content)
                // Сохраняем в кэш
                saveCache(content)
                await MainActor.run {
                    syncStatus = .connected
                }
                return transactions
            } catch let error as GistStorageError {
                if error == .gistNotFound {
                    // Создаём новый gist
                    try await createNewGist()
                    await MainActor.run {
                        syncStatus = .connected
                    }
                    return []
                } else if error == .invalidToken {
                    await MainActor.run {
                        syncStatus = .tokenError
                    }
                    throw error
                } else {
                    // Ошибка сети - используем кэш
                    await MainActor.run {
                        syncStatus = .offline
                    }
                    if let cachedContent = loadCache() {
                        return try parseMarkdown(cachedContent)
                    }
                    throw error
                }
            }
        }
        
        // Если нет gist_id или токена, используем кэш
        if let cachedContent = loadCache() {
            await MainActor.run {
                syncStatus = .offline
            }
            return try parseMarkdown(cachedContent)
        }
        
        return []
    }
    
    private func fetchGistContent(gistId: String, token: String) async throws -> String {
        let url = URL(string: "https://api.github.com/gists/\(gistId)")!
        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GistStorageError.networkError
        }
        
        if httpResponse.statusCode == 401 {
            throw GistStorageError.invalidToken
        }
        
        if httpResponse.statusCode == 404 {
            throw GistStorageError.gistNotFound
        }
        
        guard httpResponse.statusCode == 200 else {
            throw GistStorageError.unknownError("Ошибка загрузки Gist: \(httpResponse.statusCode)")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard let files = json["files"] as? [String: Any],
              let file = files["DailyMoneyLog.md"] as? [String: Any],
              let content = file["content"] as? String else {
            throw GistStorageError.parseError
        }
        
        return content
    }
    
    // MARK: - Запись
    
    func appendEntry(transaction: Transaction) async throws {
        await MainActor.run {
            syncStatus = .syncing
        }
        
        guard let gistId = gistId, let token = token else {
            // Сохраняем в кэш
            if let cachedContent = loadCache() {
                let newContent = appendTransactionToMarkdown(cachedContent, transaction: transaction)
                saveCache(newContent)
            } else {
                let newContent = formatTransaction(transaction)
                saveCache(newContent)
            }
            await MainActor.run {
                syncStatus = .offline
            }
            return
        }
        
        do {
            // Загружаем текущий контент
            let currentContent = try await fetchGistContent(gistId: gistId, token: token)
            let newContent = appendTransactionToMarkdown(currentContent, transaction: transaction)
            
            // Обновляем Gist
            try await updateGist(gistId: gistId, token: token, content: newContent)
            
            // Сохраняем в кэш
            saveCache(newContent)
            await MainActor.run {
                syncStatus = .connected
            }
        } catch {
            // Ошибка сети - сохраняем в кэш
            if let cachedContent = loadCache() {
                let newContent = appendTransactionToMarkdown(cachedContent, transaction: transaction)
                saveCache(newContent)
            } else {
                let newContent = formatTransaction(transaction)
                saveCache(newContent)
            }
            await MainActor.run {
                syncStatus = .offline
            }
            throw error
        }
    }
    
    func overwriteLog(transactions: [Transaction]) async throws {
        await MainActor.run {
            syncStatus = .syncing
        }
        
        let content = formatTransactions(transactions)
        print("📝 Formatted content (first 200 chars): \(String(content.prefix(200)))")
        print("📝 Content contains newlines: \(content.contains("\n"))")
        
        guard let gistId = gistId, let token = token else {
            // Сохраняем только в кэш
            saveCache(content)
            await MainActor.run {
                syncStatus = .offline
            }
            return
        }
        
        do {
            try await updateGist(gistId: gistId, token: token, content: content)
            saveCache(content)
            await MainActor.run {
                syncStatus = .connected
            }
        } catch {
            saveCache(content)
            await MainActor.run {
                syncStatus = .offline
            }
            throw error
        }
    }
    
    private func updateGist(gistId: String, token: String, content: String) async throws {
        let url = URL(string: "https://api.github.com/gists/\(gistId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = GistUpdateRequest(
            files: [
                "DailyMoneyLog.md": GistFile(content: content)
            ]
        )
        
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
        } catch {
            print("❌ JSON encoding error: \(error)")
            throw GistStorageError.unknownError("Ошибка формирования запроса: \(error.localizedDescription)")
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GistStorageError.networkError
        }
        
        if httpResponse.statusCode == 401 {
            throw GistStorageError.invalidToken
        }
        
        if httpResponse.statusCode == 404 {
            throw GistStorageError.gistNotFound
        }
        
        guard httpResponse.statusCode == 200 else {
            throw GistStorageError.unknownError("Ошибка обновления Gist: \(httpResponse.statusCode)")
        }
    }
    
    // MARK: - Кэш
    
    private func saveCache(_ content: String) {
        guard let cacheURL = getCacheURL() else { return }
        try? content.write(to: cacheURL, atomically: true, encoding: .utf8)
    }
    
    private func loadCache() -> String? {
        guard let cacheURL = getCacheURL(),
              FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }
        return try? String(contentsOf: cacheURL, encoding: .utf8)
    }
    
    private func getCacheURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent(cacheFileName)
    }
    
    // MARK: - Форматирование
    
    private func formatTransactions(_ transactions: [Transaction]) -> String {
        let calendar = Calendar.current
        let groupedByMonth = Dictionary(grouping: transactions) { transaction in
            calendar.date(from: calendar.dateComponents([.year, .month], from: transaction.date))!
        }
        
        var result = ""
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "ru_RU")
        monthFormatter.dateFormat = "LLLL"
        
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "ru_RU")
        dayFormatter.dateFormat = "dd.MM.yy"
        
        for month in groupedByMonth.keys.sorted(by: >) {
            let monthTransactions = groupedByMonth[month]!
            let monthSum = monthTransactions.reduce(0.0) { total, t in
                total + (Double(t.amount) ?? 0.0)
            }
            
            result += "\(monthFormatter.string(from: month).capitalized) - \(Int(monthSum))\n\n"
            
            let groupedByDay = Dictionary(grouping: monthTransactions) { transaction in
                calendar.startOfDay(for: transaction.date)
            }
            
            let today = calendar.startOfDay(for: Date())
            let daysWithTransactions = groupedByDay.keys
                .filter { dayStart in dayStart <= today }
                .sorted(by: >)
            
            // Используем только дни, которые есть в транзакциях (включая дни с "0 бесплатный день")
            let allDays = groupedByDay.keys.filter { dayStart in dayStart <= today }.sorted(by: >)
            
            for dayStart in allDays {
                let dateString = dayFormatter.string(from: dayStart)
                
                if let dayTransactions = groupedByDay[dayStart] {
                    result += "\(dateString)\n"
                    // Сортируем транзакции, но "бесплатный день" всегда идет первым
                    let sortedTransactions = dayTransactions.sorted { t1, t2 in
                        if t1.category == "бесплатный день" { return true }
                        if t2.category == "бесплатный день" { return false }
                        return t1.date > t2.date
                    }
                    
                    for transaction in sortedTransactions {
                        if transaction.category == "бесплатный день" {
                            result += "0 бесплатный день\n"
                        } else {
                            result += "\(transaction.amount) \(transaction.formattedCategory)\n"
                        }
                    }
                    result += "\n"
                }
            }
        }
        
        // Не обрезаем переносы строк в конце, чтобы сохранить форматирование
        return result.trimmingCharacters(in: .whitespaces) + "\n"
    }
    
    private func formatTransaction(_ transaction: Transaction) -> String {
        let calendar = Calendar.current
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "ru_RU")
        monthFormatter.dateFormat = "LLLL"
        
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "ru_RU")
        dayFormatter.dateFormat = "dd.MM.yy"
        
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: transaction.date))!
        let monthString = monthFormatter.string(from: month).capitalized
        let dateString = dayFormatter.string(from: transaction.date)
        let amount = Double(transaction.amount) ?? 0.0
        
        return "\(monthString) - \(Int(amount))\n\n\(dateString)\n\(transaction.amount) \(transaction.formattedCategory)\n"
    }
    
    private func appendTransactionToMarkdown(_ content: String, transaction: Transaction) -> String {
        // Парсим текущий контент и добавляем транзакцию
        var transactions = (try? parseMarkdown(content)) ?? []
        transactions.append(transaction)
        return formatTransactions(transactions)
    }
    
    // MARK: - Парсинг
    
    private func parseMarkdown(_ content: String) throws -> [Transaction] {
        let lines = content.components(separatedBy: .newlines)
        var transactions: [Transaction] = []
        var currentDate: Date?
        
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "ru_RU")
        dayFormatter.dateFormat = "dd.MM.yy"
        dayFormatter.timeZone = TimeZone.current
        dayFormatter.calendar = Calendar.current
        
        // Устанавливаем двухзначный год в диапазоне 2000-2099
        dayFormatter.twoDigitStartDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1))
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Пропускаем заголовки месяцев
            if trimmed.contains(" - ") && !trimmed.contains(".") {
                continue
            }
            
            // Проверяем, является ли строка датой в формате dd.MM.yy
            // Проверяем паттерн: две цифры, точка, две цифры, точка, две цифры
            let datePattern = #"^\d{2}\.\d{2}\.\d{2}$"#
            if trimmed.range(of: datePattern, options: .regularExpression) != nil {
                if let date = dayFormatter.date(from: trimmed) {
                    currentDate = date
                    print("📅 Parsed date: \(trimmed) -> \(date)")
                    continue
                } else {
                    print("⚠️ Failed to parse date: \(trimmed)")
                }
            }
            
            // Обрабатываем "0 бесплатный день" - создаем транзакцию с amount="0" и category="бесплатный день"
            if trimmed == "0 бесплатный день" || (trimmed.hasPrefix("0 ") && trimmed.contains("бесплатный")) {
                if let date = currentDate {
                    let transaction = Transaction(amount: "0", category: "бесплатный день", date: date)
                    transactions.append(transaction)
                    print("📅 Free day: \(dayFormatter.string(from: date))")
                }
                continue
            }
            
            // Парсим транзакцию: "сумма категория"
            let components = trimmed.components(separatedBy: " ")
            if components.count >= 2, let amount = components.first, !amount.isEmpty {
                let category = components.dropFirst().joined(separator: " ")
                let cleanCategory = category.replacingOccurrences(of: " еда", with: "")
                    .replacingOccurrences(of: " алко", with: "")
                
                if let date = currentDate {
                    let transaction = Transaction(amount: amount, category: cleanCategory, date: date)
                    transactions.append(transaction)
                    print("💰 Transaction: \(amount) \(cleanCategory) on \(dayFormatter.string(from: date))")
                } else {
                    print("⚠️ No date set for transaction: \(trimmed)")
                }
            }
        }
        
        print("✅ Parsed \(transactions.count) transactions")
        return transactions
    }
}

// MARK: - Keychain Helper

class KeychainHelper {
    static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        return nil
    }
    
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

