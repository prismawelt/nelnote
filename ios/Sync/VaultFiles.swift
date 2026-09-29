import Foundation

struct VaultRun {
    var completed: [VaultAction] = []
    var error: String?
}

/// All methods are synchronous and called exclusively on the connection's serial
/// worker queue. iOS file-provider access is coordinated, including preconditions.
final class VaultFiles {
    let root: URL
    private let fm = FileManager.default

    init(root: URL) { self.root = root.standardizedFileURL }

    private func url(_ path: String) throws -> URL {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.isEmpty else {
            throw VaultError.invalid("보관함 밖의 경로에는 접근할 수 없습니다.")
        }
        let file = root.appendingPathComponent(path)
        let base = root.resolvingSymlinksInPath().path + "/"
        guard file.resolvingSymlinksInPath().path.hasPrefix(base) else {
            throw VaultError.invalid("\(path): 보관함 밖을 가리키는 링크입니다.")
        }
        return file
    }

    private func coordinate<T>(_ file: URL, writing: Bool = false, _ body: (URL) throws -> T) throws -> T {
        #if os(iOS) || os(macOS)
        var error: NSError?
        var result: Result<T, Error>?
        let accessor: (URL) -> Void = { url in result = Result { try body(url) } }
        let coordinator = NSFileCoordinator()
        if writing {
            coordinator.coordinate(writingItemAt: file, options: .forReplacing, error: &error, byAccessor: accessor)
        } else {
            coordinator.coordinate(readingItemAt: file, options: [], error: &error, byAccessor: accessor)
        }
        if let error { throw error }
        guard let result else { throw VaultError.permission }
        return try result.get()
        #else
        return try body(file)
        #endif
    }

    private struct Stamp: Equatable {
        var modified: Date
        var size: Int
    }

    private func inventory() throws -> [String: Stamp] {
        var files: [String: Stamp] = [:]
        for category in Category.allCases {
            let folder = try url(category.dbFolder)
            try coordinate(folder) { folder in
                let info = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard info.isDirectory == true, info.isSymbolicLink != true else {
                    throw VaultError.invalid("\(category.dbFolder) 폴더를 확인해 주세요. 네 DB가 들어 있는 보관함 전체를 선택해야 합니다.")
                }
                var scanError: Error?
                guard let enumerator = fm.enumerator(at: folder,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                                                 .contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles], errorHandler: { _, error in scanError = error; return false }) else {
                    throw VaultError.permission
                }
                while let file = enumerator.nextObject() as? URL {
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                                                                 .contentModificationDateKey, .fileSizeKey])
                    guard values.isSymbolicLink != true else {
                        throw VaultError.invalid("\(file.lastPathComponent): DB 폴더의 심볼릭 링크는 지원하지 않습니다.")
                    }
                    guard file.pathExtension.lowercased() == "md" else { continue }
                    if values.isDirectory == true { continue }
                    guard values.isRegularFile == true else {
                        throw VaultError.invalid("\(file.lastPathComponent): 파일 종류를 확인하지 못했습니다.")
                    }
                    let indexNames = ["anime-db-index.md", "vnovel-db-index.md", "game-db-index.md", "book-db-index.md"]
                    if indexNames.contains(file.lastPathComponent.lowercased()) { continue }
                    guard let modified = values.contentModificationDate, let size = values.fileSize else {
                        throw VaultError.invalid("\(file.lastPathComponent): 파일 정보를 읽지 못했습니다.")
                    }
                    let relative = category.dbFolder + "/" + file.path.dropFirst(folder.path.count + 1)
                    files[relative] = Stamp(modified: modified, size: size)
                }
                if let scanError { throw scanError }
            }
        }
        return files
    }

    func validateAccess() throws { _ = try inventory() }

    private func read(_ path: String, category: Category) throws -> VaultNote {
        try coordinate(url(path)) { file in
            let data = try Data(contentsOf: file)
            guard let raw = String(data: data, encoding: .utf8) else {
                throw VaultError.invalid("\(path): UTF-8 파일이 아닙니다.")
            }
            let attributes = try fm.attributesOfItem(atPath: file.path)
            guard let date = attributes[.modificationDate] as? Date else { throw VaultError.permission }
            return try VaultNote(path: path, category: category, raw: raw,
                                 modified: Int64(date.timeIntervalSince1970 * 1000))
        }
    }

    func prepare(items: [Item], state: VaultState, time: Int64 = nowMs()) throws -> VaultPlan {
        let before = try inventory()
        var notes: [VaultNote] = []
        for path in before.keys.sorted() {
            guard let category = Category.allCases.first(where: { path.hasPrefix($0.dbFolder + "/") }) else { continue }
            notes.append(try read(path, category: category))
        }
        // A changing/incomplete enumeration is never evidence of deletion.
        guard before == (try inventory()) else { throw VaultError.changed("보관함") }
        var restored: [String: VaultNote] = [:]
        for id in state.restores.keys {
            if let tombstone = state.tombstones[id], let path = tombstone.trashPath,
               let category = state.links[id]?.category {
                restored[id] = try read(path, category: category)
            }
        }
        var plan = try VaultPlanner.make(items: items, state: state, notes: notes, restored: restored, time: time)
        plan.expectedPaths = Set(before.keys)
        return plan
    }

    func execute(_ plan: VaultPlan, isCancelled: () -> Bool = { false }) -> VaultRun {
        var result = VaultRun()
        var expectedPaths = plan.expectedPaths
        var checkedMissing = false
        guard plan.conflicts.isEmpty else { return result }
        for var action in plan.actions {
            if isCancelled() { result.error = "동기화를 중단했습니다."; break }
            do {
                if action.text == nil && action.source == nil && !checkedMissing {
                    if let expectedPaths, Set(try inventory().keys) != expectedPaths {
                        throw VaultError.changed("보관함")
                    }
                    checkedMissing = true
                }
                if let text = action.text {
                    if action.source == nil, let category = action.after?.cat {
                        let folder = try url(category.notesFolder)
                        try coordinate(folder, writing: true) { folder in
                            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                        }
                    }
                    let file = try url(action.path)
                    try coordinate(file, writing: true) { file in
                        let current = fm.fileExists(atPath: file.path) ? try String(contentsOf: file, encoding: .utf8) : nil
                        guard current == action.source?.raw || current == text else {
                            throw VaultError.changed(action.path)
                        }
                        if current != text { try Data(text.utf8).write(to: file, options: .atomic) }
                    }
                    expectedPaths?.insert(action.path)
                } else if let note = action.source {
                    var tombstone = action.tombstone!
                    let source = try url(note.path)
                    let trashPath = ".trash/nelnote/" + tombstone.id + "/" + UUID().uuidString + "/" + note.path
                    let destination = try url(trashPath)
                    try coordinate(destination.deletingLastPathComponent(), writing: true) { folder in
                        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    }
                    try moveToTrash(source: source, destination: destination, expected: note.raw)
                    tombstone.trashPath = trashPath
                    action.tombstone = tombstone
                    expectedPaths?.remove(note.path)
                }
                result.completed.append(action)
            } catch {
                result.error = error.localizedDescription
                break
            }
        }
        return result
    }

    private func moveToTrash(source: URL, destination: URL, expected: String) throws {
        func move(_ from: URL, _ to: URL) throws {
            guard try String(contentsOf: from, encoding: .utf8) == expected else {
                throw VaultError.changed(source.lastPathComponent)
            }
            try fm.moveItem(at: from, to: to)
        }
        #if os(iOS) || os(macOS)
        var error: NSError?
        var outcome: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: source, options: .forMoving,
            writingItemAt: destination, options: .forReplacing, error: &error) { from, to in
                outcome = Result { try move(from, to) }
            }
        if let error { throw error }
        guard let outcome else { throw VaultError.permission }
        try outcome.get()
        #else
        try move(source, destination)
        #endif
    }
}
