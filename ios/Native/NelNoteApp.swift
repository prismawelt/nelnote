import SwiftUI

@main
struct NelNoteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: Store
    @StateObject private var nav = Nav()

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NelNoteUITests")
            try? FileManager.default.removeItem(at: directory)
            let testStore = Store(baseURL: directory)
            if ProcessInfo.processInfo.arguments.contains("--ui-large-library") {
                testStore.items = (0..<1000).map { index in
                    Item(id: "ui-\(index)", cat: .anime, title: String(format: "Library %04d", index),
                         status: Category.anime.statuses[index % 5], cur: 0, total: 12, unit: nil,
                         memo: "", created: 1, statusAt: 0, doneAt: nil, updated: 1,
                         progressRecorded: false, statusDateRecorded: false)
                }
            }
            _store = StateObject(wrappedValue: testStore)
            return
        }
        #endif
        _store = StateObject(wrappedValue: Store())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(nav)
                .onAppear { store.obsidian.resume() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { store.syncWidget(); store.obsidian.resume() }
                    else { store.obsidian.suspend() }
                }
        }
    }
}
