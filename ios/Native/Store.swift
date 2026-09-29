import SwiftUI
import UIKit
import WidgetKit
import OSLog

struct ToastInfo: Identifiable {
    let id = UUID()
    let message: String
    let undoItems: [Item]?
}

struct SealInfo: Identifiable {
    let id = UUID()
    let text: String
    let title: String
}

enum BgSlot: String {
    case home
    case cat

    var name: String {
        return self == BgSlot.home ? "홈 화면" : "분류 화면"
    }
}

struct EditorInput {
    var existingID: String?
    var cat: Category
    var title: String
    var status: ItemStatus
    var unit: ItemUnit
    var curText: String
    var totalText: String
    var memo: String
}

/// 기록과 배경 사진을 앱 안 파일로 저장하고, 모든 작품 변경을 여기서 처리한다
final class Store: ObservableObject {
    @Published var items: [Item] = []
    @Published var toast: ToastInfo?
    @Published var seal: SealInfo?
    @Published var homeBg: UIImage?
    @Published var catBg: UIImage?
    @Published var homeThumb: UIImage?
    @Published var catThumb: UIImage?
    @Published var homeDim: Double = 0.5
    @Published var catDim: Double = 0.5

    private let base: URL
    private let dir: URL
    private let defaults: UserDefaults
    private let widgetStore: WidgetSnapshotStore
    private let reloadWidget: () -> Void
    private var toastWork: DispatchWorkItem?
    private var sealWork: DispatchWorkItem?

    init(baseURL: URL? = nil, widgetStore: WidgetSnapshotStore = WidgetSnapshotStore(),
         defaults: UserDefaults = .standard,
         reloadWidget: @escaping () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.kind) }) {
        let support = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.defaults = defaults
        self.widgetStore = widgetStore
        self.reloadWidget = reloadWidget
        self.base = support
        self.dir = support.appendingPathComponent("NelNoteNative", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.dir, withIntermediateDirectories: true)

        let fresh = !FileManager.default.fileExists(atPath: itemsURL.path)
        if fresh {
            migrateFromWebVersion()
        } else {
            loadItems()
        }
        loadBackground(BgSlot.home)
        loadBackground(BgSlot.cat)
        loadDims()
        syncWidget()
    }

    // MARK: 파일 위치

    private var itemsURL: URL {
        return dir.appendingPathComponent("items.json")
    }

    private func bgURL(_ slot: BgSlot) -> URL {
        return dir.appendingPathComponent("bg_" + slot.rawValue + ".jpg")
    }

    // MARK: 조회

    func list(_ cat: Category, _ status: ItemStatus) -> [Item] {
        let matched = items.filter { $0.cat == cat && $0.status == status }
        return matched.sorted { $0.statusAt > $1.statusAt }
    }

    func countStatus(_ status: ItemStatus) -> Int {
        return items.filter { $0.status == status }.count
    }

    func countCategory(_ cat: Category) -> Int {
        return items.filter { $0.cat == cat }.count
    }

    func countWaiting(_ cat: Category) -> Int {
        return items.filter { $0.cat == cat && $0.status == ItemStatus.wait }.count
    }

    func item(withID id: String) -> Item? {
        return items.first(where: { $0.id == id })
    }

    // MARK: 저장과 불러오기

    private func loadItems() {
        guard let data = try? Data(contentsOf: itemsURL) else { return }
        if let parsed = Store.parseItems(data) {
            items = parsed
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        do {
            try data.write(to: itemsURL, options: .atomic)
            syncWidget()
        } catch {
            Logger(subsystem: "com.nelnote.app", category: "storage").error("Could not save items: \(error.localizedDescription, privacy: .public)")
        }
    }

    func syncWidget() {
        do {
            if try widgetStore.save(WidgetSnapshot(items: items)) {
                reloadWidget()
            }
        } catch {
            Logger(subsystem: "com.nelnote.app", category: "widget").error("Could not update widget: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func parseItems(_ data: Data) -> [Item]? {
        let decoder = JSONDecoder()
        var lossy: [LossyItem]? = nil
        if let backup = try? decoder.decode(LossyBackup.self, from: data) {
            lossy = backup.items
        } else if let array = try? decoder.decode([LossyItem].self, from: data) {
            lossy = array
        }
        guard let list = lossy else { return nil }
        var seen = Set<String>()
        var result: [Item] = []
        for entry in list {
            if let item = entry.value, !item.title.isEmpty, !seen.contains(item.id) {
                seen.insert(item.id)
                result.append(item)
            }
        }
        return result
    }

    /// 웹뷰 버전 IPA로 쌓은 기록과 배경 사진을 이어받는다 (같은 앱 이름으로 덮어 설치한 경우)
    private func migrateFromWebVersion() {
        let old = base.appendingPathComponent("NelNote", isDirectory: true)
        if let data = try? Data(contentsOf: old.appendingPathComponent("dojang.json")),
           let parsed = Store.parseItems(data) {
            items = parsed
            save()
        }
        for slot in [BgSlot.home, BgSlot.cat] {
            let url = old.appendingPathComponent("bg_" + slot.rawValue + ".txt")
            if let text = try? String(contentsOf: url, encoding: .utf8),
               let comma = text.firstIndex(of: ",") {
                let payload = String(text[text.index(after: comma)...])
                if let bytes = Data(base64Encoded: payload) {
                    _ = setBackground(slot, data: bytes)
                }
            }
        }
        if let data = try? Data(contentsOf: old.appendingPathComponent("prefs.json")),
           let prefs = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] {
            if let text = prefs["dim_home"], let percent = Double(text) {
                defaults.set(percent / 100.0, forKey: "dim_home")
            }
            if let text = prefs["dim_cat"], let percent = Double(text) {
                defaults.set(percent / 100.0, forKey: "dim_cat")
            }
        }
    }

    // MARK: 알림

    func showToast(_ message: String, undo: [Item]?) {
        let info = ToastInfo(message: message, undoItems: undo)
        toast = info
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.toast?.id == info.id {
                self.toast = nil
            }
        }
        toastWork = work
        let delay: Double = (undo == nil) ? 2.8 : 5.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func dismissToast() {
        toastWork?.cancel()
        toast = nil
    }

    func celebrate(_ item: Item) {
        let info = SealInfo(text: item.cat.seal, title: clip(item.title, 24))
        seal = info
        sealWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.seal?.id == info.id {
                self.seal = nil
            }
        }
        sealWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: 진행 상태 바꾸기

    private func incMessage(_ item: Item) -> String {
        let name = clip(item.title, 16)
        switch item.effectiveUnit {
        case .some(.ep): return "\(name) \(item.cur)화까지 봤어요"
        case .some(.route): return "\(name) 루트 \(item.cur)개 클리어"
        case .some(.vol): return "\(name) \(item.cur)권까지 읽었어요"
        default: return "저장했어요"
        }
    }

    private func doneMessage(_ item: Item) -> String {
        return clip(item.title, 16) + " 완료! 완료 목록으로 옮겼어요"
    }

    func increment(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        if item.status == ItemStatus.done { return }
        let before = items
        let now = nowMs()
        let totalCount = item.total ?? 0
        if totalCount == 0 || item.cur < totalCount {
            item.cur += 1
        }
        if item.status == ItemStatus.wait {
            item.setStatus(ItemStatus.play, at: now)
        }
        var finished = false
        if totalCount > 0 && item.cur >= totalCount {
            item.cur = totalCount
            finished = item.setStatus(ItemStatus.done, at: now)
        }
        item.updated = now
        items[index] = item
        save()
        showToast(finished ? doneMessage(item) : incMessage(item), undo: before)
        if finished {
            celebrate(item)
        }
    }

    func finish(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        let before = items
        let now = nowMs()
        if !item.setStatus(ItemStatus.done, at: now) { return }
        item.updated = now
        items[index] = item
        save()
        showToast(doneMessage(item), undo: before)
        celebrate(item)
    }

    func start(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[index]
        let before = items
        let now = nowMs()
        if !item.setStatus(ItemStatus.play, at: now) { return }
        item.updated = now
        items[index] = item
        save()
        showToast(clip(item.title, 16) + " 시작했어요", undo: before)
    }

    func undo(_ snapshot: [Item]) {
        items = snapshot
        save()
        showToast("되돌렸어요", undo: nil)
    }

    func delete(_ id: String) {
        let before = items
        let name = item(withID: id).map { clip($0.title, 16) + " " } ?? ""
        items.removeAll(where: { $0.id == id })
        save()
        showToast(name + "삭제했어요", undo: before)
    }

    /// 추가·수정 창에서 저장 (웹 버전과 같은 규칙)
    func saveEditor(_ input: EditorInput) {
        let before = items
        let now = nowMs()
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let memo = input.memo.trimmingCharacters(in: .whitespacesAndNewlines)

        var hasUnit = true
        var unit: ItemUnit? = nil
        switch input.cat {
        case .game:
            hasUnit = false
        case .anime:
            unit = ItemUnit.ep
        case .vn:
            unit = ItemUnit.route
        case .book:
            unit = input.unit
        }

        var total = 0
        var cur = 0
        if hasUnit {
            total = Int(input.totalText) ?? 0
            cur = Int(input.curText) ?? 0
            if total > 0 && cur > total {
                cur = total
            }
        }

        var savedItem: Item? = nil
        var becameDone = false
        var message = "저장했어요"

        if let existingID = input.existingID, let index = items.firstIndex(where: { $0.id == existingID }) {
            var item = items[index]
            var nextStatus = input.status
            // 진행중인 작품을 끝까지 기록하면 +1 버튼처럼 바로 완료 처리
            if nextStatus == ItemStatus.play && total > 0 && cur >= total && item.cur < total {
                nextStatus = ItemStatus.done
            }
            item.title = title
            item.memo = memo
            item.cur = cur
            item.total = total > 0 ? total : nil
            if item.cat == Category.book {
                item.unit = input.unit
            }
            let changed = item.setStatus(nextStatus, at: now)
            becameDone = changed && nextStatus == ItemStatus.done
            item.updated = now
            items[index] = item
            savedItem = item
        } else {
            let item = Item(
                id: UUID().uuidString,
                cat: input.cat,
                title: title,
                status: input.status,
                cur: cur,
                total: total > 0 ? total : nil,
                unit: input.cat == Category.book ? input.unit : nil,
                memo: memo,
                created: now,
                statusAt: now,
                doneAt: input.status == ItemStatus.done ? now : nil,
                updated: now
            )
            items.append(item)
            savedItem = item
            message = clip(title, 16) + " 추가했어요"
        }

        save()
        if becameDone, let item = savedItem {
            showToast(doneMessage(item), undo: before)
            celebrate(item)
        } else {
            showToast(message, undo: before)
        }
    }

    // MARK: 백업

    func backupText() -> String {
        let file = BackupFile(app: "nelnote", v: 1, exportedAt: ISO8601DateFormatter().string(from: Date()), items: items)
        guard let data = try? JSONEncoder().encode(file), let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    @discardableResult
    func importBackup(_ text: String) -> Int? {
        guard let data = text.data(using: .utf8), let parsed = Store.parseItems(data) else {
            return nil
        }
        let before = items
        items = parsed
        save()
        showToast("작품 \(parsed.count)개를 불러왔어요", undo: before)
        return parsed.count
    }

    // MARK: 배경 사진

    func background(_ slot: BgSlot) -> UIImage? {
        return slot == BgSlot.home ? homeBg : catBg
    }

    func thumbnail(_ slot: BgSlot) -> UIImage? {
        return slot == BgSlot.home ? homeThumb : catThumb
    }

    func dim(_ slot: BgSlot) -> Double {
        return slot == BgSlot.home ? homeDim : catDim
    }

    func setDim(_ slot: BgSlot, _ value: Double) {
        let clamped = min(0.9, max(0, value))
        if slot == BgSlot.home {
            homeDim = clamped
        } else {
            catDim = clamped
        }
        defaults.set(clamped, forKey: "dim_" + slot.rawValue)
    }

    private func loadDims() {
        if let value = defaults.object(forKey: "dim_home") as? Double {
            homeDim = value
        }
        if let value = defaults.object(forKey: "dim_cat") as? Double {
            catDim = value
        }
    }

    private func loadBackground(_ slot: BgSlot) {
        if let data = try? Data(contentsOf: bgURL(slot)), let image = UIImage(data: data) {
            applyBackground(slot, image)
        }
    }

    private func applyBackground(_ slot: BgSlot, _ image: UIImage?) {
        let thumb = image.map { Store.downscaled($0, maxSide: 240) }
        if slot == BgSlot.home {
            homeBg = image
            homeThumb = thumb
        } else {
            catBg = image
            catThumb = thumb
        }
    }

    /// 고른 사진을 화면에 맞게 줄여 JPEG로 저장한다 (사진 방향도 바로잡힘)
    func setBackground(_ slot: BgSlot, data: Data) -> Bool {
        guard let image = UIImage(data: data) else { return false }
        let scaled = Store.downscaled(image, maxSide: 2000)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.84) else { return false }
        do {
            try jpeg.write(to: bgURL(slot), options: .atomic)
        } catch {
            return false
        }
        applyBackground(slot, scaled)
        return true
    }

    func clearBackground(_ slot: BgSlot) {
        try? FileManager.default.removeItem(at: bgURL(slot))
        applyBackground(slot, nil)
    }

    static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longSide = max(size.width, size.height)
        if longSide <= 0 {
            return image
        }
        let ratio = min(1, maxSide / longSide)
        let target = CGSize(width: max(1, (size.width * ratio).rounded()), height: max(1, (size.height * ratio).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: CGPoint.zero, size: target))
        }
    }
}
