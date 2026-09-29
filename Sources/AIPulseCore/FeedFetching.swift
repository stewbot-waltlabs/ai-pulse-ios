import Foundation

/// Typed feed errors.
public enum FeedError: Error, Equatable, Sendable {
    case badURL
    case http(Int)
    case network(String)
    case emptyResponse
}

/// Abstraction over the network so tests can inject fixtures.
public protocol FeedFetching: Sendable {
    func fetch(_ source: Source) async throws -> [NewsItem]
}

/// Production implementation: URLSession over `Source/url`.
/// Sends a descriptive User-Agent: Reddit's RSS 429s generic agents and
/// Microsoft's blog 403s curl-style agents without one.
public struct URLSessionFeedFetcher: FeedFetching {
    public var session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(_ source: Source) async throws -> [NewsItem] {
        guard let url = URL(string: source.url.absoluteString) else { throw FeedError.badURL }
        var request = URLRequest(url: url)
        request.setValue("AI-Pulse-iOS/1.0 (news aggregator; contact: support@waltlabs.example)",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/atom+xml, application/json, application/xml, text/xml, */*",
                         forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FeedError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedError.http(http.statusCode)
        }
        guard !data.isEmpty else { throw FeedError.emptyResponse }
        return FeedParsing.parse(data: data, source: source)
    }
}
