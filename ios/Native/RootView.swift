import SwiftUI

// MARK: - 전체 화면 (배경, 상단 로고, 좌우로 넘기는 페이지, 떠 있는 하단 탭)

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var introDone = false
    @State private var pendingWidgetLink: WidgetLink?

    private var hasBackground: Bool {
        let image = (nav.page == 2) ? store.homeBg : store.catBg
        return image != nil
    }

    var body: some View {
        ZStack {
            BackgroundView(isHome: nav.page == 2)

            VStack(spacing: 0) {
                TopBar(hasBackground: hasBackground)
                PagePager()
            }

            addButton
            DockView()
            ZStack { toastLayer }
                .animation(.easeInOut(duration: 0.25), value: store.toast?.id)
            ZStack { sealLayer }
                .allowsHitTesting(false)

            if !introDone {
                IntroView(onFinish: finishIntro)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .sheet(item: $nav.editor, onDismiss: openPendingWidget) { request in
            EditorSheet(request: request, existing: existingItem(for: request))
        }
        .sheet(isPresented: $nav.showSettings, onDismiss: openPendingWidget) {
            SettingsSheet()
        }
        .onOpenURL { url in
            guard let link = WidgetLink(url: url) else { return }
            finishIntro()
            pendingWidgetLink = link
            if nav.editor != nil || nav.showSettings {
                nav.editor = nil
                nav.showSettings = false
            } else {
                openPendingWidget()
            }
        }
    }

    private func finishIntro() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { introDone = true }
    }

    private func openPendingWidget() {
        guard let link = pendingWidgetLink else { return }
        pendingWidgetLink = nil
        nav.open(link, items: store.items)
    }

    private func existingItem(for request: EditorRequest) -> Item? {
        guard let id = request.itemID else { return nil }
        return store.item(withID: id)
    }

    // MARK: 추가 버튼

    private var addColor: Color {
        return nav.page == 2 ? Theme.ink : Category.forPage(nav.page).ink
    }

    private var addButton: some View {
        let lifted = store.toast != nil
        return Button(action: openAdd) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                Text("추가")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(Theme.paper)
            .padding(.horizontal, 18)
            .frame(height: 50)
            .background(Capsule().fill(addColor))
            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 6)
        }
        .buttonStyle(DockPressStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 16)
        .padding(.bottom, lifted ? 154 : 92)
        .animation(.easeInOut(duration: 0.25), value: lifted)
    }

    private func openAdd() {
        let onHome = nav.page == 2
        let category = onHome ? Category.game : Category.forPage(nav.page)
        nav.editor = EditorRequest(itemID: nil, category: category, status: onHome ? ItemStatus.play : ItemStatus.wait)
    }

    // MARK: 알림과 완료 도장

    @ViewBuilder private var toastLayer: some View {
        if let toast = store.toast {
            HStack(spacing: 10) {
                Text(toast.message)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.paper)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let snapshot = toast.undoItems {
                    Button(action: { store.undo(snapshot) }) {
                        Text("되돌리기")
                            .font(.system(size: 14, weight: .heavy))
                            .underline()
                            .foregroundColor(Theme.paper)
                            .padding(8)
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.ink))
            .padding(.horizontal, 16)
            .padding(.bottom, 92)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder private var sealLayer: some View {
        if let seal = store.seal {
            SealBurstView(info: seal)
                .id(seal.id)
        }
    }
}

// MARK: - 페이지 (0 게임, 1 애니, 2 홈, 3 미연시, 4 책)

struct PageView: View {
    let index: Int

    var body: some View {
        if index == 2 {
            HomeView()
        } else {
            CategoryView(cat: Category.forPage(index))
        }
    }
}

// MARK: - 배경 (종이 + 고른 사진)

struct BackgroundView: View {
    @EnvironmentObject var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isHome: Bool

    var body: some View {
        ZStack {
            Theme.paper
            background(home: false).opacity(isHome ? 0 : 1)
            background(home: true).opacity(isHome ? 1 : 0)
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: isHome)
    }

    @ViewBuilder private func background(home: Bool) -> some View {
        let image = home ? store.homeBg : store.catBg
        let dim = home ? store.homeDim : store.catDim
        if let photo = image {
            GeometryReader { geo in
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .overlay(Theme.paper.opacity(dim))
            }
        } else {
            GridShape(step: 22)
                .stroke(Theme.ink.opacity(0.05), lineWidth: 1)
        }
    }
}

// MARK: - 상단 (로고, 설정)

struct TopBar: View {
    @EnvironmentObject var nav: Nav
    let hasBackground: Bool

    var body: some View {
        HStack {
            Wordmark(height: 15)
            Spacer()
            Button(action: { nav.showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.ink2)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("설정")
            .accessibilityIdentifier("settings-open")
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .frame(height: 52)
        .background(
            (hasBackground ? Theme.paper.opacity(0.9) : Color.clear)
                .ignoresSafeArea(edges: .top)
        )
    }
}

// MARK: - 하단 탭 (배경 없이 버튼만 떠 있고, 홈이 가운데에서 조금 더 크다)

struct DockView: View {
    @EnvironmentObject var nav: Nav

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(0..<5, id: \.self) { index in
                DockButton(index: index)
            }
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

struct DockButton: View {
    @EnvironmentObject var nav: Nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int

    private var isHome: Bool { return index == 2 }
    private var selected: Bool { return nav.page == index }
    private var size: CGFloat { return isHome ? 60 : 48 }
    private var radius: CGFloat { return isHome ? 21 : 16 }

    private var tint: Color {
        return isHome ? Theme.ink : Category.forPage(index).ink
    }

    private var symbol: String {
        return isHome ? "house" : Category.forPage(index).symbol
    }

    private var title: String {
        return isHome ? "홈" : Category.forPage(index).label
    }

    var body: some View {
        Button(action: { nav.go(index) }) {
            Image(systemName: symbol)
                .font(.system(size: isHome ? 26 : 22, weight: .regular))
                .foregroundColor(selected ? Theme.paper : tint)
                .frame(width: size, height: size)
                .background(glass)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(selected ? Color.clear : Theme.dockLine, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 6)
                .offset(y: selected ? -5 : 0)
        }
        .buttonStyle(DockPressStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier("dock-\(index)")
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9), value: selected)
    }

    private var glass: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(selected ? tint : Color.clear)
        }
    }
}

// MARK: - 완료 도장 (CLEAR / 완주 / 올클 / 완독)

struct SealBurstView: View {
    let info: SealInfo
    @State private var scale: CGFloat = 2.3
    @State private var angle: Double = -30
    @State private var opacity: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            Text(info.text)
                .font(.system(size: 42, weight: .heavy))
                .foregroundColor(Theme.seal)
            Text(info.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.seal)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 120)
        }
        .frame(width: 176, height: 176)
        .background(Circle().fill(Theme.paper))
        .overlay(Circle().stroke(Theme.seal, lineWidth: 5))
        .overlay(Circle().stroke(Theme.seal, lineWidth: 3).padding(11))
        .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: 12)
        .scaleEffect(scale)
        .rotationEffect(.degrees(angle))
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                scale = 1
                angle = -12
                opacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.35)) {
                    opacity = 0
                }
            }
        }
    }
}
