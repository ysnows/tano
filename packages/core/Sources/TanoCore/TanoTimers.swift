import Foundation
import JavaScriptCore

/// Thread-safe `setTimeout`, `setInterval`, `clearTimeout`, `clearInterval`
/// implementation backed by `DispatchSourceTimer`.
///
/// Timer callbacks are marshalled back to the JSC thread via the
/// `jscPerform` closure that the caller supplies at init time.
public final class TanoTimers {

    // MARK: - Types

    private struct TimerEntry {
        let source: DispatchSourceTimer
        let callback: JSManagedValue
        let repeats: Bool
    }

    // MARK: - Properties

    private let jscPerform: (@escaping () -> Void) -> Void

    private let lock = NSLock()
    private var nextID: Int32 = 1
    private var timers: [Int32: TimerEntry] = [:]

    // MARK: - Init

    /// - Parameter jscPerform: A closure that schedules a block on the JSC
    ///   thread (typically ``TanoRuntime/performOnJSCThread(_:)``).
    public init(jscPerform: @escaping (@escaping () -> Void) -> Void) {
        self.jscPerform = jscPerform
    }

    // MARK: - Injection

    /// Injects `setTimeout`, `setInterval`, `clearTimeout`, and
    /// `clearInterval` into the given `JSContext`.
    public func inject(into context: JSContext) {
        let setTimeoutBlock: @convention(block) (JSValue, JSValue) -> Int32 = { [weak self] callback, delay in
            guard let self else { return 0 }
            let ms = delay.isUndefined ? 0 : max(0, delay.toInt32())
            return self.schedule(callback: callback, delayMs: ms, repeats: false, context: context)
        }

        let setIntervalBlock: @convention(block) (JSValue, JSValue) -> Int32 = { [weak self] callback, delay in
            guard let self else { return 0 }
            let ms = delay.isUndefined ? 0 : max(0, delay.toInt32())
            return self.schedule(callback: callback, delayMs: ms, repeats: true, context: context)
        }

        let clearTimeoutBlock: @convention(block) (JSValue) -> Void = { [weak self] idVal in
            guard let self else { return }
            let id = idVal.toInt32()
            self.cancel(id: id)
        }

        context.setObject(setTimeoutBlock,   forKeyedSubscript: "setTimeout"    as NSString)
        context.setObject(setIntervalBlock,  forKeyedSubscript: "setInterval"   as NSString)
        context.setObject(clearTimeoutBlock, forKeyedSubscript: "clearTimeout"  as NSString)
        context.setObject(clearTimeoutBlock, forKeyedSubscript: "clearInterval" as NSString)
    }

    // MARK: - Cancel All

    /// Cancel every active timer. Called during runtime shutdown.
    public func cancelAll() {
        lock.lock()
        let allTimers = timers
        timers.removeAll()
        lock.unlock()

        for (_, entry) in allTimers {
            entry.source.cancel()
        }
    }

    // MARK: - Private Helpers

    private func schedule(
        callback: JSValue,
        delayMs: Int32,
        repeats: Bool,
        context: JSContext
    ) -> Int32 {
        // Prevent GC of the JS callback while the timer is alive.
        let managed = JSManagedValue(value: callback)!
        context.virtualMachine.addManagedReference(managed, withOwner: self)

        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        let interval = DispatchTimeInterval.milliseconds(Int(delayMs))

        if repeats {
            source.schedule(deadline: .now() + interval, repeating: interval)
        } else {
            source.schedule(deadline: .now() + interval)
        }

        lock.lock()
        let id = nextID
        nextID += 1
        lock.unlock()

        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.jscPerform {
                guard let cb = managed.value, !cb.isUndefined else { return }
                cb.call(withArguments: [])
            }

            if !repeats {
                self.cancel(id: id)
                context.virtualMachine.removeManagedReference(managed, withOwner: self)
            }
        }

        source.setCancelHandler {
            // prevent dealloc crash on still-resumed sources
        }

        lock.lock()
        timers[id] = TimerEntry(source: source, callback: managed, repeats: repeats)
        lock.unlock()

        source.resume()
        return id
    }

    private func cancel(id: Int32) {
        lock.lock()
        let entry = timers.removeValue(forKey: id)
        lock.unlock()

        if let entry {
            entry.source.cancel()
        }
    }
}
