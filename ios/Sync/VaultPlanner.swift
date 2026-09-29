import Foundation

struct VaultAction {
    var before: Item?
    var after: Item?
    var source: VaultNote?
    var path: String
    var text: String?
    var link: VaultLink?
    var tombstone: VaultTombstone?
    var restoreFrom: String? = nil
}

struct VaultPlan {
    var actions: [VaultAction] = []
    var conflicts: [VaultConflict] = []
    var expectedPaths: Set<String>? = nil
}

/// Pure three-way merge. No file writes happen until the entire vault has been
/// read, validated and matched, including duplicate IDs and ambiguous titles.
enum VaultPlanner {
    static func make(items: [Item], state: VaultState, notes: [VaultNote],
                     restored: [String: VaultNote] = [:], time: Int64) throws -> VaultPlan {
        var plan = VaultPlan()
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var bySyncID: [String: Item] = [:]
        for item in items {
            if let id = item.nelnoteID {
                guard bySyncID[id] == nil else { throw VaultError.invalid("앱 목록에 중복된 작품 ID가 있습니다.") }
                bySyncID[id] = item
            }
        }
        var seenIDs = Set<String>()
        for note in notes {
            if let id = note.id, !seenIDs.insert(id).inserted {
                throw VaultError.invalid("\(note.path): nelnote_id가 다른 파일과 중복됩니다. 복사한 DB의 ID를 지운 뒤 다시 동기화해 주세요.")
            }
        }
        let linksByPath = Dictionary(grouping: state.links.values, by: \.path)
        func identity(_ note: VaultNote) -> String? {
            note.id ?? linksByPath[note.path]?.first(where: { !seenIDs.contains($0.id) })?.id
        }
        func boundItem(_ note: VaultNote) -> Item? {
            guard let id = identity(note) else { return nil }
            return state.links[id].flatMap { itemsByID[$0.itemID] } ?? bySyncID[id]
        }
        var claimed = Set(notes.compactMap { boundItem($0)?.id })
        var matchedNotes = Set<String>()
        var occupied = Set(notes.map { $0.path.lowercased() })
        let titleGroups = Dictionary(grouping: notes, by: { $0.category.rawValue + "\u{0}" + $0.fields.title })
        let appTitleGroups = Dictionary(grouping: items.filter { !claimed.contains($0.id) },
                                        by: { $0.cat.rawValue + "\u{0}" + $0.title })

        func availablePath(_ item: Item, preferred: String? = nil) -> String {
            if let preferred, !preferred.isEmpty, !occupied.contains(preferred.lowercased()) { occupied.insert(preferred.lowercased()); return preferred }
            let stem = item.cat.dbFolder + "/" + VaultNote.safeName(item.title)
            var path = stem + ".md"
            var suffix = 2
            while occupied.contains(path.lowercased()) {
                path = stem + " (\(suffix)).md"; suffix += 1
            }
            occupied.insert(path.lowercased())
            return path
        }

        for note in notes.sorted(by: { $0.path < $1.path }) {
            let originalID = identity(note)
            if let id = originalID, let tombstone = state.tombstones[id], state.restores[id] == nil {
                plan.actions.append(VaultAction(before: boundItem(note), after: nil, source: note,
                    path: note.path, text: nil, link: nil, tombstone: tombstone))
                matchedNotes.insert(id)
                continue
            }
            var local = boundItem(note)
            if let id = originalID, let link = state.links[id], link.category != note.category {
                throw VaultError.invalid("\(note.path): 연결된 작품의 분류가 달라졌습니다. 원래 DB 폴더로 옮겨 주세요.")
            }
            if local == nil, let id = originalID,
               let deletion = state.deletions.values.first(where: { $0.item.nelnoteID == id }),
               state.restores[id] == nil {
                let tombstone = VaultTombstone(id: id, itemID: deletion.item.id, path: note.path,
                                              trashPath: nil, at: deletion.at)
                plan.actions.append(VaultAction(before: nil, after: nil, source: note, path: note.path,
                                               text: nil, link: nil, tombstone: tombstone))
                matchedNotes.insert(id)
                continue
            }
            if local == nil {
                let key = note.category.rawValue + "\u{0}" + note.fields.title
                let candidates = (appTitleGroups[key] ?? []).filter { !claimed.contains($0.id) }
                if let choice = state.choices[note.path], choice != "new" {
                    if let selected = candidates.first(where: { $0.id == choice }) { local = selected }
                    else if !candidates.isEmpty {
                        plan.conflicts.append(VaultConflict(path: note.path, title: note.fields.title,
                                                           category: note.category, candidates: candidates))
                        continue
                    }
                } else if state.choices[note.path] != "new" && !candidates.isEmpty {
                    if candidates.count == 1 && titleGroups[key]?.count == 1 {
                        local = candidates[0]
                    } else {
                        plan.conflicts.append(VaultConflict(path: note.path, title: note.fields.title,
                                                           category: note.category, candidates: candidates))
                        continue
                    }
                }
            }
            let id = originalID ?? local?.nelnoteID ?? UUID().uuidString.lowercased()
            guard !matchedNotes.contains(id) else {
                throw VaultError.invalid("\(note.path): 하나의 작품이 여러 DB 파일에 연결되어 있습니다.")
            }
            matchedNotes.insert(id)
            let before = local
            var item: Item
            if var local {
                guard local.cat == note.category else {
                    throw VaultError.invalid("\(note.path): 앱과 보관함의 작품 분류가 다릅니다.")
                }
                claimed.insert(local.id)
                let merged = SyncFields.merge(local: SyncFields(local), remote: note.fields,
                    base: state.links[id]?.baseline, times: local.fieldTimes,
                    fallback: local.updated, remoteTime: note.modified)
                local = merged.applying(to: local, remoteTime: note.modified)
                local.nelnoteID = id
                item = local
            } else {
                let itemID = state.links[id]?.itemID ?? id
                guard itemsByID[itemID] == nil else {
                    throw VaultError.invalid("\(note.path): 작품 ID가 다른 앱 기록과 충돌합니다.")
                }
                item = Item(id: itemID, cat: note.category, title: note.fields.title,
                    status: note.fields.status, cur: 0, total: note.fields.total,
                    unit: note.category == .book ? .page : nil, memo: "", created: note.modified,
                    statusAt: 0, doneAt: nil, updated: note.modified,
                    progressRecorded: false, statusDateRecorded: false, nelnoteID: id)
            }
            let fields = SyncFields(item)
            let text = try note.replacing(with: fields, id: id)
            let link = VaultLink(id: id, itemID: item.id, category: note.category,
                                 path: note.path, baseline: fields)
            plan.actions.append(VaultAction(before: before, after: item, source: note, path: note.path,
                                           text: text, link: link, tombstone: nil))
        }
        guard plan.conflicts.isEmpty else { return VaultPlan(actions: [], conflicts: plan.conflicts) }

        for item in items where !claimed.contains(item.id) {
            guard let id = item.nelnoteID else {
                throw VaultError.invalid("작품 ID를 준비하지 못했습니다. 다시 동기화해 주세요.")
            }
            if matchedNotes.contains(id) { continue }
            let link = state.links[id]
            let isRestore = state.restores[id] != nil
            if !isRestore, let tombstone = state.tombstones[id] {
                plan.actions.append(VaultAction(before: item, after: nil, source: nil, path: tombstone.path,
                                               text: nil, link: nil, tombstone: tombstone))
            } else if !isRestore, let link, !link.pendingCreate, !state.protectMissing {
                let tombstone = VaultTombstone(id: id, itemID: item.id, path: link.path,
                                              trashPath: nil, at: time)
                plan.actions.append(VaultAction(before: item, after: nil, source: nil, path: link.path,
                                               text: nil, link: nil, tombstone: tombstone))
            } else {
                let path = availablePath(item, preferred: link?.path ?? state.tombstones[id]?.path)
                let archived = restored[id]
                let text = try archived?.replacing(with: SyncFields(item), id: id)
                    ?? VaultNote.newText(item: item, id: id)
                let newLink = VaultLink(id: id, itemID: item.id, category: item.cat,
                                       path: path, baseline: SyncFields(item))
                plan.actions.append(VaultAction(before: item, after: item, source: nil, path: path,
                    text: text, link: newLink, tombstone: nil, restoreFrom: archived?.path))
            }
        }
        for deletion in state.deletions.values {
            guard let id = deletion.item.nelnoteID, !matchedNotes.contains(id),
                  state.restores[id] == nil else { continue }
            let tombstone = state.tombstones[id] ?? VaultTombstone(id: id, itemID: deletion.item.id,
                path: state.links[id]?.path ?? "", trashPath: nil, at: deletion.at)
            plan.actions.append(VaultAction(before: nil, after: nil, source: nil, path: tombstone.path,
                                           text: nil, link: nil, tombstone: tombstone))
        }
        return plan
    }
}
