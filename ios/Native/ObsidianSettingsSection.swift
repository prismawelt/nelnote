import SwiftUI
import UniformTypeIdentifiers

struct ObsidianSettingsSection: View {
    @EnvironmentObject var store: Store
    @State private var chooseFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Obsidian 연결")
                .font(.system(size: 15, weight: .heavy))
            if let name = store.vaultState.name {
                Label(name, systemImage: "folder")
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 12) {
                    Button(action: { store.obsidian.sync() }) {
                        HStack(spacing: 6) {
                            if store.vaultBusy { ProgressView().scaleEffect(0.8) }
                            Text(store.vaultBusy ? "동기화 중" : "지금 동기화")
                        }
                    }
                    .disabled(store.vaultBusy)
                    .accessibilityIdentifier("obsidian-sync")
                    Spacer()
                    Button("다시 선택") { chooseFolder = true }
                    Button("연결 해제", role: .destructive) { store.obsidian.disconnect() }
                }
                .font(.system(size: 14, weight: .semibold))
            } else {
                Button("보관함 폴더 선택") { chooseFolder = true }
                    .font(.system(size: 15, weight: .bold))
                    .accessibilityIdentifier("obsidian-connect")
            }
            Text("아이폰 Obsidian에서 사용하는 보관함 전체를 선택하세요. 작품과 상태를 서로 반영하며, 삭제한 DB 파일은 보관함 휴지통으로 옮깁니다.")
                .font(.system(size: 13))
                .foregroundColor(Theme.ink2)
            Text("메모와 세부 진행량은 NEL NOTE에만 저장됩니다. 노트북까지 반영하려면 양쪽 Obsidian에서 Remotely Save를 실행하세요.")
                .font(.system(size: 12))
                .foregroundColor(Theme.ink3)
            if !store.vaultMessage.isEmpty {
                Text(store.vaultMessage)
                    .font(.system(size: 13))
                    .accessibilityIdentifier("obsidian-result")
            }
            if let date = store.vaultState.lastSync {
                Text("마지막 완료: " + date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.ink3)
            }
            if let conflict = store.vaultConflicts.first {
                conflictView(conflict)
            }
        }
        .foregroundColor(Theme.ink)
        .padding(.bottom, 22)
        .fileImporter(isPresented: $chooseFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { store.obsidian.connect(url) }
            case .failure(let error):
                store.vaultMessage = error.localizedDescription
            }
        }
    }

    private func conflictView(_ conflict: VaultConflict) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("연결할 작품 선택").font(.system(size: 14, weight: .bold))
            Text(conflict.path).font(.system(size: 12)).foregroundColor(Theme.ink2)
            ForEach(conflict.candidates) { item in
                Button(action: { store.obsidian.choose(conflict, itemID: item.id) }) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                        Text([item.status.label, item.progressText, clip(item.memo, 32)]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.rule2)
                    .cornerRadius(8)
                }
            }
            Button("별도 작품으로 추가") { store.obsidian.choose(conflict, itemID: nil) }
        }
        .padding(12)
        .background(Theme.card)
        .cornerRadius(12)
    }
}
