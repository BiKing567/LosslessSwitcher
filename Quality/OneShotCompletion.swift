import Foundation

/// Delivers an asynchronous result at most once when a callback and timeout
/// race on different queues.
final class OneShotCompletion<Value> {
    private let lock = NSLock()
    private var callback: ((Value) -> Void)?

    init(_ callback: @escaping (Value) -> Void) {
        self.callback = callback
    }

    func complete(_ value: Value) {
        lock.lock()
        let callback = self.callback
        self.callback = nil
        lock.unlock()
        callback?(value)
    }
}
