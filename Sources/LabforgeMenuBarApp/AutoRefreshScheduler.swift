import Foundation

final class AutoRefreshScheduler {
    private let intervalNanoseconds: UInt64
    private var task: Task<Void, Never>?

    init(intervalNanoseconds: UInt64 = 300_000_000_000) {
        self.intervalNanoseconds = intervalNanoseconds
    }

    deinit {
        stop()
    }

    func start(action: @escaping @Sendable () async -> Void) {
        guard task == nil else { return }
        let intervalNanoseconds = intervalNanoseconds

        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
                guard !Task.isCancelled else { break }
                await action()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
