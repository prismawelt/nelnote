import XCTest
import SwiftUI
import WidgetKit
@testable import NelNote

@MainActor
final class WidgetTests: XCTestCase {
    private typealias Category = NelNote.Category
    private var temporaryDirectory: URL!
    private var shared: WidgetSnapshotStore!
    private var store: Store!
    private var suite: String!
    private var defaults: UserDefaults!
    private var reloads = 0

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        shared = WidgetSnapshotStore(directory: temporaryDirectory)
        suite = "NelNoteTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        reloads = 0
        store = Store(baseURL: temporaryDirectory, widgetStore: shared, defaults: defaults,
                      reloadWidget: { [weak self] in self?.reloads += 1 })
    }

    override func tearDownWithError() throws {
        store = nil
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func item(_ id: String, cat: Category = .anime, status: ItemStatus = .play,
                      cur: Int = 2, total: Int? = 12, updated: Int64 = 1) -> Item {
        Item(id: id, cat: cat, title: "작품 " + id, status: status, cur: cur, total: total,
             unit: cat == .book ? .page : nil, memo: "", created: 0, statusAt: 0, doneAt: nil, updated: updated)
    }

    func testOnlyPlayingItemsAreSharedAndEveryCategoryGetsARow() {
        let input = [
            item("game-1", cat: .game, updated: 1), item("game-2", cat: .game, updated: 9),
            item("anime"), item("vn", cat: .vn), item("book", cat: .book),
            item("waiting", status: .wait), item("done", status: .done)
        ]
        let snapshot = WidgetSnapshot(items: input)
        XCTAssertEqual(snapshot.totalCount, 5)
        let sections = snapshot.sections(limit: 4)
        XCTAssertEqual(sections.map(\.category), Category.allCases)
        XCTAssertEqual(sections.flatMap(\.items).map(\.id), ["game-2", "anime", "vn", "book"])
        XCTAssertEqual(sections.first?.count, 2)
        XCTAssertTrue(snapshot.sections(limit: 0).isEmpty)
    }

    func testUnknownTotalsAndGamesNeverShowAFakePercentage() {
        XCTAssertNil(WidgetItem(item("game", cat: .game)).progress)
        XCTAssertNil(WidgetItem(item("ongoing", total: nil)).progress)
        XCTAssertNil(WidgetItem(item("zero", total: 0)).progress)
        XCTAssertEqual(WidgetItem(item("half", cur: 6)).progress, 0.5)
        XCTAssertEqual(WidgetItem(item("over", cur: 20)).progress, 1)
    }

    func testWidgetLinksRoundTripImportedIDsAndRejectUnrelatedURLs() throws {
        let id = "한글 / & ? # + %"
        let link = try XCTUnwrap(WidgetLink(url: WidgetLink.itemURL(id)))
        XCTAssertEqual(link, .item(id))
        XCTAssertEqual(WidgetLink(url: WidgetLink.homeURL), .home)
        for invalid in ["https://item?id=1", "nelnote://item", "nelnote://item?id=", "nelnote://other",
                        "nelnote://item/unexpected?id=1"] {
            XCTAssertNil(WidgetLink(url: try XCTUnwrap(URL(string: invalid))))
        }
    }

    func testPersistenceAndCorruptFileFallback() throws {
        let snapshot = WidgetSnapshot(items: [item("anime")])
        XCTAssertTrue(try shared.save(snapshot))
        XCTAssertEqual(shared.load(), snapshot)
        XCTAssertFalse(try shared.save(snapshot))
        try Data("corrupt".utf8).write(to: temporaryDirectory.appendingPathComponent("widget-progress.json"))
        XCTAssertNil(shared.load())
        XCTAssertTrue(try shared.save(.empty))
        XCTAssertEqual(shared.load(), .empty)
        XCTAssertFalse(try WidgetSnapshotStore(directory: nil).save(snapshot))
    }

    func testMutationsImportUndoAndRelaunchKeepTheWidgetInSync() throws {
        let source = [item("anime", cur: 11), item("book", cat: .book, status: .wait)]
        let json = String(data: try JSONEncoder().encode(source), encoding: .utf8)!
        XCTAssertEqual(store.importBackup(json), 2)
        XCTAssertEqual(shared.load()?.totalCount, 1)
        XCTAssertEqual(shared.load()?.items.first?.progressText, "11 / 12화")

        let unchangedReloads = reloads
        store.syncWidget()
        XCTAssertEqual(reloads, unchangedReloads)

        store.increment("anime")
        XCTAssertEqual(shared.load()?.totalCount, 0)
        store.undo(source)
        XCTAssertEqual(shared.load()?.totalCount, 1)
        store.start("book")
        XCTAssertEqual(shared.load()?.totalCount, 2)
        store.delete("anime")
        XCTAssertEqual(shared.load()?.items.map(\.id), ["book"])
        store.finish("book")
        XCTAssertEqual(shared.load()?.totalCount, 0)

        store.saveEditor(EditorInput(existingID: nil, cat: .vn, title: "새 작품", status: .play,
                                     unit: .route, curText: "2", totalText: "6", memo: "다음 루트"))
        XCTAssertEqual(shared.load()?.items.first?.progressText, "2 / 6 루트")
        let reloaded = Store(baseURL: temporaryDirectory, widgetStore: shared, defaults: defaults, reloadWidget: {})
        XCTAssertEqual(reloaded.items, store.items)
        XCTAssertEqual(shared.load(), WidgetSnapshot(items: reloaded.items))
    }

    func testWidgetTapOpensExistingRecordAndDeletedRecordFallsBackHome() {
        let nav = Nav()
        let anime = item("anime")
        nav.open(.item(anime.id), items: [anime])
        XCTAssertEqual(nav.page, Category.anime.pageIndex)
        XCTAssertEqual(nav.editor?.itemID, anime.id)
        nav.open(.item("deleted"), items: [anime])
        XCTAssertEqual(nav.page, 2)
        XCTAssertNil(nav.editor)
    }

    func testRenderWidgetSizesForVisualReview() throws {
        for (family, width, height, name) in [
            (WidgetFamily.systemSmall, 158.0, 158.0, "widget-small"),
            (.systemMedium, 338.0, 158.0, "widget-medium"),
            (.systemLarge, 338.0, 354.0, "widget-large")
        ] {
            let renderer = ImageRenderer(content:
                ProgressWidgetView(entry: ProgressEntry(date: Date(), snapshot: .preview))
                    .environment(\.widgetFamily, family)
                    .padding(14)
                    .frame(width: width, height: height)
                    .background(Color(red: 0.115, green: 0.13, blue: 0.19))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            )
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
