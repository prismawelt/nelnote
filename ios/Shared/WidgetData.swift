import Foundation

/// Only a compact, read-only copy leaves the app's existing data directory.
struct WidgetItem: Codable, Identifiable, Equatable {
    let id: String
    let category: Category
    let title: String
    let memo: String
    let progressText: String
    let progress: Double?

    init(_ item: Item) {
        id = item.id
        category = item.cat
        title = item.title
        memo = item.memo
        progressText = item.progressText
        if item.effectiveUnit != nil, let total = item.total, total > 0 {
            progress = min(1, max(0, Double(item.cur) / Double(total)))
        } else {
            progress = nil
        }
    }

    var url: URL { WidgetLink.itemURL(id) }
}

struct WidgetSection: Identifiable {
    let category: Category
    let count: Int
    let items: [WidgetItem]
    var id: Category { category }
}

struct WidgetSnapshot: Codable, Equatable {
    let items: [WidgetItem]
    let categoryCounts: [String: Int]

    init(items: [Item]) {
        let playing = items.filter { $0.status == .play }.sorted {
            if $0.updated != $1.updated { return $0.updated > $1.updated }
            if $0.statusAt != $1.statusAt { return $0.statusAt > $1.statusAt }
            return $0.id < $1.id
        }
        categoryCounts = Dictionary(uniqueKeysWithValues: Category.allCases.map { cat in
            (cat.rawValue, playing.filter { $0.cat == cat }.count)
        })
        // Keep enough rows per category for every supported widget size.
        self.items = Category.allCases.flatMap { cat in
            playing.filter { $0.cat == cat }.prefix(4).map(WidgetItem.init)
        }
    }

    var totalCount: Int { categoryCounts.values.reduce(0, +) }

    /// Reserve one row per category before filling spare rows.
    func sections(limit: Int) -> [WidgetSection] {
        guard limit > 0 else { return [] }
        let groups = Category.allCases.compactMap { cat -> WidgetSection? in
            let rows = items.filter { $0.category == cat }
            guard !rows.isEmpty else { return nil }
            return WidgetSection(category: cat, count: categoryCounts[cat.rawValue] ?? rows.count, items: rows)
        }
        let visible = Array(groups.prefix(limit))
        var counts = Array(repeating: 1, count: visible.count)
        var remaining = limit - visible.count
        for index in visible.indices {
            let extra = min(remaining, visible[index].items.count - 1)
            counts[index] += extra
            remaining -= extra
        }
        return visible.enumerated().map { index, section in
            WidgetSection(category: section.category, count: section.count,
                          items: Array(section.items.prefix(counts[index])))
        }
    }

    static let empty = WidgetSnapshot(items: [])
}

enum WidgetLink: Equatable {
    case home
    case item(String)

    static let homeURL = URL(string: "nelnote://home")!

    static func itemURL(_ id: String) -> URL {
        var components = URLComponents()
        components.scheme = "nelnote"
        components.host = "item"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url!
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "nelnote",
              components.user == nil, components.password == nil, components.port == nil,
              components.path.isEmpty || components.path == "/" else { return nil }
        switch components.host {
        case "home":
            self = .home
        case "item":
            guard let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
                  !id.isEmpty else { return nil }
            self = .item(id)
        default:
            return nil
        }
    }
}

struct WidgetSnapshotStore {
    static let kind = "NelNoteProgress"
    let directory: URL?

    init(directory: URL? = WidgetSnapshotStore.sharedDirectory) {
        self.directory = directory
    }

    static var sharedDirectory: URL? {
        let configured = Bundle.main.object(forInfoDictionaryKey: "NelNoteAppGroup") as? String
            ?? "group.com.nelnote.app"
        // AltStore records the actual group after re-signing with a different team.
        let resigned = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        let candidates = resigned.filter { $0.contains(configured) } + [configured]
        for identifier in candidates {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
                return url
            }
        }
        return nil
    }

    private var fileURL: URL? {
        directory?.appendingPathComponent("widget-progress.json")
    }

    func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// A successful atomic write is the only point at which the timeline may refresh.
    @discardableResult
    func save(_ snapshot: WidgetSnapshot) throws -> Bool {
        guard let url = fileURL else { return false }
        if load() == snapshot { return false }
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }
}
