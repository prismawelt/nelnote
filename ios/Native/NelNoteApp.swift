import SwiftUI

@main
struct NelNoteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = Store()
    @StateObject private var nav = Nav()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(nav)
                .onChange(of: scenePhase) { phase in
                    if phase == .active { store.syncWidget() }
                }
        }
    }
}
