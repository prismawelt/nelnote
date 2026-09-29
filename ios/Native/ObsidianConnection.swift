import Foundation

private final class VaultCancellation {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

/// Main-thread orchestration; file-provider work and YAML parsing stay on one
/// background queue. Every mutation is persisted before another pass is queued.
final class ObsidianConnection {
    private weak var store: Store?
    private let queue = DispatchQueue(label: "com.nelnote.obsidian", qos: .utility)
    private var scheduled: DispatchWorkItem?
    private var timer: Timer?
    private var presenter: VaultPresenter?
    private var token = VaultCancellation()
    private var generation = 0
    private var active = false
    private var again = false

    init(store: Store) { self.store = store }

    func resume() {
        active = true
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                self?.schedule()
            }
        }
        schedule(delay: 0)
    }

    func suspend() {
        active = false
        timer?.invalidate(); timer = nil
        scheduled?.cancel(); scheduled = nil
        stopPresenting()
    }

    func cancel() {
        generation += 1
        token.cancel()
        scheduled?.cancel(); scheduled = nil
        again = false
    }

    func disconnect() {
        guard let store else { return }
        cancel(); stopPresenting()
        store.vaultState = VaultState()
        store.vaultConflicts = []
        store.vaultMessage = "연결을 해제했습니다."
        _ = store.save(trackChanges: false)
    }

    func connect(_ url: URL) {
        guard let store else { return }
        guard url.startAccessingSecurityScopedResource() else {
            store.vaultMessage = VaultError.permission.localizedDescription
            return
        }
        cancel()
        let selectionGeneration = generation
        store.vaultMessage = "보관함을 확인하고 있습니다…"
        queue.async { [weak self] in
            let result = Result { () -> Data in
                try VaultFiles(root: url).validateAccess()
                return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            url.stopAccessingSecurityScopedResource()
            DispatchQueue.main.async {
                guard let self, let store = self.store, self.generation == selectionGeneration else { return }
                switch result {
                case .success(let bookmark):
                    self.stopPresenting()
                    store.vaultState.connect(bookmark: bookmark, name: url.lastPathComponent,
                                             location: url.standardizedFileURL.path)
                    store.vaultConflicts = []
                    if store.save(trackChanges: false) {
                        store.vaultMessage = "보관함을 연결했습니다."
                        self.schedule(delay: 0)
                    }
                case .failure(let error):
                    store.vaultMessage = error.localizedDescription
                }
            }
        }
    }

    func choose(_ conflict: VaultConflict, itemID: String?) {
        guard let store else { return }
        store.vaultState.choices[conflict.path] = itemID ?? "new"
        if store.save(trackChanges: false) { schedule(delay: 0) }
    }

    func schedule(delay: Double = 0.8) {
        guard store?.vaultState.bookmark != nil else { return }
        if store?.vaultBusy == true { again = true; return }
        scheduled?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sync() }
        scheduled = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func work<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try operation() }) }
        }
    }

    func sync() {
        guard let store, let bookmark = store.vaultState.bookmark else { return }
        guard !store.vaultBusy else { again = true; return }
        scheduled?.cancel(); scheduled = nil
        store.vaultBusy = true
        store.vaultMessage = "동기화 중…"
        token = VaultCancellation()
        let runToken = token
        let runGeneration = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            var scopedURL: URL?
            defer {
                scopedURL?.stopAccessingSecurityScopedResource()
                store.vaultBusy = false
                if self.again {
                    self.again = false
                    self.schedule()
                }
            }
            do {
                var stale = false
                let root = try URL(resolvingBookmarkData: bookmark, options: [],
                                   relativeTo: nil, bookmarkDataIsStale: &stale)
                guard root.startAccessingSecurityScopedResource() else { throw VaultError.permission }
                scopedURL = root
                if stale {
                    store.vaultState.bookmark = try root.bookmarkData(options: .minimalBookmark,
                        includingResourceValuesForKeys: nil, relativeTo: nil)
                    guard store.save(trackChanges: false) else { return }
                }
                if self.active { self.startPresenting(root) }
                let revision = store.vaultRevision
                let input = store.items
                let snapshot = store.vaultState
                let files = VaultFiles(root: root)
                let plan = try await self.work { try files.prepare(items: input, state: snapshot) }
                guard self.generation == runGeneration else { return }
                guard store.vaultRevision == revision else { self.again = true; return }
                store.vaultConflicts = plan.conflicts
                if !plan.conflicts.isEmpty {
                    store.vaultMessage = "이름이 같은 작품 \(plan.conflicts.count)개를 확인해 주세요."
                    return
                }
                guard store.adoptVaultLinks(plan) else { return }
                let result = try await self.work { files.execute(plan, isCancelled: { runToken.isCancelled }) }
                guard self.generation == runGeneration else { return }
                let saved = store.acceptVaultRun(result, snapshot: snapshot)
                if saved {
                    store.vaultMessage = result.error ?? store.vaultState.lastResult ?? "동기화 완료"
                }
            } catch {
                if self.generation == runGeneration {
                    store.vaultMessage = error.localizedDescription
                    store.vaultState.lastResult = store.vaultMessage
                    _ = store.save(trackChanges: false)
                }
            }
        }
    }

    private func startPresenting(_ url: URL) {
        guard presenter?.presentedItemURL != url else { return }
        stopPresenting()
        let observer = VaultPresenter(url: url) { [weak self] in
            DispatchQueue.main.async { self?.schedule(delay: 1.5) }
        }
        presenter = observer
        NSFileCoordinator.addFilePresenter(observer)
    }

    private func stopPresenting() {
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        presenter = nil
    }

    deinit {
        timer?.invalidate()
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
    }
}

private final class VaultPresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue
    private let onChange: () -> Void
    private let scopedAccess: Bool

    init(url: URL, onChange: @escaping () -> Void) {
        presentedItemURL = url
        scopedAccess = url.startAccessingSecurityScopedResource()
        self.onChange = onChange
        presentedItemOperationQueue = OperationQueue()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        super.init()
    }
    deinit { if scopedAccess { presentedItemURL?.stopAccessingSecurityScopedResource() } }
    func presentedItemDidChange() { onChange() }
    func presentedSubitemDidChange(at url: URL) { onChange() }
    func presentedSubitemDidAppear(at url: URL) { onChange() }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { onChange() }
    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil); onChange()
    }
}
