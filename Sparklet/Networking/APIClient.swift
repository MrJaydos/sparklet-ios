import Foundation

// Thin URLSession wrapper. The bearer token is passed in per-call rather
// than read from AuthSession directly, so this stays a plain, testable
// value type with no dependency on the main-actor-isolated session object.
struct APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func get<Response: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        token: String?
    ) async throws -> Response {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        return try await send(request, token: token)
    }

    func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        token: String?
    ) async throws -> Response {
        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await send(request, token: token)
    }

    // No caller needs the `{ ok: true }` body back — a dedicated
    // non-generic method avoids the awkward "decode into a type I'm
    // discarding" shape a generic `delete<Response>` would force at the
    // call site.
    func deleteDiscardingResponse(_ path: String, token: String?) async throws {
        var request = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent(path))
        request.httpMethod = "DELETE"
        let _: EmptyDecodable = try await send(request, token: token)
    }

    private func send<Response: Decodable>(_ request: URLRequest, token: String?) async throws -> Response {
        var request = request
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            throw APIError.unauthorized
        }
        guard (200..<300).contains(status) else {
            throw APIError.server(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

// Decodes successfully against any JSON object — used by
// deleteDiscardingResponse where the caller only cares that the request
// succeeded, not the response body's shape.
private struct EmptyDecodable: Decodable {}
