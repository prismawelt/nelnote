import SwiftUI
import WidgetKit

struct ProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        completion(ProgressEntry(date: Date(), snapshot: context.isPreview ? .preview : WidgetSnapshotStore().load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        let entry = ProgressEntry(date: Date(), snapshot: WidgetSnapshotStore().load())
        // App edits explicitly reload the timeline; this also retries a temporarily unavailable file.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

@main
struct NelNoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshotStore.kind, provider: ProgressProvider()) { entry in
            ProgressWidgetView(entry: entry)
        }
        .configurationDisplayName("도장깨기")
        .description("진행 중인 게임, 애니, 미연시, 책을 모아 봐요. 작품을 누르면 기록을 이어갈 수 있어요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

