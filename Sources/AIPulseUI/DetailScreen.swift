import SwiftUI
import AIPulseCore

/// Item detail: summary, metadata, "Read" opens the URL externally.
struct DetailScreen: View {
    let scored: ScoredItem
    @Environment(AppModel.self) private var appModel
    @State private var isSaved = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Text(scored.item.title)
                    .font(.title3.weight(.semibold))
                HStack(spacing: 10) {
                    SourceBadge(source: scored.item.source)
                    RelativeTimeText(date: scored.item.publishedAt)
                }
                if let engagement = scored.item.engagement {
                    Text(verbatim: engagementText(engagement))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Engagement not available for this source")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !scored.item.summary.isEmpty {
                    Text(scored.item.summary)
                        .font(Theme.body)
                } else {
                    Text("No summary available for this story.")
                        .font(Theme.body)
                        .foregroundStyle(.secondary)
                }
                if !scored.score.topics.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(scored.score.topics) { TopicChip(topic: $0) }
                    }
                }
                Button {
                    openURL(scored.item.url)
                } label: {
                    Label("Read", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Read the full story at \(scored.item.url.host ?? "the source")")

                Button {
                    toggleSave()
                } label: {
                    Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(isSaved ? "Remove from saved items" : "Save this story for later")
            }
            .padding(.horizontal, Theme.hPad)
            .padding(.vertical, Theme.spacing)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { isSaved = appModel.savedModel.isSaved(scored.item) }
    }

    private func engagementText(_ e: NewsItem.Engagement) -> String {
        let p = e.points.map { "\($0) points" } ?? "points unknown"
        let c = e.comments.map { "\($0) comments" } ?? "comments unknown"
        return "\(p) · \(c)"
    }

    private func toggleSave() {
        if isSaved {
            appModel.savedModel.remove(scored.item)
        } else {
            appModel.savedModel.save(scored)
        }
        isSaved = appModel.savedModel.isSaved(scored.item)
    }
}
