import SwiftUI
import UIKit

// MARK: - 화면 이동 상태

struct EditorRequest: Identifiable {
    let id = UUID()
    var itemID: String?
    var category: Category
    var status: ItemStatus
    var focusCur: Bool = false
}

/// 현재 페이지(0 게임, 1 애니, 2 홈, 3 미연시, 4 책)와 열려 있는 창을 들고 있다
final class Nav: ObservableObject {
    @Published var page: Int = 2
    @Published var editor: EditorRequest?
    @Published var showSettings = false

    func go(_ index: Int) {
        guard (0..<5).contains(index), page != index else { return }
        page = index
    }

    func open(_ link: WidgetLink, items: [Item]) {
        switch link {
        case .home:
            page = 2
            editor = nil
        case .item(let id):
            guard let item = items.first(where: { $0.id == id }) else {
                page = 2
                editor = nil
                return
            }
            page = item.cat.pageIndex
            editor = EditorRequest(itemID: item.id, category: item.cat, status: item.status)
        }
    }
}

// MARK: - 모눈종이

struct GridShape: Shape {
    let step: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if step <= 0 {
            return path
        }
        var x: CGFloat = 0
        while x <= rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
            y += step
        }
        return path
    }
}

// MARK: - 캐릭터 원형 배지 (앱 아이콘과 같은 구도)

struct CharacterBadge: View {
    let size: CGFloat
    var imageOffsetY: CGFloat = 0

    var body: some View {
        Circle()
            .fill(LinearGradient(
                colors: [Color(UIColor(hex: 0xDDEBF8)), Color(UIColor(hex: 0xAACAEA))],
                startPoint: .top,
                endPoint: .bottom
            ))
            .frame(width: size, height: size)
            .overlay(GridShape(step: size * 0.15).stroke(Color.white.opacity(0.3), lineWidth: 1))
            .overlay {
                // An overlay cannot enlarge the badge's layout frame. Its center
                // stays fixed while the character peeks up inside the circle.
                Image("nel")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 1.5, height: size * 1.5)
                    .offset(y: imageOffsetY)
            }
            .clipShape(Circle())
    }
}

// MARK: - NEL NOTE 글자 로고 (선으로 그린 글자, 둥근 끝, O 안에 빨간 점)

struct WordmarkLetter: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch index {
        case 0: // N
            p.move(to: CGPoint(x: 0, y: 20))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 13, y: 20))
            p.addLine(to: CGPoint(x: 13, y: 0))
        case 1: // E
            p.move(to: CGPoint(x: 30.5, y: 0))
            p.addLine(to: CGPoint(x: 20, y: 0))
            p.addLine(to: CGPoint(x: 20, y: 20))
            p.addLine(to: CGPoint(x: 30.5, y: 20))
            p.move(to: CGPoint(x: 20, y: 10))
            p.addLine(to: CGPoint(x: 28.5, y: 10))
        case 2: // L
            p.move(to: CGPoint(x: 37.5, y: 0))
            p.addLine(to: CGPoint(x: 37.5, y: 20))
            p.addLine(to: CGPoint(x: 47.5, y: 20))
        case 3: // N
            p.move(to: CGPoint(x: 62.5, y: 20))
            p.addLine(to: CGPoint(x: 62.5, y: 0))
            p.addLine(to: CGPoint(x: 75.5, y: 20))
            p.addLine(to: CGPoint(x: 75.5, y: 0))
        case 4: // O
            p.addEllipse(in: CGRect(x: 82, y: -0.4, width: 20.8, height: 20.8))
        case 5: // T
            p.move(to: CGPoint(x: 108.8, y: 0))
            p.addLine(to: CGPoint(x: 120.8, y: 0))
            p.move(to: CGPoint(x: 114.8, y: 0))
            p.addLine(to: CGPoint(x: 114.8, y: 20))
        default: // E
            p.move(to: CGPoint(x: 138.3, y: 0))
            p.addLine(to: CGPoint(x: 127.8, y: 0))
            p.addLine(to: CGPoint(x: 127.8, y: 20))
            p.addLine(to: CGPoint(x: 138.3, y: 20))
            p.move(to: CGPoint(x: 127.8, y: 10))
            p.addLine(to: CGPoint(x: 136.3, y: 10))
        }
        let scale = min(rect.width / 142.3, rect.height / 24.4)
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: 2, y: 2.2)
        return p.applying(transform)
    }
}

struct Wordmark: View {
    let height: CGFloat
    var drawn: Bool = true
    var dotShown: Bool = true
    var animated: Bool = false

    private var scale: CGFloat { return height / 24.4 }
    private var width: CGFloat { return 142.3 * scale }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<7, id: \.self) { i in
                letter(i)
            }
            Circle()
                .fill(Theme.seal)
                .frame(width: 6 * scale, height: 6 * scale)
                .scaleEffect(dotShown ? 1 : 0.01)
                .offset(x: (92.4 + 2 - 3) * scale, y: (10 + 2.2 - 3) * scale)
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    private func letter(_ i: Int) -> some View {
        let style = StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round, lineJoin: .round)
        let timing: Animation? = animated ? Animation.easeInOut(duration: 0.38).delay(0.52 + 0.07 * Double(i)) : nil
        return WordmarkLetter(index: i)
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(Theme.ink, style: style)
            .frame(width: width, height: height)
            .animation(timing, value: drawn)
    }
}

// MARK: - 작은 도장 (완료 목록 표시)

struct SealMini: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .foregroundColor(Theme.seal)
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(Theme.seal, lineWidth: 2))
            .overlay(Circle().stroke(Theme.seal, lineWidth: 1).padding(4))
            .rotationEffect(.degrees(-14))
            .opacity(0.88)
    }
}

struct DockPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

// MARK: - 도장 칸과 진행 막대

struct StampDot: View {
    /// 0 빈 칸, 1 찍힌 칸, 2 다음 칸
    let kind: Int
    let ink: Color

    var body: some View {
        ZStack {
            if kind == 1 {
                Circle().fill(ink)
                Circle().stroke(Theme.card, lineWidth: 1.5).padding(2.5)
            } else {
                Circle().strokeBorder(kind == 2 ? ink : Theme.slot, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
            }
        }
        .frame(width: 18, height: 18)
    }
}

struct ProgressVisual: View {
    let item: Item

    private var cur: Int { return item.cur }
    private var total: Int { return item.total ?? 0 }
    private var isPage: Bool { return item.effectiveUnit == ItemUnit.page }

    private var showStamps: Bool {
        if item.effectiveUnit == nil { return false }
        if isPage { return false }
        if total > 30 { return false }
        if total == 0 && cur >= 30 { return false }
        return true
    }

    private var showBar: Bool {
        return item.effectiveUnit != nil && total > 0 && !showStamps
    }

    var body: some View {
        VStack(spacing: 0) {
            if showStamps {
                stamps
            } else if showBar {
                bar
            }
        }
    }

    private var stamps: some View {
        let count = total > 0 ? total : cur + 1
        let columns = [GridItem(.adaptive(minimum: 18, maximum: 18), spacing: 5)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                StampDot(kind: kindOf(i), ink: item.cat.ink)
            }
        }
        .padding(.top, 10)
    }

    private func kindOf(_ i: Int) -> Int {
        if i < cur { return 1 }
        if i == cur && item.status != ItemStatus.done { return 2 }
        return 0
    }

    private var bar: some View {
        let ratio = min(1.0, max(0.0, Double(cur) / Double(max(1, total))))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.rule2)
                Capsule().fill(item.cat.ink).frame(width: geo.size.width * CGFloat(ratio))
            }
        }
        .frame(height: 6)
        .padding(.top, 12)
    }
}

/// iOS 16-compatible tab shape: the lower corners meet the section rule squarely.
struct CategoryTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight],
                          cornerRadii: CGSize(width: 7, height: 7)).cgPath)
    }
}
