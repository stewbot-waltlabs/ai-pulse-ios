import Foundation

/// Parsers turn raw feed bytes into `[NewsItem]`. Malformed items are skipped,
/// never fatal.
public enum FeedParsing {

    /// Dispatch on feed kind.
    public static func parse(data: Data, source: Source, fetchedAt: Date = .now) -> [NewsItem] {
        switch source.kind {
        case .hnAlgolia:
            parseAlgoliaJSON(data: data, source: source, fetchedAt: fetchedAt)
        case .rss, .atom, .redditRSS:
            parseXML(data: data, source: source, fetchedAt: fetchedAt)
        }
    }

    // MARK: - XML (RSS 2.0 / Atom / Reddit RSS)

    /// Generic XML walker that collects "entries" — either `<item>` (RSS) or
    /// `<entry>` (Atom) — as flat dictionaries of child text.
    static func parseXML(data: Data, source: Source, fetchedAt: Date) -> [NewsItem] {
        let delegate = FeedXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        // Ignore parser.parse()'s success flag: malformed items later in the
        // document must not discard valid entries collected earlier.
        _ = parser.parse()
        return delegate.entries.compactMap { entry in item(fromEntry: entry, source: source, fetchedAt: fetchedAt) }
    }

    static func item(fromEntry entry: [String: String], source: Source, fetchedAt: Date) -> NewsItem? {
        let title = entry["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }
        guard let link = bestLink(entry), let url = URL(string: link.encodingForURL ?? link) else { return nil }
        let summary = (entry["description"] ?? entry["summary"] ?? entry["content"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return NewsItem(
            title: title,
            summary: summary,
            url: url,
            source: source,
            publishedAt: parseXMLDate(entry["pubDate"] ?? entry["published"] ?? entry["updated"]),
            fetchedAt: fetchedAt
        )
    }

    static func bestLink(_ entry: [String: String]) -> String? {
        if let link = entry["link"], !link.isEmpty { return link }
        if let href = entry["linkHref"], !href.isEmpty { return href } // Atom href captured by delegate
        if let guid = entry["guid"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           guid.hasPrefix("http") { return guid }
        return nil
    }

    /// RFC 822 (RSS), ISO 8601 (Atom), and common variants.
    public static func parseXMLDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = Date.rfc822(s) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return isoFractional.date(from: s)
    }

    // MARK: - HN Algolia JSON

    struct AlgoliaResponse: Decodable {
        var hits: [AlgoliaHit]?
    }

    struct AlgoliaHit: Decodable {
        var objectID: String?
        var title: String?
        var storyTitle: String?
        var url: String?
        var storyURL: String?
        var points: Int?
        var numComments: Int?
        var createdAt: String?
        var created_atI: Int?

        enum CodingKeys: String, CodingKey {
            case objectID, title, storyTitle, url, storyURL, points
            case numComments = "num_comments"
            case createdAt = "created_at"
            case created_atI = "created_at_i"
        }
    }

    static func parseAlgoliaJSON(data: Data, source: Source, fetchedAt: Date) -> [NewsItem] {
        guard let response = try? JSONDecoder().decode(AlgoliaResponse.self, from: data),
              let hits = response.hits else { return [] }
        return hits.compactMap { hit in
            let title = (hit.title ?? hit.storyTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let link = hit.url ?? hit.storyURL
            guard let link, let url = URL(string: link) else { return nil }
            return NewsItem(
                id: hit.objectID ?? UUID().uuidString,
                title: title,
                summary: "",
                url: url,
                source: source,
                publishedAt: algoliaDate(hit),
                engagement: NewsItem.Engagement(points: hit.points, comments: hit.numComments),
                fetchedAt: fetchedAt
            )
        }
    }

    static func algoliaDate(_ hit: AlgoliaHit) -> Date? {
        if let unix = hit.created_atI { return Date(timeIntervalSince1970: TimeInterval(unix)) }
        if let iso = hit.createdAt {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: iso)
        }
        return nil
    }
}

extension Date {
    /// RFC 822 / RFC 1123 (RSS pubDate), e.g. "Mon, 29 Sep 2026 10:00:00 GMT".
    /// Handles named zones (GMT/UT/EST…) via `zzz`, numeric offsets
    /// ("+0000", "+0100") via `xxxx`, and falls back to no weekday prefix.
    static func rfc822(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")

        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let variants = [
            "EEE, dd MMM yyyy HH:mm:ss zzz", // Mon, 29 Sep 2026 10:00:00 GMT
            "EEE, dd MMM yyyy HH:mm:ss xxxx", // Mon, 29 Sep 2026 10:00:00 +0100
            "dd MMM yyyy HH:mm:ss zzz",       // 29 Sep 2026 10:00:00 GMT
            "dd MMM yyyy HH:mm:ss xxxx",      // 29 Sep 2026 10:00:00 +0100
            "EEE, dd MMM yyyy HH:mm zzz",     // Mon, 29 Sep 2026 10:00 GMT (no seconds)
        ]
        for format in variants {
            formatter.dateFormat = format
            if let d = formatter.date(from: s) { return d }
        }
        return nil
    }
}

extension String {
    /// Percent-encode spaces and stray characters so odd feed URLs still parse.
    var encodingForURL: String? {
        addingPercentEncoding(withAllowedCharacters: .urlFeedAllowed)
    }
}

extension CharacterSet {
    static let urlFeedAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.insert(charactersIn: "?&=#%+")
        return set
    }()
}

/// Collects `<item>`/`<entry>` children as dictionaries. Atom `<link href=…/>`
/// is captured under `linkHref`.
final class FeedXMLDelegate: NSObject, XMLParserDelegate {
    var entries: [[String: String]] = []
    private var currentEntry: [String: String]?
    private var currentText = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        currentText = ""
        if name == "item" || name == "entry" {
            currentEntry = [:]
        } else if currentEntry != nil, name == "link", let href = attributes["href"] {
            if currentEntry?["linkHref"] == nil { currentEntry?["linkHref"] = href }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        defer {
            if name == "item" || name == "entry" {
                if let entry = currentEntry { entries.append(entry) }
                currentEntry = nil
            }
            currentText = ""
        }
        guard name != "item", name != "entry", currentEntry != nil else { return }
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, currentEntry?[name] == nil {
            currentEntry?[name] = text // first occurrence wins; priority resolved at read time
        }
    }

    /// On a document-level parse error, keep the entries collected so far —
    /// malformed items are skipped, valid earlier items survive.
    func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
        // Deliberately retain partial results.
    }
}
