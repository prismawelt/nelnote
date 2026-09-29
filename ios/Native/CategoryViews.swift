import SwiftUI

// MARK: - 분류 화면 (진행중 / 대기중 / 완료)

struct CategoryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    let cat: Category
    @State private var doneOpen = false

    private var hasBackground: Bool { return store.catBg != nil }

    var body: some View {
        let playing = store.list(cat, ItemStatus.play)
        let waiting = store.list(cat, ItemStatus.wait)
        let done = store.list(cat, ItemStatus.done)
        let all = playing.count + waiting.count + done.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(all: all, playing: playing.count, done: done.count)
                if all == 0 {
                    emptyState
                } else {
                    sectionTitle("진행중", playing.count)
                    if playing.isEmpty {
                        note(waiting.isEmpty ? "진행 중인 작품이 없어요." : "대기 목록에서 시작 버튼을 누르면 여기로 올라와요.")
                    } else {
                        ForEach(playing) { item in
                            CardView(item: item, bordered: true)
                        }
                    }
                    sectionTitle("대기중", waiting.count)
                    if waiting.isEmpty {
                        note("대기 중인 작품이 없어요.")
                    } else {
                        listPanel(waiting)
                    }
                    if !done.isEmpty {
                        doneToggle(done.count)
                        if doneOpen {
                            listPanel(done)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 140)
        }
    }

    private func header(all: Int, playing: Int, done: Int) -> some View {
        let donePercent = all > 0 ? Int((Double(done) / Double(all) * 100).rounded()) : 0
        let playPercent = all > 0 ? Int((Double(playing) / Double(all) * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: 0) {
            Text(cat.label)
                .accessibilityIdentifier("category-\(cat.rawValue)")
                .font(.system(size: 42, weight: .heavy))
                .foregroundColor(cat.ink)
                .glow(hasBackground)
            if all > 0 {
                HStack {
                    Text("\(all)개 중 \(done)개 완료")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.ink2)
                    Spacer()
                    Text("\(donePercent)%")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Theme.ink)
                }
                .padding(.top, 12)
                .glow(hasBackground)
                RateBar(donePercent: donePercent, playPercent: playPercent, ink: cat.ink)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text(cat.noneText)
                .font(.system(size: 15))
                .foregroundColor(Theme.ink2)
            Button(action: {
                nav.editor = EditorRequest(itemID: nil, category: cat, status: ItemStatus.wait)
            }) {
                Text(cat.addText)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.paper)
                    .padding(.horizontal, 20)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cat.ink))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hasBackground ? Theme.paper.opacity(0.88) : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.rule, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .padding(.top, 26)
    }

    private func sectionTitle(_ title: String, _ count: Int) -> some View {
        return HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Theme.ink)
            Text("\(count)")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Theme.ink3)
            Spacer()
        }
        .padding(.horizontal, 2)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .glow(hasBackground)
    }

    private func note(_ text: String) -> some View {
        return Text(text)
            .font(.system(size: 14))
            .foregroundColor(Theme.ink3)
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
            .glow(hasBackground)
    }

    private func doneToggle(_ count: Int) -> some View {
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                doneOpen.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Text("완료")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.ink)
                Text("\(count)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.ink3)
                Spacer()
                Image(systemName: doneOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.ink3)
            }
            .padding(.horizontal, 2)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
        }
        .glow(hasBackground)
    }

    private func listPanel(_ list: [Item]) -> some View {
        return VStack(spacing: 0) {
            ForEach(list) { item in
                LineRow(item: item)
                Divider()
            }
        }
        .padding(.horizontal, hasBackground ? 12 : 2)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(hasBackground ? Theme.paper.opacity(0.88) : Color.clear)
        )
    }
}

struct RateBar: View {
    let donePercent: Int
    let playPercent: Int
    let ink: Color

    var body: some View {
        GeometryReader { geo in
            let doneWidth = geo.size.width * CGFloat(donePercent) / 100
            let playWidth = geo.size.width * CGFloat(playPercent) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.rule2)
                HStack(spacing: 0) {
                    Rectangle().fill(ink).frame(width: doneWidth)
                    Rectangle().fill(ink.opacity(0.38)).frame(width: playWidth)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 8)
    }
}

// MARK: - 대기중·완료 목록의 한 줄

struct LineRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    let item: Item

    private var subText: String {
        if item.status == ItemStatus.done {
            return shortDate(item.doneAt ?? item.statusAt) + " 완료"
        }
        var parts: [String] = []
        if let unit = item.effectiveUnit {
            if item.cur > 0 {
                parts.append(item.progressText)
            } else if let total = item.total, total > 0 {
                parts.append("전체 \(total)\(unit.gap)\(unit.short)")
            }
        }
        if !item.memo.isEmpty {
            parts.append(item.memo)
        }
        return parts.joined(separator: "  ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(item.status == ItemStatus.done ? Theme.ink2 : Theme.ink)
                    .lineLimit(1)
                if !subText.isEmpty {
                    Text(subText)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if item.status == ItemStatus.done {
                SealMini(text: item.cat.seal)
            } else {
                Button(action: { store.start(item.id) }) {
                    Text("시작")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(item.cat.ink)
                        .padding(.horizontal, 15)
                        .frame(height: 36)
                        .overlay(Capsule().stroke(item.cat.ink, lineWidth: 1.5))
                }
                .buttonStyle(DockPressStyle())
            }
        }
        .frame(minHeight: 60)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            nav.editor = EditorRequest(itemID: item.id, category: item.cat, status: item.status)
        }
    }
}
