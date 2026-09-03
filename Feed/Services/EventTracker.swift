import Foundation

/// Buffers analytics events and flushes them in batches (count, time, or explicit). Safe to call from any context.
actor EventTracker {
    private let repository: EventRepository
    private var pending: [AnalyticsEvent] = []
    private var flushTask: Task<Void, Never>?
    private let batchSize: Int
    private let maxDelay: Duration
    private var backoff: Duration = .seconds(2)

    init(repository: EventRepository, batchSize: Int = 10, maxDelay: Duration = .seconds(5)) {
        self.repository = repository
        self.batchSize = batchSize
        self.maxDelay = maxDelay
    }

    func track(_ event: AnalyticsEvent) {
        pending.append(event)
        if pending.count >= batchSize {
            Task { await flush() }
        } else if flushTask == nil {
            flushTask = Task { [maxDelay] in
                try? await Task.sleep(for: maxDelay)
                await self.flush()
            }
        }
    }

    func flush() async {
        flushTask?.cancel()
        flushTask = nil
        guard !pending.isEmpty else { return }
        let batch = Array(pending.prefix(200))
        do {
            try await repository.send(batch)
            pending.removeFirst(batch.count)
            backoff = .seconds(2)
            if !pending.isEmpty { await flush() }
        } catch {
            print("[EventTracker] flush failed: \(error). Retrying in \(backoff)")
            let delay = backoff
            backoff = min(backoff * 2, .seconds(60))
            flushTask = Task {
                try? await Task.sleep(for: delay)
                await self.flush()
            }
        }
    }

    var pendingCount: Int { pending.count }
}
