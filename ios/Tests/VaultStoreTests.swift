import XCTest
@testable import NelNote

final class VaultStoreTests: XCTestCase {
    private var root: URL!
    private var store: Store!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = Store(baseURL: root, widgetStore: WidgetSnapshotStore(directory: nil), reloadWidget: {})
    }
    override func tearDownWithError() throws {
        store.obsidian.cancel()
        store = nil
        try FileManager.default.removeItem(at: root)
    }

    func testFieldClocksOnlyTrackSyncedFieldsAndUnknownProgressCanBecomeZero() throws {
        let id = UUID().uuidString.lowercased()
        let item = Item(id: id, cat: .book, title: "책", status: .play, cur: 0, total: 300, unit: .page,
                        memo: "", created: 1, statusAt: 0, doneAt: nil, updated: 1,
                        progressRecorded: false, statusDateRecorded: false, nelnoteID: id)
        _ = store.importBackup(String(decoding: try JSONEncoder().encode([item]), as: UTF8.self))
        store.updateBookProgress(id, current: 0)
        XCTAssertTrue(try XCTUnwrap(store.item(withID: id)).progressRecorded)
        store.saveEditor(EditorInput(existingID: id, cat: .book, title: "새 제목", status: .play,
                                     unit: .page, curText: "0", totalText: "300", memo: "메모"))
        let clocks = try XCTUnwrap(store.item(withID: id)).fieldTimes
        XCTAssertNotNil(clocks["title"])
        XCTAssertNil(clocks["status"])
        store.updateBookProgress(id, current: 12)
        XCTAssertEqual(store.item(withID: id)?.fieldTimes, clocks)
        store.finish(id)
        XCTAssertEqual(store.item(withID: id)?.cur, 300)
        XCTAssertNotNil(store.item(withID: id)?.fieldTimes["status"])
        let loaded = Store(baseURL: root, widgetStore: WidgetSnapshotStore(directory: nil), reloadWidget: {})
        XCTAssertEqual(loaded.items, store.items)
    }

    func testDeletionJournalSurvivesRelaunchAndUndoDoesNotRemoveLaterImports() throws {
        store.saveEditor(EditorInput(existingID: nil, cat: .game, title: "삭제 테스트", status: .play,
                                     unit: .page, curText: "", totalText: "", memo: "유지"))
        let original = store.items[0]
        store.vaultState.bookmark = Data("test bookmark".utf8)
        store.delete(original.id)
        XCTAssertNotNil(store.vaultState.deletions[original.id])
        let before = try XCTUnwrap(store.toast?.undoItems)
        let loaded = Store(baseURL: root, widgetStore: WidgetSnapshotStore(directory: nil), reloadWidget: {})
        XCTAssertNotNil(loaded.vaultState.deletions[original.id])
        var imported = original
        imported.id = UUID().uuidString.lowercased(); imported.nelnoteID = imported.id; imported.title = "동기화로 들어온 작품"
        store.items.append(imported)
        _ = store.save(trackChanges: false)
        store.undo(before)
        XCTAssertEqual(Set(store.items.map(\.title)), ["삭제 테스트", "동기화로 들어온 작품"])
        XCTAssertNil(store.vaultState.deletions[original.id])
        XCTAssertNotNil(store.vaultState.restores[original.nelnoteID!])
    }

    func testBackupReplacementDoesNotQueueDeletionsOrLoseConnection() throws {
        store.saveEditor(EditorInput(existingID: nil, cat: .anime, title: "남겨둘 노트", status: .wait,
                                     unit: .ep, curText: "", totalText: "12", memo: ""))
        store.vaultState.bookmark = Data("test bookmark".utf8)
        let bookmark = store.vaultState.bookmark
        XCTAssertEqual(store.importBackup("[]"), 0)
        XCTAssertTrue(store.vaultState.deletions.isEmpty)
        XCTAssertTrue(store.vaultState.protectMissing)
        XCTAssertEqual(store.vaultState.bookmark, bookmark)
    }

    func testWidgetDoesNotInventProgressForImportedNotes() {
        let item = Item(id: "import", cat: .anime, title: "가져온 작품", status: .play, cur: 0, total: 12,
                        unit: nil, memo: "", created: 1, statusAt: 0, doneAt: nil, updated: 1,
                        progressRecorded: false, statusDateRecorded: false)
        let snapshot = WidgetSnapshot(items: [item])
        XCTAssertEqual(snapshot.items.first?.progressText, "진행 미기록")
        XCTAssertNil(snapshot.items.first?.progress)
        var dropped = item; dropped.status = .dropped
        var next = item; next.status = .nextCours
        XCTAssertEqual(WidgetSnapshot(items: [dropped, next]).totalCount, 0)
    }
}
