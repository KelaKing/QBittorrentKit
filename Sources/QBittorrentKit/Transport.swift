import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol QBittorrentTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public final class URLSessionTransport: QBittorrentTransport, @unchecked Sendable {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        self.session = URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw QBittorrentError.invalidResponse
        }
        return (data, response)
    }
}

public enum QBittorrentError: Error, Sendable {
    case invalidBaseURL
    case invalidRequest(String)
    case cancelled
    case network(URLError)
    case authenticationFailed(String?)
    case http(statusCode: Int, message: String?)
    case apiFailure(String)
    case decoding(String)
    case invalidResponse
    case unsupportedVersion(required: WebAPIVersion, actual: WebAPIVersion)
}

extension QBittorrentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "The server base URL must use HTTP or HTTPS and cannot contain a query or fragment."
        case let .invalidRequest(message):
            message
        case .cancelled:
            "The request was cancelled."
        case let .network(error):
            "Network request failed: \(error.localizedDescription)"
        case let .authenticationFailed(message):
            message ?? "Authentication failed."
        case let .http(statusCode, message):
            "Server returned HTTP \(statusCode)\(message.map { ": \($0)" } ?? "")."
        case let .apiFailure(message):
            "qBittorrent rejected the request: \(message)"
        case let .decoding(message):
            "Could not decode the server response: \(message)"
        case .invalidResponse:
            "The server returned an invalid response."
        case let .unsupportedVersion(required, actual):
            "This operation requires Web API \(required) or later; server reports \(actual)."
        }
    }
}
