import XCTest
#if canImport(NelNote)
@testable import NelNote
#else
@testable import NelNoteSync
#endif

final class VaultSyncTests: XCTestCase {
    #if canImport(NelNote)
    private typealias Category = NelNote.Category
    #endif
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("nelnote-tests-" + UUID().uuidString)
        for cat in Category.allCases {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(cat.dbFolder), withIntermediateDirectories: true)
        }
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func item(_ cat: Category = .anime, title: String = "한글 작품: [특별편]", status: ItemStatus = .play) -> Item {
        let id = UUID().uuidString.lowercased()
        return Item(id: id, cat: cat, title: title, status: status, cur: 3, total: 12,
                    unit: cat == .book ? .page : nil, memo: "앱 전용 메모", created: 10,
                    statusAt: 20, doneAt: nil, updated: 30, nelnoteID: id)
    }
    private func write(_ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    private func read(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }

    // Exercise the real parser, planner and coordinated file implementation.
    private func cycle(_ items: inout [Item], _ state: inout VaultState) throws -> VaultRun {
        let files = VaultFiles(root: root)
        let plan = try files.prepare(items: items, state: state)
        XCTAssertTrue(plan.conflicts.isEmpty)
        var library = VaultLibrary(items: items, state: state)
        library.adopt(plan)
        let result = files.execute(plan)
        library.accept(result, snapshot: state)
        items = library.items; state = library.state
        return result
    }

    func testEveryCategoryAddsUpdatesAndDeletesBothWays() throws {
        for cat in Category.allCases {
            var items = [item(cat)]
            let original = items[0]
            var state = VaultState()
            XCTAssertNil(try cycle(&items, &state).error)
            let link = try XCTUnwrap(state.links[original.nelnoteID!])
            let raw = try read(link.path)
            XCTAssertTrue(raw.contains("## note\n- [[\(cat.notesFolder)/"))
            XCTAssertFalse(raw.contains(original.memo))
            XCTAssertFalse(raw.contains("\ncur:"))
            XCTAssertEqual(items[0].cur, 3)
            var fields = SyncFields(items[0]); fields.title = "Obsidian에서 바꾼 제목"; fields.status = .dropped
            let note = try VaultNote(path: link.path, category: cat, raw: raw, modified: 200)
            try write(link.path, note.replacing(with: fields, id: link.id))
            XCTAssertNil(try cycle(&items, &state).error)
            XCTAssertEqual(items[0].title, fields.title)
            XCTAssertEqual(items[0].status, .dropped)
            XCTAssertEqual(items[0].memo, original.memo)
            XCTAssertEqual(items[0].cur, original.cur)
            XCTAssertTrue(try read(link.path).contains("# " + original.title + "\n"))
            try FileManager.default.removeItem(at: root.appendingPathComponent(link.path))
            XCTAssertNil(try cycle(&items, &state).error)
            XCTAssertTrue(items.isEmpty)
            XCTAssertNotNil(state.tombstones[link.id])
        }
    }

    func testOnlyOwnedYAMLChangesAndBodyIsBytePreserved() throws {
        let raw = "\u{FEFF}---\r\ntitle: '제목: 하나' # 제목 주석\r\nstatus: watching\r\nepisodes:\r\ngenre:\r\n  - 일상\r\n  - 키라라\r\nstudio: [\"제작사 A\", \"제작사 B\"]\r\ncustom:\r\n  nested: true\r\n# 마지막 주석\r\n---\r\n# 원래 제목\r\n## note\r\n- [[Anime/notes/없는 노트|없는 노트]]\r\n본문 **그대로**\r\n"
        let id = UUID().uuidString.lowercased()
        let note = try VaultNote(path: "_db_anime/test.md", category: .anime, raw: raw, modified: 10)
        let next = try note.replacing(with: SyncFields(title: "바뀜 # ' \" : 한글", status: .nextCours, total: 24), id: id)
        XCTAssertTrue(next.contains(" # 제목 주석\r\n"))
        XCTAssertTrue(next.contains("genre:\r\n  - 일상\r\n  - 키라라\r\nstudio: [\"제작사 A\", \"제작사 B\"]\r\ncustom:\r\n  nested: true\r\n# 마지막 주석\r\n"))
        XCTAssertTrue(next.hasSuffix("# 원래 제목\r\n## note\r\n- [[Anime/notes/없는 노트|없는 노트]]\r\n본문 **그대로**\r\n"))
        let parsed = try VaultNote(path: note.path, category: .anime, raw: next, modified: 10)
        XCTAssertEqual(parsed.fields.total, 24)
        XCTAssertEqual(parsed.fields.status, .nextCours)
        XCTAssertEqual(try parsed.replacing(with: parsed.fields, id: id), next)
    }

    func testLatestFieldWinsAndIndependentChangesMergeIncludingEmptyTotal() {
        let base = SyncFields(title: "원래", status: .wait, total: 12)
        let app = SyncFields(title: "앱", status: .wait, total: nil)
        let remote = SyncFields(title: "노트", status: .play, total: 12)
        let newerApp = SyncFields.merge(local: app, remote: remote, base: base,
                                       times: ["title": 201], fallback: 0, remoteTime: 200)
        XCTAssertEqual(newerApp, SyncFields(title: "앱", status: .play, total: nil))
        let tied = SyncFields.merge(local: app, remote: remote, base: base,
                                   times: ["title": 200], fallback: 0, remoteTime: 200)
        XCTAssertEqual(tied.title, "노트")
        let clearedBase = SyncFields(title: "원래", status: .wait, total: nil)
        XCTAssertEqual(SyncFields.merge(local: base, remote: clearedBase, base: clearedBase,
                                       times: [:], fallback: 1, remoteTime: 200).total, 12)
    }

    func testTitleAndFilenameRenameKeepIdentityAndAppProgress() throws {
        var items = [item()]
        let id = items[0].id
        var state = VaultState()
        _ = try cycle(&items, &state)
        let link = state.links[items[0].nelnoteID!]!
        let newPath = "_db_anime/파일명 변경.md"
        try FileManager.default.moveItem(at: root.appendingPathComponent(link.path), to: root.appendingPathComponent(newPath))
        _ = try cycle(&items, &state)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, id)
        XCTAssertEqual(items[0].cur, 3)
        XCTAssertEqual(state.links[link.id]?.path, newPath)
    }

    func testAmbiguousTitlesNeedChoiceAndDuplicateIDsBlockAllWrites() throws {
        let first = item(title: "동명")
        let second = item(title: "동명")
        try write("_db_anime/a.md", "---\ntitle: 동명\nstatus: watching\n---\n")
        let files = VaultFiles(root: root)
        var state = VaultState()
        var plan = try files.prepare(items: [first, second], state: state)
        XCTAssertEqual(plan.conflicts.count, 1)
        XCTAssertTrue(plan.actions.isEmpty)
        state.choices["_db_anime/a.md"] = second.id
        plan = try files.prepare(items: [first, second], state: state)
        XCTAssertTrue(plan.conflicts.isEmpty)
        XCTAssertEqual(plan.actions.first(where: { $0.path == "_db_anime/a.md" })?.after?.id, second.id)
        let duplicated = VaultNote.newText(item: first, id: first.nelnoteID!)
        try write("_db_anime/a.md", duplicated)
        try write("_db_anime/b.md", duplicated)
        XCTAssertThrowsError(try files.prepare(items: [first], state: state))
    }

    func testTrashUndoRestoresUnknownPropertiesAndNeverDeletesLinkedNotes() throws {
        var items = [item(.book, title: "책")]
        let saved = items[0]
        var state = VaultState()
        _ = try cycle(&items, &state)
        let id = saved.nelnoteID!
        let path = state.links[id]!.path
        let original = try read(path).replacingOccurrences(of: "publisher: []", with: "publisher: [사용자 출판사]")
        try write(path, original)
        try write("Books/notes/책.md", "사용자 노트")
        state.deletions[saved.id] = VaultDeletion(item: saved, at: 100)
        items = []
        XCTAssertNil(try cycle(&items, &state).error)
        let trash = try XCTUnwrap(state.tombstones[id]?.trashPath)
        XCTAssertEqual(try read(trash), original)
        XCTAssertEqual(try read("Books/notes/책.md"), "사용자 노트")
        items = [saved]; state.restores[id] = 200
        XCTAssertNil(try cycle(&items, &state).error)
        XCTAssertEqual(try read(path), original)
        XCTAssertNil(state.tombstones[id])
        XCTAssertEqual(items[0].memo, saved.memo)
    }

    func testTombstonesPreventRemoteResurrection() throws {
        var items = [item()]
        var state = VaultState()
        _ = try cycle(&items, &state)
        let saved = items[0], link = state.links[items[0].nelnoteID!]!
        let text = try read(link.path)
        items = []; state.deletions[saved.id] = VaultDeletion(item: saved, at: 100)
        _ = try cycle(&items, &state)
        try write(link.path, text)
        _ = try cycle(&items, &state)
        XCTAssertTrue(items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(link.path).path))
    }

    func testInvalidReadMissingFolderAndBadYAMLDoNotDeleteAnything() throws {
        var items = [item()]
        var state = VaultState()
        _ = try cycle(&items, &state)
        let original = items
        try write("_db_book/bad.md", "---\ntitle: [\nstatus: reading\n---\n")
        XCTAssertThrowsError(try VaultFiles(root: root).prepare(items: items, state: state))
        XCTAssertEqual(items, original)
        try FileManager.default.removeItem(at: root.appendingPathComponent("_db_book/bad.md"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("_db_book"))
        XCTAssertThrowsError(try VaultFiles(root: root).prepare(items: items, state: state))
        XCTAssertEqual(items, original)
        for yaml in ["title: A\ntitle: B\nstatus: watching", "title: A\nstatus: unknown",
                     "title: A\nstatus: watching\nepisodes: -2", "title: A\nstatus: watching\nnelnote_id: invalid"] {
            XCTAssertThrowsError(try VaultNote(path: "bad.md", category: .anime, raw: "---\n" + yaml + "\n---\n", modified: 0))
        }
    }

    func testConcurrentWriteIsNotOverwrittenAndRetryMergesIt() throws {
        var items = [item()]
        var state = VaultState()
        _ = try cycle(&items, &state)
        let link = state.links[items[0].nelnoteID!]!
        items[0].title = "앱 수정"
        items[0].fieldTimes["title"] = nowMs() + 10_000
        let files = VaultFiles(root: root)
        let plan = try files.prepare(items: items, state: state)
        let changed = try read(link.path).replacingOccurrences(of: "genre: []", with: "genre: [키라라]")
        try write(link.path, changed)
        XCTAssertNotNil(files.execute(plan).error)
        XCTAssertEqual(try read(link.path), changed)
        XCTAssertNil(try cycle(&items, &state).error)
        XCTAssertTrue(try read(link.path).contains("genre: [키라라]"))
        XCTAssertEqual(items[0].title, "앱 수정")
    }

    func testFirstMergeAndBackupRestoreNeverPropagateEmptyListsAsDeletes() throws {
        var items = [item()]
        var state = VaultState()
        _ = try cycle(&items, &state)
        items = []; state.protectMissing = true
        _ = try cycle(&items, &state)
        XCTAssertEqual(items.count, 1)
        let path = state.links[items[0].nelnoteID!]!.path
        try FileManager.default.removeItem(at: root.appendingPathComponent(path))
        state.protectMissing = true
        _ = try cycle(&items, &state)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
    }

    func testUnrecordedProgressAndVolumeTotalsStayLocal() throws {
        try write("_db_book/import.md", "---\ntitle: 새 책\nstatus: completed\npages: 300\n---\n")
        var items: [Item] = [], state = VaultState()
        _ = try cycle(&items, &state)
        XCTAssertFalse(items[0].progressRecorded)
        XCTAssertFalse(items[0].statusDateRecorded)
        XCTAssertNil(items[0].doneAt)
        XCTAssertEqual(items[0].progressText, "진행 미기록")
        items[0].unit = .vol; items[0].bookPages = 300; items[0].total = 5; items[0].cur = 2
        _ = try cycle(&items, &state)
        XCTAssertTrue(try read("_db_book/import.md").contains("pages: 300"))
        XCTAssertEqual(items[0].total, 5)
        XCTAssertEqual(items[0].cur, 2)
    }

    func testThousandNotesAndIndexesAreHandled() throws {
        for index in 0..<1000 {
            try write("_db_anime/작품 \(index).md", "---\ntitle: 작품 \(index)\nstatus: wishlist\nepisodes:\ngenre: [일상, 키라라]\n---\n본문\n")
        }
        try write("_db_anime/anime-db-index.md", "# 인덱스\n")
        let start = Date()
        var items: [Item] = [], state = VaultState()
        XCTAssertNil(try cycle(&items, &state).error)
        XCTAssertEqual(items.count, 1000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 30)
        XCTAssertEqual(try read("_db_anime/anime-db-index.md"), "# 인덱스\n")
    }

    func testOldBackupDecodesWithDefaultFields() throws {
        let json = """
        {"id":"old","cat":"ANIME","title":"예전 기록","status":"play","cur":3,"total":12,"memo":"보존","created":1,"statusAt":2,"updated":3}
        """
        let old = try JSONDecoder().decode(Item.self, from: Data(json.utf8))
        XCTAssertTrue(old.progressRecorded)
        XCTAssertEqual(old.memo, "보존")
        XCTAssertNil(old.nelnoteID)
        XCTAssertEqual(old.cur, 3)
    }
    func testExistingVaultReadOnlyWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["NELNOTE_AUDIT_VAULT"] else {
            throw XCTSkip("Optional read-only audit")
        }
        let plan = try VaultFiles(root: URL(fileURLWithPath: path)).prepare(items: [], state: VaultState())
        XCTAssertTrue(plan.conflicts.isEmpty)
        print("READ-ONLY VAULT AUDIT: \(plan.actions.count) DB records parsed; no files written.")
    }

    func testPendingExportsSurviveWriteFailureAndRelaunch() throws {
        let local = item()
        var library = VaultLibrary(items: [local], state: VaultState(protectMissing: false))
        let files = VaultFiles(root: root)
        let snapshot = library.state
        let plan = try files.prepare(items: library.items, state: snapshot)
        library.adopt(plan)
        let path = try XCTUnwrap(plan.actions.first?.path)
        try write(path, "다른 사람이 만든 파일")
        let result = files.execute(plan)
        XCTAssertNotNil(result.error)
        library.accept(result, snapshot: snapshot)
        let data = try JSONEncoder().encode(StoredLibrary(items: library.items, vault: library.state))
        let loaded = try JSONDecoder().decode(StoredLibrary.self, from: data)
        XCTAssertTrue(try XCTUnwrap(loaded.vault.links[local.nelnoteID!]).pendingCreate)
        try FileManager.default.removeItem(at: root.appendingPathComponent(path))
        let retry = try files.prepare(items: loaded.items, state: loaded.vault)
        XCTAssertEqual(retry.actions.first?.after?.id, local.id)
        XCTAssertNil(files.execute(retry).error)
        XCTAssertTrue(try read(path).contains(local.nelnoteID!))
    }

    func testForegroundEditsDuringIOAndUndoDuringDeletionSurvive() throws {
        var items = [item()]
        var state = VaultState()
        _ = try cycle(&items, &state)
        let original = items[0]
        let id = original.nelnoteID!, path = state.links[id]!.path
        var remote = SyncFields(original); remote.title = "원격 제목"
        let note = try VaultNote(path: path, category: .anime, raw: read(path), modified: 100)
        try write(path, note.replacing(with: remote, id: id))
        let files = VaultFiles(root: root)
        let plan = try files.prepare(items: items, state: state)
        var library = VaultLibrary(items: items, state: state)
        library.adopt(plan)
        library.items[0].title = "작업 중 새 제목"
        library.items[0].cur = 7
        library.items[0].memo = "작업 중 새 메모"
        library.items[0].fieldTimes["title"] = nowMs()
        library.accept(files.execute(plan), snapshot: state)
        XCTAssertEqual(library.items[0].title, "작업 중 새 제목")
        XCTAssertEqual(library.items[0].cur, 7)
        XCTAssertEqual(library.items[0].memo, "작업 중 새 메모")

        library.state.deletions[original.id] = VaultDeletion(item: original, at: 100)
        library.items = []
        let deletionSnapshot = library.state
        let deletion = try files.prepare(items: [], state: deletionSnapshot)
        library.items = [original]
        library.state.deletions.removeValue(forKey: original.id)
        library.state.restores[id] = 200
        library.accept(files.execute(deletion), snapshot: deletionSnapshot)
        XCTAssertEqual(library.items.count, 1)
        XCTAssertNotNil(library.state.tombstones[id]?.trashPath)
        let restoredPlan = try files.prepare(items: library.items, state: library.state)
        let restoreSnapshot = library.state
        library.accept(files.execute(restoredPlan), snapshot: restoreSnapshot)
        XCTAssertEqual(library.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
    }

    func testFilesAppearingAfterScanCannotBeTreatedAsDeleted() throws {
        var items = [item()]
        var state = VaultState()
        _ = try cycle(&items, &state)
        let link = state.links[items[0].nelnoteID!]!
        let raw = try read(link.path)
        try FileManager.default.removeItem(at: root.appendingPathComponent(link.path))
        let files = VaultFiles(root: root)
        let plan = try files.prepare(items: items, state: state)
        try write("_db_anime/새 이름.md", raw)
        let result = files.execute(plan)
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.completed.isEmpty)
    }

    func testLongKoreanNamesAndAllStatusMappings() throws {
        XCTAssertLessThanOrEqual(VaultNote.safeName(String(repeating: "한", count: 200)).utf8.count, 240)
        XCTAssertEqual(VaultNote.safeName("CON"), "_CON")
        for category in Category.allCases {
            for status in category.statuses {
                XCTAssertEqual(try category.itemStatus(category.vaultStatus(status)), status)
            }
            if category != .anime { XCTAssertThrowsError(try category.itemStatus("next_cours")) }
        }
    }

    func testCaseInsensitiveFileNamesGetDistinctPaths() throws {
        let first = item(.game, title: "Portal")
        let second = item(.game, title: "portal")
        let plan = try VaultFiles(root: root).prepare(items: [first, second], state: VaultState())
        XCTAssertEqual(Set(plan.actions.map { $0.path.lowercased() }).count, 2)
        XCTAssertTrue(plan.actions.contains { $0.path.hasSuffix(" (2).md") })
    }

    func testPermissionRenewalRetainsPendingChangesAndAnotherVaultStartsSafely() throws {
        var items = [item(.book, title: "삭제 대기"), item(.anime, title: "노트에서 삭제")]
        var state = VaultState()
        state.connect(bookmark: Data([1]), name: "note", location: root.path)
        _ = try cycle(&items, &state)
        let deleting = items[0], remoteDeleted = items[1]
        let deletionPath = state.links[deleting.nelnoteID!]!.path
        let remotePath = state.links[remoteDeleted.nelnoteID!]!.path
        state.deletions[deleting.id] = VaultDeletion(item: deleting, at: 100)
        items.removeFirst()
        try FileManager.default.removeItem(at: root.appendingPathComponent(remotePath))

        // An expired bookmark survives a relaunch before the user picks the same folder.
        state = try JSONDecoder().decode(VaultState.self, from: JSONEncoder().encode(state))
        state.connect(bookmark: Data([2]), name: "note", location: root.path)
        XCTAssertNil(try cycle(&items, &state).error)
        XCTAssertTrue(items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(deletionPath).path))
        XCTAssertNotNil(state.tombstones[deleting.nelnoteID!]?.trashPath)
        XCTAssertNotNil(state.tombstones[remoteDeleted.nelnoteID!])

        state.connect(bookmark: Data([3]), name: "note", location: root.path + "-different")
        XCTAssertTrue(state.protectMissing)
        XCTAssertTrue(state.tombstones.isEmpty)
        XCTAssertTrue(state.links.isEmpty)
    }

    func testUnknownLegacyTotalsArePreserved() throws {
        for total in ["-1", "\"\"", "null", ""] {
            let raw = "---\ntitle: 미정\nstatus: next_cours\nepisodes: " + total + "\n---\n본문"
            let note = try VaultNote(path: "test.md", category: .anime, raw: raw, modified: 0)
            XCTAssertNil(note.fields.total)
            let linked = try note.replacing(with: note.fields, id: UUID().uuidString.lowercased())
            XCTAssertTrue(linked.contains("episodes: " + total + "\n"))
        }
    }

}
