import SwiftUI
import AIPulseCore

/// One row on Pulse / Latest / Topics / Saved lists.
struct NewsRow: View {
    let scored: ScoredItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SourceBadge(source: scored.item.source)
                if let engagement = scored.item.engagement {
                    Label("\(pointsText(engagement.points)) pts · \(commentsText(engagement.comments)) comments",
                          systemImage: "arrowtriangle.up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(engagementLabel(engagement))
                }
                Spacer()
                RelativeTimeText(date: scored.item.publishedAt)
            }
            Text(scored.item.title)
                .font(Theme.title)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            if !scored.item.summary.isEmpty {
                Text(scored.item.summary)
                    .font(Theme.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !scored.score.topics.isEmpty {
                HStack(spacing: 6) {
                    ForEach(scored.score.topics) { TopicChip(topic: $0) }
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }

    private func pointsText(_ p: Int?) -> String { p.map(String.init) ?? "—" }
    private func commentsText(_ c: Int?) -> String { c.map(String.init) ?? "—" }
    private func engagementLabel(_ e: NewsItem.Engagement) -> String {
        let p = e.points.map { "\($0) points" } ?? "points unknown"
        let c = e.comments.map { "\($0) comments" } ?? "comments unknown"
        return "\(p), \(c)"
    }
}
