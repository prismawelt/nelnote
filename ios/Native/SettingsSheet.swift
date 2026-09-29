import SwiftUI
import PhotosUI

// MARK: - 설정 (배경 사진, 백업)

struct SettingsSheet: View {
    @EnvironmentObject var store: Store
    @State private var importText = ""
    @State private var confirmImport = false
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("설정")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(Theme.ink)
                    .padding(.bottom, 16)

                ObsidianSettingsSection()

                sub("배경 사진")
                Text("홈 화면과 분류 화면에 각각 다른 사진을 깔 수 있어요.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.ink2)
                    .padding(.bottom, 4)
                BackgroundRow(slot: BgSlot.home)
                BackgroundRow(slot: BgSlot.cat)

                sub("백업").padding(.top, 22)
                Text("앱을 지우거나 휴대폰을 바꾸면 기록도 함께 사라져요. 가끔 백업을 카톡 나와의 채팅이나 메모 앱에 보내 두세요.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.ink2)
                    .padding(.bottom, 12)
                HStack(spacing: 8) {
                    ShareLink(item: store.backupText()) {
                        Text("백업 보내기")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Theme.paper)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.ink))
                    }
                    Button(action: copyBackup) {
                        Text("복사")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Theme.ink)
                            .padding(.horizontal, 22)
                            .frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.rule2))
                    }
                }

                sub("백업 불러오기").padding(.top, 22)
                importBox
                Button(action: importTapped) {
                    Text(confirmImport ? "한 번 더 누르면 지금 기록을 덮어써요" : "불러오기")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(confirmImport ? Theme.seal : Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.rule2))
                }
                .padding(.top, 8)

                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.ink2)
                        .padding(.top, 12)
                }

                Text("작품 \(store.items.count)개 기록 중")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
            }
            .padding(18)
        }
        .background(Theme.paper.ignoresSafeArea())
    }

    private func sub(_ text: String) -> some View {
        return Text(text)
            .font(.system(size: 15, weight: .heavy))
            .foregroundColor(Theme.ink)
            .padding(.bottom, 8)
    }

    private var importBox: some View {
        return ZStack(alignment: .topLeading) {
            TextEditor(text: $importText)
                .font(.system(size: 13))
                .frame(height: 96)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.rule, lineWidth: 1.5))
                .onChange(of: importText) { _ in
                    confirmImport = false
                }
            if importText.isEmpty {
                Text("보내 둔 백업 내용을 전부 붙여 넣으세요")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.ink3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
    }

    private func copyBackup() {
        UIPasteboard.general.string = store.backupText()
        message = "백업을 복사했어요"
    }

    private func importTapped() {
        let text = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = text.data(using: .utf8), Store.parseItems(data) != nil else {
            confirmImport = false
            message = "백업 내용을 읽지 못했어요. 처음부터 끝까지 빠짐없이 붙여 넣었는지 확인해 주세요."
            return
        }
        if !confirmImport {
            confirmImport = true
            return
        }
        if let count = store.importBackup(text) {
            message = "작품 \(count)개를 불러왔어요"
        }
        importText = ""
        confirmImport = false
    }
}

struct BackgroundRow: View {
    @EnvironmentObject var store: Store
    let slot: BgSlot
    @State private var picked: PhotosPickerItem?
    @State private var note = ""

    private var hasPhoto: Bool { return store.background(slot) != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            thumb
            VStack(alignment: .leading, spacing: 8) {
                Text(slot.name)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(Theme.ink)
                HStack(spacing: 6) {
                    PhotosPicker(selection: $picked, matching: .images) {
                        Text(hasPhoto ? "다른 사진" : "사진 고르기")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Theme.paper)
                            .padding(.horizontal, 15)
                            .frame(height: 36)
                            .background(Capsule().fill(Theme.ink))
                    }
                    if hasPhoto {
                        Button(action: { store.clearBackground(slot) }) {
                            Text("지우기")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Theme.ink)
                                .padding(.horizontal, 15)
                                .frame(height: 36)
                                .background(Capsule().fill(Theme.rule2))
                        }
                    }
                }
                if hasPhoto {
                    dimSlider
                }
                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.ink3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .onChange(of: picked) { newItem in
            if let item = newItem {
                load(item)
            }
        }
    }

    @ViewBuilder private var thumb: some View {
        if let image = store.thumbnail(slot) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 104)
                .overlay(Theme.paper.opacity(store.dim(slot)))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Text("없음")
                .font(.system(size: 12))
                .foregroundColor(Theme.ink3)
                .frame(width: 60, height: 104)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        }
    }

    private var dimSlider: some View {
        let binding = Binding<Double>(
            get: { return store.dim(slot) },
            set: { store.setDim(slot, $0) }
        )
        return HStack(spacing: 8) {
            Text("흐리게")
                .font(.system(size: 12))
                .foregroundColor(Theme.ink2)
            Slider(value: binding, in: 0...0.9, step: 0.05)
            Text("\(Int((store.dim(slot) * 100).rounded()))%")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Theme.ink)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func load(_ item: PhotosPickerItem) {
        note = "사진을 준비하고 있어요"
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                var ok = false
                if let bytes = data {
                    ok = store.setBackground(slot, data: bytes)
                }
                note = ok ? "" : "이 사진은 불러오지 못했어요. 다른 사진을 골라 주세요."
                picked = nil
            }
        }
    }
}
