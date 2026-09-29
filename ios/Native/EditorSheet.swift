import SwiftUI

// MARK: - 작품 추가 / 수정 창

struct EditorSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: Nav
    @Environment(\.dismiss) private var dismiss

    let request: EditorRequest

    @State private var cat: Category
    @State private var title: String
    @State private var status: ItemStatus
    @State private var unit: ItemUnit
    @State private var curText: String
    @State private var totalText: String
    @State private var memo: String
    @State private var confirmDelete = false
    @State private var titleError = false
    @FocusState private var focus: Field?

    enum Field {
        case title
        case cur
        case total
        case memo
    }

    init(request: EditorRequest, existing: Item?) {
        self.request = request
        if let item = existing {
            _cat = State(initialValue: item.cat)
            _title = State(initialValue: item.title)
            _status = State(initialValue: item.status)
            _unit = State(initialValue: item.unit ?? ItemUnit.page)
            _curText = State(initialValue: String(item.cur))
            _totalText = State(initialValue: item.total.map { String($0) } ?? "")
            _memo = State(initialValue: item.memo)
        } else {
            _cat = State(initialValue: request.category)
            _title = State(initialValue: "")
            _status = State(initialValue: request.status)
            _unit = State(initialValue: ItemUnit.page)
            _curText = State(initialValue: "")
            _totalText = State(initialValue: "")
            _memo = State(initialValue: "")
        }
    }

    private var isAdd: Bool { return request.itemID == nil }

    private var effectiveUnit: ItemUnit? {
        switch cat {
        case .game: return nil
        case .anime: return ItemUnit.ep
        case .vn: return ItemUnit.route
        case .book: return unit
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isAdd ? "작품 추가" : "작품 수정")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(Theme.ink)
                if isAdd {
                    categoryField
                }
                titleField
                statusField
                if cat == Category.book {
                    unitField
                }
                countFields
                memoField
                actionRow
            }
            .padding(18)
        }
        .background(Theme.paper.ignoresSafeArea())
        .task {
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
                if request.focusCur {
                    focus = Field.cur
                } else if isAdd {
                    focus = Field.title
                }
            } catch { }
        }
    }

    // MARK: 입력 칸

    private func label(_ text: String) -> some View {
        return Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Theme.ink2)
    }

    private func box(_ placeholder: String, text: Binding<String>, error: Bool = false) -> some View {
        return TextField(placeholder, text: text)
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(error ? Theme.seal : Theme.rule, lineWidth: 1.5)
            )
    }

    private var categoryField: some View {
        return VStack(alignment: .leading, spacing: 6) {
            label("분류")
            Picker("분류", selection: $cat) {
                ForEach(Category.allCases) { c in
                    Text(c.label).tag(c)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: cat) { _ in
                curText = ""
                totalText = ""
            }
        }
    }

    private var titleField: some View {
        return VStack(alignment: .leading, spacing: 6) {
            label("제목")
            box(cat.titlePlaceholder, text: $title, error: titleError)
                .focused($focus, equals: Field.title)
                .submitLabel(.done)
                .onChange(of: title) { _ in
                    titleError = false
                }
            if titleError {
                Text("제목을 입력해야 저장할 수 있어요")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.seal)
            }
        }
    }

    private var statusField: some View {
        return VStack(alignment: .leading, spacing: 6) {
            label("상태")
            Picker("상태", selection: $status) {
                ForEach([ItemStatus.wait, ItemStatus.play, ItemStatus.done], id: \.self) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var unitField: some View {
        return VStack(alignment: .leading, spacing: 6) {
            label("기록 단위")
            Picker("기록 단위", selection: $unit) {
                Text("페이지").tag(ItemUnit.page)
                Text("권").tag(ItemUnit.vol)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder private var countFields: some View {
        if let u = effectiveUnit {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    curColumn(u)
                    totalColumn(u)
                }
                if u == ItemUnit.ep {
                    HStack(spacing: 6) {
                        ForEach([12, 13, 24, 26], id: \.self) { n in
                            Button(action: { totalText = String(n) }) {
                                Text("\(n)화")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.ink2)
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .overlay(Capsule().stroke(Theme.rule, lineWidth: 1))
                            }
                        }
                    }
                    Text("방영 중이라 전체 화수를 모르면 비워 두세요.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.ink3)
                }
            }
        }
    }

    private func curColumn(_ u: ItemUnit) -> some View {
        return VStack(alignment: .leading, spacing: 6) {
            label(u.curLabel)
            HStack(spacing: 4) {
                stepButton("minus", delta: -1)
                TextField("0", text: $curText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 18, weight: .bold))
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.rule, lineWidth: 1.5))
                    .focused($focus, equals: Field.cur)
                    .onChange(of: curText) { value in
                        let cleaned = String(value.filter { $0.isNumber }.prefix(5))
                        if cleaned != value {
                            curText = cleaned
                        }
                    }
                stepButton("plus", delta: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func totalColumn(_ u: ItemUnit) -> some View {
        return VStack(alignment: .leading, spacing: 6) {
            label(u.totalLabel)
            TextField("비워도 돼요", text: $totalText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 18, weight: .bold))
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.rule, lineWidth: 1.5))
                .focused($focus, equals: Field.total)
                .onChange(of: totalText) { value in
                    let cleaned = String(value.filter { $0.isNumber }.prefix(5))
                    if cleaned != value {
                        totalText = cleaned
                    }
                }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        return Button(action: { step(delta) }) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.ink)
                .frame(width: 40, height: 46)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.rule2))
        }
    }

    private func step(_ delta: Int) {
        let current = Int(curText) ?? 0
        var next = max(0, current + delta)
        if let total = Int(totalText), total > 0 {
            next = min(next, total)
        }
        curText = String(next)
    }

    private var memoField: some View {
        return VStack(alignment: .leading, spacing: 6) {
            label("메모")
            box(cat.memoPlaceholder, text: $memo)
                .focused($focus, equals: Field.memo)
                .submitLabel(.done)
        }
    }

    private var actionRow: some View {
        return HStack(spacing: 8) {
            if !isAdd {
                Button(action: deleteTapped) {
                    Text(confirmDelete ? "한 번 더 누르면 삭제" : "삭제")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.seal)
                        .padding(.horizontal, 12)
                        .frame(height: 50)
                }
            }
            Button(action: save) {
                Text(isAdd ? "추가" : "저장")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.paper)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cat.ink))
            }
        }
        .padding(.top, 6)
    }

    // MARK: 저장과 삭제

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            titleError = true
            focus = Field.title
            return
        }
        let input = EditorInput(
            existingID: request.itemID,
            cat: cat,
            title: trimmed,
            status: status,
            unit: unit,
            curText: curText,
            totalText: totalText,
            memo: memo
        )
        store.saveEditor(input)
        let target = cat.pageIndex
        dismiss()
        // 분류 화면에서 다른 분류의 작품을 추가했다면 그 분류 화면으로 이동
        if nav.page != 2 && nav.page != target {
            nav.go(target)
        }
    }

    private func deleteTapped() {
        if !confirmDelete {
            confirmDelete = true
            return
        }
        if let id = request.itemID {
            store.delete(id)
        }
        dismiss()
    }
}
