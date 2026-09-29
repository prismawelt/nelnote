import SwiftUI

// MARK: - 홈 (분류별 진행중 작품)

struct HomeView: View {
    @EnvironmentObject var store: Store

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: Date())
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(dateText)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.ink2)
                    Text("진행 중 \(store.countStatus(ItemStatus.play))개")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(Theme.ink)
                }
                .glow(store.homeBg != nil)
                .padding(.horizontal, 2)
                .padding(.top, 4)

                if store.items.isEmpty {
                    FirstRunCard()
                } else {
                    ForEach(Category.allCases) { cat in
                        HomeBlock(cat: cat)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 140)
        }
    }
}

struct FirstRunCard: View {
    @EnvironmentObject var nav: Nav

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                CharacterBadge(size: 64)
                Text("하고 있는 게임, 보고 있는 애니, 읽고 있는 책을 하나씩 추가해 보세요. 진행 중인 작품은 이 화면에 모여요.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: {
                nav.editor = EditorRequest(itemID: nil, category: Category.game, status: ItemStatus.play)
            }) {
                Text("첫 작품 추가")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.paper)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.ink))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.rule, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .padding(.top, 18)
    }
}

struct HomeBlock: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    let cat: Category

    var body: some View {
        let playing = store.list(cat, ItemStatus.play)
        let waiting = store.countWaiting(cat)
        let glowOn = store.homeBg != nil
        return LazyVStack(alignment: .leading, spacing: 0) {
            header(count: playing.count, glowOn: glowOn)
            if playing.isEmpty {
                emptyRow(waiting: waiting, glowOn: glowOn)
            } else {
                ForEach(playing) { item in
                    CardView(item: item, bordered: false)
                }
            }
        }
        .padding(.top, 22)
    }

    private func header(count: Int, glowOn: Bool) -> some View {
        return HStack(alignment: .bottom, spacing: 8) {
            Button(action: { nav.go(cat.pageIndex) }) {
                Text(cat.label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.paper)
                    .padding(.horizontal, 11)
                    .padding(.top, 7)
                    .padding(.bottom, 5)
                    .background(CategoryTabShape().fill(cat.ink))
            }
            Text("\(count)")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(cat.ink)
                .padding(.bottom, 5)
                .glow(glowOn)
            Spacer()
            Button(action: { nav.go(cat.pageIndex) }) {
                Text("전체 보기")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.ink2)
                    .padding(.vertical, 6)
            }
            .glow(glowOn)
        }
        .overlay(Rectangle().fill(cat.ink).frame(height: 2), alignment: .bottom)
        .padding(.bottom, 10)
    }

    private func emptyRow(waiting: Int, glowOn: Bool) -> some View {
        return HStack {
            Text(cat.emptyPlaying)
                .font(.system(size: 14))
                .foregroundColor(Theme.ink3)
            Spacer()
            if waiting > 0 {
                Button(action: { nav.go(cat.pageIndex) }) {
                    Text("대기 중인 \(waiting)개 보기")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(cat.ink)
                }
            } else {
                Button(action: {
                    nav.editor = EditorRequest(itemID: nil, category: cat, status: ItemStatus.play)
                }) {
                    Text(cat.addText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(cat.ink)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
        .glow(glowOn)
    }
}

// MARK: - 진행중 카드 (분류 화면에서는 분류 색 테두리로 강조)

struct CardView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    let item: Item
    let bordered: Bool

    var body: some View {
        let ink = item.cat.ink
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: openEditor) {
                    headline(ink: ink)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                if item.cat == .book && item.status == .play {
                    bookProgress(ink: ink)
                }
                if let quick = item.quick {
                    quickButton(quick, ink: ink)
                }
            }
            Button(action: openEditor) {
                VStack(alignment: .leading, spacing: 0) {
                    ProgressVisual(item: item)
                    if !item.memo.isEmpty {
                        Text(item.memo)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.ink2)
                            .lineLimit(1)
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(bordered ? 11 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(bordered ? ink : Theme.rule, lineWidth: bordered ? 2 : 1)
        )
        .padding(.bottom, 8)
    }

    private func headline(ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 8) {
                if !item.progressText.isEmpty {
                    Text(item.progressText)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(ink)
                }
                Text(item.statusDateRecorded ? "\(dayCount(item.statusAt))일째" : "시작일 미기록")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.ink2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func bookProgress(ink: Color) -> some View {
        HStack(spacing: 3) {
            BookProgressInput(item: item, ink: ink) { value in
                store.updateBookProgress(item.id, current: value)
            }
            .frame(width: 50, height: 48)
            Text(item.effectiveUnit?.short ?? "p")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.ink2)
        }
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ink.opacity(0.45), lineWidth: 1))
    }

    private func quickButton(_ quick: QuickInfo, ink: Color) -> some View {
        Button(action: { perform(quick.action) }) {
            Text(quick.label)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(ink)
                .frame(minWidth: 48, minHeight: 48)
                .padding(.horizontal, 4)
                .overlay(Capsule().stroke(ink, lineWidth: 2))
        }
        .buttonStyle(DockPressStyle())
        .accessibilityIdentifier("item-quick-\(item.id)")
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func openEditor() {
        dismissKeyboard()
        nav.editor = EditorRequest(itemID: item.id, category: item.cat, status: item.status)
    }

    private func perform(_ action: QuickAction) {
        dismissKeyboard()
        switch action {
        case .finish:
            store.finish(item.id)
        case .inc:
            store.increment(item.id)
        case .log:
            nav.editor = EditorRequest(itemID: item.id, category: item.cat, status: item.status, focusCur: true)
        }
    }
}
