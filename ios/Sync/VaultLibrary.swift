import Foundation

/// The same reducer is used by the app and tests. Merge into a local dictionary
/// first; publish a single array so importing 1,000 notes does not redraw 1,000 times.
struct VaultLibrary {
    var items: [Item]
    var state: VaultState

    mutating func adopt(_ plan: VaultPlan) {
        var identities: [String: String] = [:]
        for action in plan.actions {
            guard var link = action.link else { continue }
            if state.links[link.id] == nil {
                link.baseline = action.source?.fields ?? link.baseline
                link.pendingCreate = action.source == nil
                state.links[link.id] = link
            }
            identities[link.itemID] = link.id
        }
        items = items.map { original in
            var item = original
            if let id = identities[item.id] { item.nelnoteID = id }
            return item
        }
    }

    mutating func accept(_ run: VaultRun, snapshot: VaultState) {
        var order = items.map(\.id)
        var currentItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for action in run.completed {
            if let desired = action.after, let link = action.link {
                if var current = currentItems[desired.id], let before = action.before {
                    let old = SyncFields(before), remote = SyncFields(desired)
                    var merged = SyncFields(current)
                    if merged.title == old.title { merged.title = remote.title }
                    if merged.status == old.status { merged.status = remote.status }
                    if merged.total == old.total { merged.total = remote.total }
                    current = merged.applying(to: current, remoteTime: desired.updated)
                    current.nelnoteID = link.id
                    currentItems[desired.id] = current
                } else if action.before == nil, currentItems[desired.id] == nil,
                          state.deletions[desired.id] == nil {
                    currentItems[desired.id] = desired
                    order.append(desired.id)
                }
                state.links[link.id] = link
                if state.restores[link.id] == snapshot.restores[link.id] {
                    state.restores.removeValue(forKey: link.id)
                    state.tombstones.removeValue(forKey: link.id)
                }
            } else if let tombstone = action.tombstone {
                state.tombstones[tombstone.id] = tombstone
                if state.restores[tombstone.id] == nil {
                    currentItems.removeValue(forKey: tombstone.itemID)
                }
                if state.deletions[tombstone.itemID] == snapshot.deletions[tombstone.itemID] {
                    state.deletions.removeValue(forKey: tombstone.itemID)
                }
            }
        }
        items = order.compactMap { currentItems[$0] }
        if run.error == nil {
            state.protectMissing = false
            state.lastSync = Date()
        }
        state.lastResult = run.error ?? "작품 \(items.count)개 동기화 완료"
    }
}
