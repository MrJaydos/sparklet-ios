import Foundation

enum APIError: Error {
    case unauthorized
    case server(status: Int, body: String)
    case decoding(Error)
    case transport(Error)
}
