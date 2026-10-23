import Foundation

enum GoogleFormsService {
    enum SendResult {
        case skipped
        case success
        case invalidURL
        case httpError(Int)
        case networkError
    }

    static func send(urlString: String, amount: String, comment: String, category: String) async -> SendResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .skipped }
        guard let url = URL(string: trimmed) else { return .invalidURL }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "entry.1478941545", value: amount),
            URLQueryItem(name: "entry.913606663", value: comment),
            URLQueryItem(name: "entry.2039786247", value: category)
        ]

        guard let body = components.percentEncodedQuery else { return .skipped }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .httpError(http.statusCode)
            }
            return .success
        } catch {
            return .networkError
        }
    }
}
