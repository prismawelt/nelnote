import Foundation
import Yams

/// Parse with YAML, but edit only the owned source ranges. Never serialize the
/// whole document: Obsidian lists, comments, links and body text keep their bytes.
struct VaultNote {
    let path: String
    let category: Category
    let raw: String
    let modified: Int64
    let id: String?
    let fields: SyncFields
    private let lines: [String]
    private let closing: Int
    private let ranges: [String: Range<Int>]

    init(path: String, category: Category, raw: String, modified: Int64) throws {
        self.path = path; self.category = category; self.raw = raw; self.modified = modified
        let lines = raw.utf8.split(separator: 10, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        self.lines = lines
        guard lines.first?.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let closing = lines.indices.dropFirst().first(where: {
                  ["---", "..."].contains(lines[$0].trimmingCharacters(in: .whitespacesAndNewlines))
              }) else { throw VaultError.invalid("\(path): YAML 속성 영역을 읽을 수 없습니다.") }
        self.closing = closing
        let yaml = lines[1..<closing].joined(separator: "\n")
        let node: Node
        do {
            guard let parsed = try Yams.compose(yaml: yaml) else {
                throw VaultError.invalid("빈 YAML")
            }
            node = parsed
        } catch { throw VaultError.invalid("\(path): YAML 오류 — \(error.localizedDescription)") }
        guard case .mapping(let mapping) = node, mapping.style != .flow else {
            throw VaultError.invalid("\(path): 속성은 한 줄에 하나씩 적어 주세요.")
        }
        var values: [String: Node] = [:]
        var keys: [(String, Int)] = []
        for pair in mapping {
            guard let key = pair.key.string, pair.key.mark?.column == 1, key != "<<",
                  values[key] == nil, let line = pair.key.mark?.line else {
                throw VaultError.invalid("\(path): 중복되거나 지원하지 않는 YAML 속성이 있습니다.")
            }
            values[key] = pair.value
            keys.append((key, line))
        }
        var blocks: [String: Range<Int>] = [:]
        for (index, key) in keys.enumerated() {
            var end = index + 1 < keys.count ? keys[index + 1].1 : closing
            while end > key.1 + 1 {
                let line = lines[end - 1]
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || line.hasPrefix("#") { end -= 1 }
                else { break }
            }
            blocks[key.0] = key.1..<end
        }
        ranges = blocks
        guard let title = values["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty, values["title"]?.null == nil,
              let status = values["status"]?.string else {
            throw VaultError.invalid("\(path): title과 status가 필요합니다.")
        }
        let parsedStatus: ItemStatus
        do { parsedStatus = try category.itemStatus(status) }
        catch { throw VaultError.invalid("\(path): \(error.localizedDescription)") }
        var total: Int?
        if let key = category.totalKey, let value = values[key], value.null == nil {
            guard let scalar = value.scalar?.string else {
                throw VaultError.invalid("\(path): \(key)는 정수 또는 빈 값이어야 합니다.")
            }
            // Older Anime DB templates used -1 for an unannounced episode count.
            // Treat that sentinel and quoted blanks as unknown without rewriting them.
            if scalar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scalar == "-1" {
                total = nil
            } else {
                guard scalar.utf8.allSatisfy({ (48...57).contains($0) }), let count = Int(scalar) else {
                    throw VaultError.invalid("\(path): \(key)는 0 이상의 정수 또는 빈 값이어야 합니다.")
                }
                total = count > 0 ? count : nil
            }
        }
        if let value = values["nelnote_id"], value.null == nil {
            guard let text = value.string, let uuid = UUID(uuidString: text) else {
                throw VaultError.invalid("\(path): nelnote_id가 올바른 UUID가 아닙니다.")
            }
            id = uuid.uuidString.lowercased()
        } else { id = nil }
        fields = SyncFields(title: title, status: parsedStatus, total: total)
    }

    func replacing(with fields: SyncFields, id: String) throws -> String {
        var updates: [String: String] = [:]
        if self.fields.title != fields.title { updates["title"] = Self.quoted(fields.title) }
        if self.fields.status != fields.status { updates["status"] = Self.quoted(category.vaultStatus(fields.status)) }
        if self.fields.total != fields.total, let key = category.totalKey {
            updates[key] = fields.total.map(String.init) ?? ""
        }
        if self.id != id { updates["nelnote_id"] = Self.quoted(id) }
        guard !updates.isEmpty else { return raw }
        var result = lines
        let carriage = lines.first?.hasSuffix("\r") == true ? "\r" : ""
        let existing = updates.keys.compactMap { key -> (String, Range<Int>)? in
            ranges[key].map { (key, $0) }
        }.sorted { $0.1.lowerBound > $1.1.lowerBound }
        // Insert missing keys first so original source ranges remain valid.
        let added = updates.keys.filter { ranges[$0] == nil }.sorted().map {
            $0 + ":" + (updates[$0]!.isEmpty ? "" : " " + updates[$0]!) + carriage
        }
        result.insert(contentsOf: added, at: closing)
        for (key, range) in existing {
            let comment = Self.inlineComment(lines[range.lowerBound])
            let value = updates[key]!
            let replacement = key + ":" + (value.isEmpty ? "" : " " + value) + comment + carriage
            result.replaceSubrange(range, with: [replacement])
        }
        let text = result.joined(separator: "\n")
        // Reject transformations that would break aliases or YAML syntax.
        let check = try VaultNote(path: path, category: category, raw: text, modified: modified)
        guard check.fields == fields, check.id == id else {
            throw VaultError.invalid("\(path): 속성을 안전하게 수정할 수 없습니다.")
        }
        return text
    }

    private static func inlineComment(_ line: String) -> String {
        var quote: Character?
        var escaped = false
        var previous: Character = " "
        for index in line.indices {
            let c = line[index]
            if escaped { escaped = false; previous = c; continue }
            if c == "\\" && quote == "\"" { escaped = true; previous = c; continue }
            if let current = quote {
                if c == current { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "#" && previous.isWhitespace {
                return " " + line[index...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            previous = c
        }
        return ""
    }

    static func quoted(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    static func safeName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|#^[]").union(.controlCharacters)
        let cleaned = String(value.unicodeScalars.map { invalid.contains($0) ? "_" : String($0) }.joined().prefix(120))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[. ]+$", with: "", options: .regularExpression)
        var shortened = ""
        for character in cleaned {
            if shortened.utf8.count + String(character).utf8.count > 240 { break }
            shortened.append(character)
        }
        let name = shortened.isEmpty ? "작품" : shortened
        let reserved = name.range(of: "^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\\.|$)",
                                  options: [.regularExpression, .caseInsensitive]) != nil
        return reserved ? "_" + name : name
    }

    static func newText(item: Item, id: String) -> String {
        let fields = SyncFields(item)
        var properties = [
            "title: " + quoted(fields.title),
            "status: " + quoted(item.cat.vaultStatus(fields.status))
        ]
        switch item.cat {
        case .anime:
            properties += ["year:", "episodes:" + (fields.total.map { " \($0)" } ?? ""),
                           "genre: []", "studio: []", "director: []", "rating:", "tier:",
                           "series:", "season:", "type:", "image:"]
        case .game:
            properties += ["release_date:", "series:", "developer: []", "genre: []",
                           "platform: []", "rating:", "tier:", "image:"]
        case .vn:
            properties += ["release_date:", "series:", "studio: []", "genre: []",
                           "platform: []", "rating:", "tier:", "image:"]
        case .book:
            properties += ["author: []", "publisher: []", "published_date:", "translator: []",
                           "series:", "volume:", "genre: []",
                           "pages:" + (fields.total.map { " \($0)" } ?? ""), "rating:", "tier:", "image:"]
        }
        properties.append("nelnote_id: " + quoted(id))
        let label = fields.title.replacingOccurrences(of: "|", with: "｜")
            .replacingOccurrences(of: "[", with: "［").replacingOccurrences(of: "]", with: "］")
        return "---\n" + properties.joined(separator: "\n") + "\n---\n# " + fields.title
            + "\n## note\n- [[" + item.cat.notesFolder + "/" + safeName(fields.title) + "|" + label
            + "]]\n## writing\n## related\n"
    }
}
