import Foundation

// MARK: - 도구 함수

func nowMs() -> Int64 {
    return Int64(Date().timeIntervalSince1970 * 1000)
}

func clip(_ text: String, _ limit: Int) -> String {
    if text.count <= limit {
        return text
    }
    return String(text.prefix(limit - 1)) + "…"
}

/// 상태가 바뀐 날부터 며칠째인지 (당일이 1일째)
func dayCount(_ ms: Int64) -> Int {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(ms) / 1000))
    let today = calendar.startOfDay(for: Date())
    let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
    return max(1, days + 1)
}

func shortDate(_ ms: Int64) -> String {
    let date = Date(timeIntervalSince1970: Double(ms) / 1000)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
    formatter.dateFormat = sameYear ? "M월 d일" : "yyyy년 M월 d일"
    return formatter.string(from: date)
}

// MARK: - 분류, 상태, 단위

enum Category: String, Codable, CaseIterable, Identifiable {
    case game = "GAME"
    case anime = "ANIME"
    case vn = "VN"
    case book = "BOOK"

    var id: String { return rawValue }

    var label: String {
        switch self {
        case .game: return "GAME"
        case .anime: return "ANIME"
        case .vn: return "V-NOVEL"
        case .book: return "BOOK"
        }
    }

    var seal: String {
        switch self {
        case .game: return "CLEAR"
        case .anime: return "완주"
        case .vn: return "올클"
        case .book: return "완독"
        }
    }

    var emptyPlaying: String {
        switch self {
        case .game: return "진행 중인 게임이 없어요"
        case .anime: return "보고 있는 애니가 없어요"
        case .vn: return "진행 중인 미연시가 없어요"
        case .book: return "읽고 있는 책이 없어요"
        }
    }

    var noneText: String {
        switch self {
        case .game: return "아직 등록한 게임이 없어요."
        case .anime: return "아직 등록한 애니가 없어요."
        case .vn: return "아직 등록한 미연시가 없어요."
        case .book: return "아직 등록한 책이 없어요."
        }
    }

    var addText: String {
        switch self {
        case .game: return "게임 추가"
        case .anime: return "애니 추가"
        case .vn: return "미연시 추가"
        case .book: return "책 추가"
        }
    }

    var titlePlaceholder: String {
        switch self {
        case .game: return "게임 제목"
        case .anime: return "애니 제목"
        case .vn: return "미연시 제목"
        case .book: return "책 제목"
        }
    }

    var memoPlaceholder: String {
        switch self {
        case .game: return "예: 2회차, DLC 남음"
        case .anime: return "예: 2기, 라프텔"
        case .vn: return "예: 다음은 히로인 B 루트"
        case .book: return "예: 전자책, 도서관 반납 10/15"
        }
    }

    /// 하단 탭에서 이 분류가 차지하는 자리 (0 게임, 1 애니, 2 홈, 3 미연시, 4 책)
    var pageIndex: Int {
        switch self {
        case .game: return 0
        case .anime: return 1
        case .vn: return 3
        case .book: return 4
        }
    }

    static func forPage(_ index: Int) -> Category {
        switch index {
        case 0: return .game
        case 1: return .anime
        case 3: return .vn
        default: return .book
        }
    }
}

enum ItemStatus: String, Codable, Hashable {
    case wait
    case play
    case done

    var label: String {
        switch self {
        case .wait: return "대기중"
        case .play: return "진행중"
        case .done: return "완료"
        }
    }
}

enum ItemUnit: String, Codable, Hashable {
    case ep
    case route
    case page
    case vol

    var short: String {
        switch self {
        case .ep: return "화"
        case .route: return "루트"
        case .page: return "p"
        case .vol: return "권"
        }
    }

    var gap: String {
        return self == .route ? " " : ""
    }

    var curLabel: String {
        switch self {
        case .ep: return "본 화수"
        case .route: return "클리어한 루트"
        case .page: return "읽은 페이지"
        case .vol: return "읽은 권수"
        }
    }

    var totalLabel: String {
        switch self {
        case .ep: return "전체 화수"
        case .route: return "전체 루트"
        case .page: return "전체 페이지"
        case .vol: return "전체 권수"
        }
    }
}

// MARK: - 작품

enum QuickAction {
    case finish
    case inc
    case log
}

struct QuickInfo {
    let action: QuickAction
    let label: String
}

/// 저장 형식은 웹·안드로이드 앱의 백업과 같아서 서로 불러올 수 있다
struct Item: Codable, Identifiable, Equatable {
    var id: String
    var cat: Category
    var title: String
    var status: ItemStatus
    var cur: Int
    var total: Int?
    var unit: ItemUnit?
    var memo: String
    var created: Int64
    var statusAt: Int64
    var doneAt: Int64?
    var updated: Int64

    enum CodingKeys: String, CodingKey {
        case id, cat, title, status, cur, total, unit, memo, created, statusAt, doneAt, updated
    }

    /// 실제로 쓰는 진행 단위 (게임은 없음)
    var effectiveUnit: ItemUnit? {
        switch cat {
        case .game: return nil
        case .anime: return ItemUnit.ep
        case .vn: return ItemUnit.route
        case .book: return unit == ItemUnit.vol ? ItemUnit.vol : ItemUnit.page
        }
    }

    var progressText: String {
        guard let u = effectiveUnit else { return "" }
        let totalCount = total ?? 0
        if totalCount > 0 {
            return "\(cur) / \(totalCount)\(u.gap)\(u.short)"
        }
        if cur > 0 {
            return "\(cur)\(u.gap)\(u.short)"
        }
        return ""
    }

    var quick: QuickInfo? {
        if status != ItemStatus.play {
            return nil
        }
        if cat == Category.game {
            return QuickInfo(action: .finish, label: "완료")
        }
        if cat == Category.book {
            return QuickInfo(action: .finish, label: "완독")
        }
        return QuickInfo(action: .inc, label: "+1")
    }

    @discardableResult
    mutating func setStatus(_ next: ItemStatus, at time: Int64) -> Bool {
        if status == next {
            return false
        }
        status = next
        statusAt = time
        doneAt = (next == ItemStatus.done) ? time : nil
        return true
    }
}

extension Item {
    /// 빠진 값이 있는 백업도 최대한 읽는다
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let now = nowMs()
        let category = try c.decode(Category.self, forKey: .cat)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        cat = category
        title = ((try? c.decode(String.self, forKey: .title)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        status = (try? c.decode(ItemStatus.self, forKey: .status)) ?? ItemStatus.wait

        var curValue = max(0, (try? c.decode(Int.self, forKey: .cur)) ?? 0)
        var totalValue: Int? = try? c.decodeIfPresent(Int.self, forKey: .total)
        if let t = totalValue, t <= 0 {
            totalValue = nil
        }
        if let t = totalValue, curValue > t {
            curValue = t
        }
        cur = curValue
        total = totalValue

        if category == Category.book {
            let raw: ItemUnit? = try? c.decodeIfPresent(ItemUnit.self, forKey: .unit)
            unit = (raw == ItemUnit.vol) ? ItemUnit.vol : ItemUnit.page
        } else {
            unit = nil
        }

        memo = (try? c.decode(String.self, forKey: .memo)) ?? ""
        created = (try? c.decode(Int64.self, forKey: .created)) ?? now
        statusAt = (try? c.decode(Int64.self, forKey: .statusAt)) ?? now
        doneAt = try? c.decodeIfPresent(Int64.self, forKey: .doneAt)
        updated = (try? c.decode(Int64.self, forKey: .updated)) ?? now
    }
}

// MARK: - 백업 파일

struct BackupFile: Codable {
    var app: String
    var v: Int
    var exportedAt: String
    var items: [Item]
}

struct LossyItem: Decodable {
    let value: Item?

    init(from decoder: Decoder) throws {
        value = try? Item(from: decoder)
    }
}

struct LossyBackup: Decodable {
    let items: [LossyItem]
}
