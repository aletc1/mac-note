import Foundation

/// A simple debouncer built on `DispatchWorkItem`.
/// Calling `schedule` multiple times within `delay` seconds cancels the
/// previous pending block and restarts the timer, so only the *last* call
/// in a burst fires.
final class Debouncer: @unchecked Sendable {

    // MARK: - State

    private let delay: TimeInterval
    private let queue: DispatchQueue
    private var workItem: DispatchWorkItem?
    private let lock = NSLock()

    // MARK: - Init

    /// - Parameters:
    ///   - delay: Seconds to wait after the last `schedule` call before firing.
    ///   - queue: Queue on which the block executes (default: main).
    init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    // MARK: - API

    /// Schedule `block` to run after `delay` seconds.
    /// Any previously-pending block is cancelled before scheduling the new one.
    func schedule(_ block: @escaping @Sendable () -> Void) {
        lock.lock()
        workItem?.cancel()
        let item = DispatchWorkItem(block: block)
        workItem = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Cancel the pending block without firing it.
    func cancel() {
        lock.lock()
        workItem?.cancel()
        workItem = nil
        lock.unlock()
    }

    /// Fire the pending block immediately (if any) and cancel the delayed call.
    func fireNow() {
        lock.lock()
        let item = workItem
        workItem = nil
        lock.unlock()
        item?.cancel()                     // cancel the delayed dispatch
        item.map { queue.async(execute: $0) } // fire synchronously on queue
    }
}
