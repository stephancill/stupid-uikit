// Combine's `Publishers.MergeMany`, which the pinned OpenCombine revision
// (full/oracle-opencombine) does not have. Compiled into the app-facing
// `Combine` module by full/scripts/build_full.sh next to the hash-pinned
// re-export shim (full/oracle-opencombine/Combine.swift, which the widget and
// onboarding gates pin byte for byte and so stays unchanged). See
// uikit/docs/APP_CATCHUP_APIS.md.
//
// Semantics follow Combine: every upstream is subscribed; values are
// delivered one at a time (serialized across upstreams) and never beyond the
// downstream's demand; the merge finishes once every upstream has finished
// and fails, cancelling the others, on the first failure. Each upstream has
// at most one value requested at a time, so a value that arrives while the
// downstream has no demand waits in a buffer of at most one per upstream.

import COpenCombineHelpers
import OpenCombine

extension Publishers {
    public struct MergeMany<Upstream: Publisher>: Publisher {
        public typealias Output = Upstream.Output
        public typealias Failure = Upstream.Failure

        public let publishers: [Upstream]

        public init(_ upstream: Upstream...) {
            publishers = upstream
        }

        public init<S: Swift.Sequence>(_ upstream: S) where Upstream == S.Element {
            publishers = Array(upstream)
        }

        public func receive<S: Subscriber>(subscriber: S)
        where S.Input == Output, S.Failure == Failure {
            let inner = _MergeManyInner<Upstream, S>(downstream: subscriber, count: publishers.count)
            subscriber.receive(subscription: inner)
            if publishers.isEmpty {
                inner.finishIfEmpty()
                return
            }
            for (index, publisher) in publishers.enumerated() {
                publisher.subscribe(_MergeManySide(index: index, inner: inner))
            }
        }

        public func merge(with other: Upstream) -> Publishers.MergeMany<Upstream> {
            Publishers.MergeMany(publishers + [other])
        }
    }
}

extension Publishers.MergeMany: Equatable where Upstream: Equatable {}

final class _MergeManyInner<Upstream: Publisher, Downstream: Subscriber>: Subscription
where Downstream.Input == Upstream.Output, Downstream.Failure == Upstream.Failure {
    private let lock = __UnfairRecursiveLock.allocate()
    private var downstream: Downstream?
    private var subscriptions: [Subscription?]
    private var outstanding: [Bool]
    private var finished: [Bool]
    private var pending: [(index: Int, value: Upstream.Output)] = []
    private var demand = Subscribers.Demand.none

    init(downstream: Downstream, count: Int) {
        self.downstream = downstream
        subscriptions = Array(repeating: nil, count: count)
        outstanding = Array(repeating: false, count: count)
        finished = Array(repeating: false, count: count)
    }

    deinit {
        lock.deallocate()
    }

    func finishIfEmpty() {
        lock.lock()
        defer { lock.unlock() }
        finishIfDone()
    }

    func receive(subscription: Subscription, index: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard downstream != nil, subscriptions[index] == nil else {
            subscription.cancel()
            return
        }
        subscriptions[index] = subscription
        requestIdle()
    }

    func receive(_ value: Upstream.Output, index: Int) -> Subscribers.Demand {
        lock.lock()
        defer { lock.unlock() }
        outstanding[index] = false
        guard let downstream else { return .none }
        guard demand > 0 else {
            pending.append((index, value))
            return .none
        }
        demand -= 1
        demand += downstream.receive(value)
        guard demand > 0, self.downstream != nil else { return .none }
        outstanding[index] = true
        requestIdle()
        return .max(1)
    }

    func receive(completion: Subscribers.Completion<Upstream.Failure>, index: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard let downstream else { return }
        subscriptions[index] = nil
        outstanding[index] = false
        finished[index] = true
        switch completion {
        case .failure:
            let others = subscriptions
            terminate()
            for subscription in others { subscription?.cancel() }
            downstream.receive(completion: completion)
        case .finished:
            finishIfDone()
        }
    }

    func request(_ demand: Subscribers.Demand) {
        lock.lock()
        defer { lock.unlock() }
        guard downstream != nil else { return }
        self.demand += demand
        while self.demand > 0, !pending.isEmpty, let downstream = self.downstream {
            let (_, value) = pending.removeFirst()
            self.demand -= 1
            self.demand += downstream.receive(value)
        }
        finishIfDone()
        requestIdle()
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        let all = subscriptions
        terminate()
        for subscription in all { subscription?.cancel() }
    }

    private func terminate() {
        downstream = nil
        subscriptions = subscriptions.map { _ in nil }
        pending = []
    }

    private func finishIfDone() {
        guard let downstream, pending.isEmpty, !finished.contains(false) else { return }
        terminate()
        downstream.receive(completion: .finished)
    }

    /// Requests one value from every live upstream that has none requested or
    /// buffered, while the downstream wants values.
    private func requestIdle() {
        for index in subscriptions.indices {
            guard demand > 0, downstream != nil else { return }
            guard let subscription = subscriptions[index], !outstanding[index],
                  !pending.contains(where: { $0.index == index })
            else { continue }
            outstanding[index] = true
            subscription.request(.max(1))
        }
    }
}

final class _MergeManySide<Upstream: Publisher, Downstream: Subscriber>: Subscriber
where Downstream.Input == Upstream.Output, Downstream.Failure == Upstream.Failure {
    typealias Input = Upstream.Output
    typealias Failure = Upstream.Failure

    private let index: Int
    private let inner: _MergeManyInner<Upstream, Downstream>

    init(index: Int, inner: _MergeManyInner<Upstream, Downstream>) {
        self.index = index
        self.inner = inner
    }

    func receive(subscription: Subscription) {
        inner.receive(subscription: subscription, index: index)
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        inner.receive(input, index: index)
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        inner.receive(completion: completion, index: index)
    }
}
