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
    private let cacheFileName = "DailyMoneyLog_cache.csv"
    private let gistFileName = "DailyMoneyLog.csv"
    
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
        // НЕ удаляем gistId - он может быть полезен при повторной установке токена
        // Если пользователь установит новый токен, мы попробуем использовать существующий Gist
        Task { @MainActor in
            syncStatus = .offline
        }
    }
    
    var hasToken: Bool {
        return token != nil
    }
    
    // MARK: - Инициализация
    
    func initializeIfNeeded() async throws {
        guard let token = token else {
            throw GistStorageError.invalidToken
        }
        
        if let existingGistId = gistId {
            do {
                let _ = try await fetchGistContent(gistId: existingGistId, token: token)
                return
            } catch let error as GistStorageError {
                if error == .gistNotFound || error == .invalidToken {
                    try await createNewGist()
                } else {
                    throw error
                }
            }
        } else {
            try await createNewGist()
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
                gistFileName: GistFile(content: "timestamp,amount,comment\n")
            ]
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [] // Компактный формат
            request.httpBody = try encoder.encode(body)
            
        } catch {
            // Fallback на JSONSerialization
            var filesDict = [String: [String: String]]()
            filesDict[gistFileName] = ["content": "timestamp,amount,comment\n"]
            let bodyDict: [String: Any] = [
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
        }
    }
    
    // MARK: - Загрузка
    
    func loadLog() async throws -> [Transaction] {
        // Сначала пытаемся загрузить из Gist
        if let gistId = gistId, let token = token {
            do {
                let content = try await fetchGistContent(gistId: gistId, token: token)
                let transactions = try parseCSV(content)
                saveCache(content)
                await MainActor.run {
                    syncStatus = .connected
                }
                return transactions
            } catch let error as GistStorageError {
                if error == .gistNotFound {
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
                    await MainActor.run {
                        syncStatus = .offline
                    }
                    if let cachedContent = loadCache() {
                        return try parseCSV(cachedContent)
                    }
                    throw error
                }
            } catch {
                await MainActor.run {
                    syncStatus = .offline
                }
                if let cachedContent = loadCache() {
                    return try parseCSV(cachedContent)
                }
                throw error
            }
        }
        
        // Если нет gist_id или токена, используем кэш
        if let cachedContent = loadCache() {
            await MainActor.run {
                syncStatus = .offline
            }
            return try parseCSV(cachedContent)
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
        
        guard let files = json["files"] as? [String: Any] else {
            throw GistStorageError.parseError
        }
        
        if files.isEmpty {
            throw GistStorageError.unknownError("Gist пуст. Создайте файл \(gistFileName) вручную в Gist или создайте новый Gist.")
        }
        
        guard let file = files[gistFileName] as? [String: Any] else {
            throw GistStorageError.unknownError("Файл \(gistFileName) не найден в Gist. Доступные файлы: \(files.keys.joined(separator: ", ")). Создайте файл \(gistFileName) вручную в Gist.")
        }
        
        guard let content = file["content"] as? String else {
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
    
    func syncWithGist(localTransactions: [Transaction]) async throws -> [Transaction] {
        guard let gistId = gistId, let token = token else {
            throw GistStorageError.invalidToken
        }
        
        await MainActor.run {
            syncStatus = .syncing
        }
        
        do {
            // Загружаем транзакции из Gist
            let gistTransactions = try await loadLog()
            
            // Убираем дубликаты из Gist транзакций
            var uniqueGistTransactions: [Transaction] = []
            var gistTimestamps = Set<TimeInterval>()
            for transaction in gistTransactions {
                let roundedTimestamp = transaction.roundedTimestamp
                if !gistTimestamps.contains(roundedTimestamp) {
                    uniqueGistTransactions.append(transaction)
                    gistTimestamps.insert(roundedTimestamp)
                }
            }
            
            // Убираем дубликаты из локальных транзакций
            var uniqueLocalTransactions: [Transaction] = []
            for transaction in localTransactions {
                let roundedTimestamp = transaction.roundedTimestamp
                if !uniqueLocalTransactions.contains(where: { $0.roundedTimestamp == roundedTimestamp }) {
                    uniqueLocalTransactions.append(transaction)
                }
            }
            
            // Объединяем: берем все из Gist и добавляем локальные, которых нет в Gist
            var mergedTransactions = uniqueGistTransactions
            for localTransaction in uniqueLocalTransactions {
                let roundedTimestamp = localTransaction.roundedTimestamp
                if !gistTimestamps.contains(roundedTimestamp) {
                    mergedTransactions.append(localTransaction)
                }
            }
            
            // Убираем все дубликаты из объединенного списка
            var finalTransactions: [Transaction] = []
            var finalSeenTimestamps = Set<TimeInterval>()
            for transaction in mergedTransactions {
                let roundedTimestamp = transaction.roundedTimestamp
                if !finalSeenTimestamps.contains(roundedTimestamp) {
                    finalTransactions.append(transaction)
                    finalSeenTimestamps.insert(roundedTimestamp)
                }
            }
            
            // Сортируем по дате (новые первыми)
            finalTransactions.sort { $0.date > $1.date }
            
            // Сохраняем в Gist
            try await overwriteLog(transactions: finalTransactions)
            
            await MainActor.run {
                syncStatus = .connected
            }
            
            return finalTransactions
        } catch {
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
        
        let content = formatCSV(transactions)
        
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
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        let body = GistUpdateRequest(
            files: [
                gistFileName: GistFile(content: content)
            ]
        )
        
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
        } catch {
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
    
    // MARK: - Создание файла в существующем Gist
    
    private func createFileInGist(gistId: String, token: String, content: String) async throws {
        let url = URL(string: "https://api.github.com/gists/\(gistId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        let body = GistUpdateRequest(
            files: [
                gistFileName: GistFile(content: content)
            ]
        )
        
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
        } catch {
            throw GistStorageError.unknownError("Ошибка формирования запроса: \(error.localizedDescription)")
        }
        
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
            let errorMessage = "Ошибка создания файла в Gist: \(httpResponse.statusCode)"
            throw GistStorageError.unknownError(errorMessage)
        }
        
    }
    
    // MARK: - Кэш
    
    func saveCache(_ content: String) {
        guard let cacheURL = getCacheURL() else { return }
        try? content.write(to: cacheURL, atomically: true, encoding: .utf8)
    }
    
    func loadCache() -> String? {
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
    
    func formatTransactions(_ transactions: [Transaction]) -> String {
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
                            result += "0 бесплатный день [\(Int(transaction.timestamp))]\n"
                        } else {
                            result += "\(transaction.amount) \(transaction.formattedCategory) [\(Int(transaction.timestamp))]\n"
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
    
    // MARK: - CSV форматирование и парсинг
    
    func formatCSV(_ transactions: [Transaction]) -> String {
        // Убираем дубликаты перед форматированием
        var uniqueTransactions: [Transaction] = []
        var seenTimestamps = Set<TimeInterval>()
        for transaction in transactions {
            let roundedTimestamp = transaction.roundedTimestamp
            if !seenTimestamps.contains(roundedTimestamp) {
                uniqueTransactions.append(transaction)
                seenTimestamps.insert(roundedTimestamp)
            }
        }
        // Сортируем по timestamp (от новых к старым)
        let sorted = uniqueTransactions.sorted { $0.timestamp > $1.timestamp }
        
        var result = "timestamp,amount,comment\n"
        // Используем формат без дробных секунд: 2025-11-27T19:13:24Z
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC
        
        for transaction in sorted {
            let timestampDate = Date(timeIntervalSince1970: transaction.timestamp)
            let timestampISO = dateFormatter.string(from: timestampDate)
            // Используем formattedCategory для добавления суффиксов " еда" и " алко"
            let comment = transaction.category == "бесплатный день" ? "бесплатный день" : transaction.formattedCategory
            // Всегда экранируем комментарий в кавычках для единообразия
            result += "\(timestampISO),\(transaction.amount),\"\(comment)\"\n"
        }
        return result
    }
    
    func parseCSV(_ content: String) throws -> [Transaction] {
        let lines = content.components(separatedBy: .newlines)
        var transactions: [Transaction] = []
        var seenTimestamps = Set<TimeInterval>() // Для отслеживания дубликатов
        
        // Пропускаем заголовок
        guard lines.count > 1 else {
            return []
        }
        
        // Используем формат без дробных секунд: 2025-11-27T19:13:24Z
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || index == 0 { // Пропускаем пустые строки и заголовок
                continue
            }
            
            // Парсим CSV строку: timestamp,amount,comment
            // Используем более надежный парсинг для обработки кавычек в комментариях
            var components: [String] = []
            var currentComponent = ""
            var inQuotes = false
            
            for char in trimmed {
                if char == "\"" {
                    inQuotes.toggle()
                } else if char == "," && !inQuotes {
                    components.append(currentComponent)
                    currentComponent = ""
                } else {
                    currentComponent.append(char)
                }
            }
            components.append(currentComponent) // Последний компонент
            
               guard components.count >= 3 else {
                   continue
               }
            
            let timestampStr = components[0].trimmingCharacters(in: .whitespaces)
            let amount = components[1].trimmingCharacters(in: .whitespaces)
            var comment = components[2].trimmingCharacters(in: .whitespaces)
            
            // Убираем кавычки из комментария, если есть
            if comment.hasPrefix("\"") && comment.hasSuffix("\"") {
                comment = String(comment.dropFirst().dropLast())
            }
            
            // Убираем суффиксы " еда" и " алко" для сохранения чистой категории
            let cleanCategory = comment.replacingOccurrences(of: " еда", with: "")
                .replacingOccurrences(of: " алко", with: "")
            
            // Парсим timestamp - поддерживаем оба формата (с дробными секундами и без)
            var timestampDate: Date?
            
            // Сначала пробуем с дробными секундами (для старых файлов)
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            fractionalFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            timestampDate = fractionalFormatter.date(from: timestampStr)
            
            // Если не получилось, пробуем без дробных секунд
            if timestampDate == nil {
                timestampDate = dateFormatter.date(from: timestampStr)
            }
            
               guard let date = timestampDate else {
                   continue
               }
            
            let timestamp = date.timeIntervalSince1970
            // Округляем до одного знака после точки
            let roundedTimestamp = Transaction.roundTimestamp(timestamp)
            
            // Date в Swift всегда хранит время в UTC, но при использовании Calendar.current
            // он автоматически интерпретирует его в локальном часовом поясе
            // Проблема может быть в том, что при парсинге ISO8601 дата уже в UTC,
            // но нам нужно использовать эту дату как есть - Calendar сам конвертирует при необходимости
            
            // Проверяем на дубликаты по округленному timestamp
            if !seenTimestamps.contains(roundedTimestamp) {
                let transaction = Transaction(amount: amount, category: cleanCategory, date: date, timestamp: roundedTimestamp)
                transactions.append(transaction)
                seenTimestamps.insert(roundedTimestamp)
            }
        }
        
        return transactions
    }
    
    // MARK: - Парсинг Markdown (для отображения и экспорта)
    
    func parseMarkdown(_ content: String) throws -> [Transaction] {
        let lines = content.components(separatedBy: .newlines)
        var transactions: [Transaction] = []
        var currentDate: Date?
        var transactionIndex = 0 // Индекс для генерации уникального timestamp для старых файлов
        
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "ru_RU")
        dayFormatter.dateFormat = "dd.MM.yy"
        dayFormatter.timeZone = TimeZone.current
        dayFormatter.calendar = Calendar.current
        
        // Устанавливаем двухзначный год в диапазоне 2000-2099
        dayFormatter.twoDigitStartDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1))
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Пропускаем Markdown заголовки (строки, начинающиеся с #)
            if trimmed.hasPrefix("#") {
                continue
            }
            
            // Пропускаем заголовки месяцев
            if trimmed.contains(" - ") && !trimmed.contains(".") {
                continue
            }
            
            // Проверяем, является ли строка датой в формате dd.MM.yy
            let datePattern = #"^\d{2}\.\d{2}\.\d{2}$"#
            if trimmed.range(of: datePattern, options: .regularExpression) != nil {
                if let date = dayFormatter.date(from: trimmed) {
                    currentDate = date
                    continue
                }
            }
            
            // Извлекаем timestamp из строки, если он есть (формат: "текст [timestamp]")
            var timestamp: TimeInterval?
            var lineWithoutTimestamp = trimmed
            if let timestampRange = trimmed.range(of: #"\[\d+\]$"#, options: .regularExpression) {
                let timestampString = String(trimmed[timestampRange].dropFirst().dropLast())
                if let ts = TimeInterval(timestampString) {
                    timestamp = ts
                    lineWithoutTimestamp = String(trimmed[..<timestampRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
            }
            
            // Обрабатываем "0 бесплатный день" - создаем транзакцию с amount="0" и category="бесплатный день"
            if lineWithoutTimestamp == "0 бесплатный день" || (lineWithoutTimestamp.hasPrefix("0 ") && lineWithoutTimestamp.contains("бесплатный")) {
                if let date = currentDate {
                    // Используем сохраненный timestamp или генерируем уникальный из даты и индекса
                    let ts: TimeInterval
                    if let savedTimestamp = timestamp {
                        ts = savedTimestamp
                    } else {
                        // Генерируем уникальный timestamp: дата + небольшое смещение на основе индекса
                        ts = date.timeIntervalSince1970 + Double(transactionIndex) * 0.001
                    }
                    let transaction = Transaction(amount: "0", category: "бесплатный день", date: date, timestamp: ts)
                    transactions.append(transaction)
                    transactionIndex += 1
                }
                continue
            }
            
            // Парсим транзакцию: "сумма категория [timestamp]"
            let components = lineWithoutTimestamp.components(separatedBy: " ")
            if components.count >= 2, let amount = components.first, !amount.isEmpty {
                let category = components.dropFirst().joined(separator: " ")
                let cleanCategory = category.replacingOccurrences(of: " еда", with: "")
                    .replacingOccurrences(of: " алко", with: "")
                
                if let date = currentDate {
                    let ts: TimeInterval
                    if let savedTimestamp = timestamp {
                        ts = savedTimestamp
                    } else {
                        ts = date.timeIntervalSince1970 + Double(transactionIndex) * 0.001
                    }
                    let transaction = Transaction(amount: amount, category: cleanCategory, date: date, timestamp: ts)
                    transactions.append(transaction)
                    transactionIndex += 1
                }
            }
        }
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



