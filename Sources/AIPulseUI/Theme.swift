import SwiftUI
import AIPulseCore

/// Minimal design tokens: clean typography, SF Symbols, light/dark.
enum Theme {
    static let corner: CGFloat = 12
    static let spacing: CGFloat = 12
    static let hPad: CGFloat = 16

    static let title = Font.headline
    static let body = Font.subheadline
    static let caption = Font.caption
}

/// Source badge chip.
struct SourceBadge: View {
    let source: Source
    var body: some View {
        Text(source.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .accessibilityLabel("Source: \(source.displayName)")
    }
}

/// Topic chip.
struct TopicChip: View {
    let topic: Topic
    var body: some View {
        Text(topic.displayName)
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.fill.tertiary, in: Capsule())
    }
}

/// Relative timestamp text, e.g. "3h ago". Missing dates render "—".
struct RelativeTimeText: View {
    let date: Date?
    var body: some View {
        Text(date.map { RelativeDateTimeFormatter.localizedString(for: $0, relativeTo: .now) } ?? "—")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(date.map { Text("Published \(DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short))") } ?? Text("Publish time unknown"))
    }
}

extension RelativeDateTimeFormatter {
    static func localizedString(for date: Date, relativeTo reference: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: reference)
    }
}
