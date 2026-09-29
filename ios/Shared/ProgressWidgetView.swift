import SwiftUI
import WidgetKit

struct ProgressEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private enum WidgetPalette {
    static let background = Color(red: 0.115, green: 0.13, blue: 0.19)
    static let text = Color(red: 0.91, green: 0.92, blue: 0.96)
    static let secondary = Color(red: 0.60, green: 0.64, blue: 0.72)
    static let stamp = Color(red: 1, green: 0.36, blue: 0.29)
    static let track = Color(red: 0.19, green: 0.22, blue: 0.29)

    static func ink(_ category: Category) -> Color {
        switch category {
        case .game: return Color(red: 0.21, green: 0.81, blue: 0.63)
        case .anime: return Color(red: 1, green: 0.42, blue: 0.62)
        case .vn: return Color(red: 0.65, green: 0.55, blue: 1)
        case .book: return Color(red: 0.95, green: 0.67, blue: 0.24)
        }
    }
}

struct ProgressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProgressEntry

    private var rowLimit: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 2
        default: return 4
        }
    }

    private var sections: [WidgetSection] {
        entry.snapshot?.sections(limit: rowLimit) ?? []
    }

    private var destination: URL {
        family == .systemSmall ? (sections.first?.items.first?.url ?? WidgetLink.homeURL) : WidgetLink.homeURL
    }

    var body: some View {
        content
            .widgetURL(destination)
            .modifier(WidgetBackground())
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
            header
            if let snapshot = entry.snapshot, snapshot.totalCount > 0 {
                if family == .systemSmall, let section = sections.first, let item = section.items.first {
                    categoryHeader(section)
                    itemRow(item, compact: false)
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 5) {
                            categoryHeader(section)
                            ForEach(section.items) { item in
                                Link(destination: item.url) {
                                    itemRow(item, compact: family == .systemMedium)
                                }
                            }
                        }
                    }
                }
                let hidden = snapshot.totalCount - sections.reduce(0) { $0 + $1.items.count }
                if family == .systemLarge && hidden > 0 {
                    Text("외 \(hidden)개 · 앱에서 모두 보기")
                        .font(.system(size: 10))
                        .foregroundColor(WidgetPalette.secondary)
                }
            } else {
                Spacer(minLength: 0)
                Text(entry.snapshot == nil ? "앱을 한 번 열어 주세요" : "진행 중인 작품이 없어요")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(WidgetPalette.text)
                Text("작품을 추가하고 기록을 이어가요.")
                    .font(.system(size: 11))
                    .foregroundColor(WidgetPalette.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("도장깨기")
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(WidgetPalette.stamp)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(WidgetPalette.stamp, lineWidth: 1.5))
                .rotationEffect(.degrees(-3))
            Spacer(minLength: 4)
            Text("진행 중 \(entry.snapshot?.totalCount ?? 0)")
                .font(.system(size: 11))
                .foregroundColor(WidgetPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private func categoryHeader(_ section: WidgetSection) -> some View {
        HStack(spacing: 5) {
            Text(section.category.label)
                .foregroundColor(WidgetPalette.ink(section.category))
            Text("\(section.count)")
                .foregroundColor(WidgetPalette.secondary)
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .accessibilityElement(children: .combine)
    }

    private func itemRow(_ item: WidgetItem, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.title)
                    .font(.system(size: compact ? 12 : 14, weight: .medium))
                    .foregroundColor(WidgetPalette.text)
                    .lineLimit(family == .systemSmall ? 2 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if family != .systemSmall && !item.progressText.isEmpty {
                    Text(item.progressText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(WidgetPalette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .layoutPriority(1)
                }
            }
            if family == .systemSmall && !item.progressText.isEmpty {
                Text(item.progressText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(WidgetPalette.secondary)
            }
            if !compact && !item.memo.isEmpty && item.progress == nil {
                Text(item.memo)
                    .font(.system(size: 11))
                    .foregroundColor(WidgetPalette.secondary)
                    .lineLimit(1)
            }
            if let progress = item.progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WidgetPalette.track)
                        Capsule().fill(WidgetPalette.ink(item.category))
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 3)
                .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("작품 기록 열기")
    }
}

private struct WidgetBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                WidgetPalette.background.opacity(0.96)
            }
        } else {
            content.padding(14).background(WidgetPalette.background.opacity(0.96))
        }
    }
}

extension WidgetSnapshot {
    static var preview: WidgetSnapshot {
        let examples: [(Category, String, Int, Int?, String)] = [
            (.game, "하늘의 궤적 2nd", 0, nil, "도전과제 미완료"),
            (.game, "파이어 엠블렘 만자천홍", 0, nil, ""),
            (.anime, "네가 죽을 때까지 사랑하고 싶어", 11, 12, ""),
            (.vn, "임금님 연애", 2, 6, "")
        ]
        return WidgetSnapshot(items: examples.enumerated().map { index, example in
            Item(id: "preview-\(index)", cat: example.0, title: example.1, status: .play,
                 cur: example.2, total: example.3, unit: nil, memo: example.4,
                 created: 0, statusAt: 0, doneAt: nil, updated: Int64(examples.count - index))
        })
    }
}

struct ProgressWidgetPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            ProgressWidgetView(entry: ProgressEntry(date: Date(), snapshot: .preview))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            ProgressWidgetView(entry: ProgressEntry(date: Date(), snapshot: .preview))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            ProgressWidgetView(entry: ProgressEntry(date: Date(), snapshot: .preview))
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
