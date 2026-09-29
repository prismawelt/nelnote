import Foundation

extension Category {
    var dbFolder: String {
        switch self {
        case .anime: return "_db_anime"
        case .game: return "_db_game"
        case .vn: return "_db_vnovel"
        case .book: return "_db_book"
        }
    }
    var notesFolder: String {
        switch self {
        case .anime: return "Anime/notes"
        case .game: return "Games/notes"
        case .vn: return "VNovel/notes"
        case .book: return "Books/notes"
        }
    }
    var totalKey: String? {
        switch self {
        case .anime: return "episodes"
        case .book: return "pages"
        default: return nil
        }
    }
    var statuses: [ItemStatus] {
        [.wait, .play, .done, .dropped] + (self == .anime ? [.nextCours] : [])
    }
    func vaultStatus(_ status: ItemStatus) -> String {
        switch status {
        case .wait: return "wishlist"
        case .play: return self == .anime ? "watching" : self == .book ? "reading" : "playing"
        case .done: return "completed"
        case .dropped: return "dropped"
        case .nextCours: return "next_cours"
        }
    }
    func itemStatus(_ text: String) throws -> ItemStatus {
        guard let value = statuses.first(where: { vaultStatus($0) == text }) else {
            throw VaultError.invalid("알 수 없는 상태: \(text)")
        }
        return value
    }
}

struct SyncFields: Codable, Equatable {
    var title: String
    var status: ItemStatus
    var total: Int?

    init(title: String, status: ItemStatus, total: Int?) {
        self.title = title; self.status = status; self.total = total
    }
    init(_ item: Item) {
        title = item.title
        status = item.status
        total = item.cat == .anime ? item.total
            : item.cat == .book ? (item.effectiveUnit == .vol ? item.bookPages : item.total) : nil
    }
    func applying(to input: Item, remoteTime: Int64) -> Item {
        var item = input
        item.title = title
        if item.status != status {
            item.status = status
            item.statusAt = 0
            item.statusDateRecorded = false
            item.doneAt = nil
        }
        if item.cat == .anime || (item.cat == .book && item.effectiveUnit != .vol) {
            item.total = total
        } else if item.cat == .book {
            item.bookPages = total
        }
        if SyncFields(input) != self { item.updated = max(item.updated, remoteTime) }
        return item
    }
    static func merge(local: SyncFields, remote: SyncFields, base: SyncFields?,
                      times: [String: Int64], fallback: Int64, remoteTime: Int64) -> SyncFields {
        func choose<T: Equatable>(_ key: String, _ local: T, _ remote: T, _ original: T?) -> T {
            if let original {
                if local == original { return remote }
                if remote == original { return local }
            }
            return (times[key] ?? fallback) > remoteTime ? local : remote
        }
        return SyncFields(
            title: choose("title", local.title, remote.title, base?.title),
            status: choose("status", local.status, remote.status, base?.status),
            total: choose("total", local.total, remote.total, base.map { $0.total })
        )
    }
}

struct VaultLink: Codable, Equatable {
    var id: String
    var itemID: String
    var category: Category
    var path: String
    var baseline: SyncFields
    var pendingCreate = false
}

struct VaultDeletion: Codable, Equatable {
    var item: Item
    var at: Int64
}

struct VaultTombstone: Codable, Equatable {
    var id: String
    var itemID: String
    var path: String
    var trashPath: String?
    var at: Int64
}

struct VaultState: Codable, Equatable {
    var bookmark: Data? = nil
    var name: String? = nil
    var links: [String: VaultLink] = [:]
    var deletions: [String: VaultDeletion] = [:]
    var tombstones: [String: VaultTombstone] = [:]
    var restores: [String: Int64] = [:]
    var choices: [String: String] = [:]
    var protectMissing = true
    var lastSync: Date? = nil
    var lastResult: String? = nil
}

struct StoredLibrary: Codable {
    var items: [Item]
    var vault: VaultState
}

struct VaultConflict: Identifiable {
    var path: String
    var title: String
    var category: Category
    var candidates: [Item]
    var id: String { path }
}

enum VaultError: LocalizedError {
    case invalid(String)
    case changed(String)
    case permission
    var errorDescription: String? {
        switch self {
        case .invalid(let text): return text
        case .changed(let path): return "\(path): 동기화 중 파일이 바뀌었습니다. 다시 시도합니다."
        case .permission: return "보관함에 접근할 수 없습니다. Obsidian 보관함 폴더를 다시 선택해 주세요."
        }
    }
}
