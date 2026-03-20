import Foundation

/// iOS-adapted NodeJsTask — manages command execution via UDS.
/// Simplified from macOS: no FlowTask/ExtensionCommandManager, no Worker threads.
class NodeJsTask {

    // MARK: - Static delegate storage

    static var delegates: [String: OnMessageDelegate] = [:]
    static var callDelegates: [String: OnMessageDelegate] = [:]

    private static let delegatesQueue = DispatchQueue(
        label: "com.enconvo.ios.nodejstask.delegates.queue", attributes: .concurrent)
    private static let callDelegatesQueue = DispatchQueue(
        label: "com.enconvo.ios.nodejstask.calldelegates.queue", attributes: .concurrent)

    // MARK: - Delegate Management

    static func addDelegate(for key: String, delegate: @escaping OnMessageDelegate) {
        delegatesQueue.async(flags: .barrier) {
            delegates[key] = delegate
        }
    }

    static func getDelegate(for key: String) -> OnMessageDelegate? {
        var delegate: OnMessageDelegate?
        delegatesQueue.sync {
            delegate = delegates[key]
        }
        return delegate
    }

    static func removeDelegate(for key: String) {
        delegatesQueue.async(flags: .barrier) {
            delegates.removeValue(forKey: key)
        }
    }

    static func addCallDelegate(for key: String, delegate: @escaping OnMessageDelegate) {
        callDelegatesQueue.async(flags: .barrier) {
            callDelegates[key] = delegate
        }
    }

    static func getCallDelegate(for key: String) -> OnMessageDelegate? {
        var delegate: OnMessageDelegate?
        callDelegatesQueue.sync {
            delegate = callDelegates[key]
        }
        return delegate
    }

    static func removeCallDelegate(for key: String) {
        callDelegatesQueue.async(flags: .barrier) {
            callDelegates.removeValue(forKey: key)
        }
    }

    // MARK: - Running Tasks

    private static let runningTaskQueue = DispatchQueue(
        label: "com.enconvo.ios.nodejstask.runningtask.queue", attributes: .concurrent)
    private static var _runningTasks: [String: Bool] = [:]

    static func markRunning(_ callId: String) {
        runningTaskQueue.async(flags: .barrier) {
            _runningTasks[callId] = true
        }
    }

    static func markComplete(_ callId: String) {
        runningTaskQueue.async(flags: .barrier) {
            _runningTasks.removeValue(forKey: callId)
        }
    }

    static var runningTaskIds: [String] {
        var result: [String] = []
        runningTaskQueue.sync {
            result = Array(_runningTasks.keys)
        }
        return result
    }

    // MARK: - Cancel / Terminate

    static func cancel(callId: String?) {
        guard let callId = callId else { return }
        markComplete(callId)
        do {
            try SocketUtil.sendRequestToClient(
                method: JobTalk.Methods.cancel, callId: callId, input: [:])
        } catch {
            print("[NodeJsTask] Cancel failed: \(error)")
        }
    }

    static func terminate(callIds: [String], all: Bool = false) {
        do {
            try SocketUtil.sendRequestToClient(
                method: JobTalk.Methods.terminate, callId: "", input: ["callIds": callIds, "all": all])
        } catch {
            print("[NodeJsTask] Terminate failed: \(error)")
        }
    }

    static func cancelAll() {
        runningTaskQueue.async(flags: .barrier) {
            _runningTasks.removeAll()
        }
        do {
            try SocketUtil.sendRequestToClient(
                method: JobTalk.Methods.cancelAllTask, callId: "cancelAllTask", input: [:])
        } catch {
            print("[NodeJsTask] CancelAll failed: \(error)")
        }
    }

    // MARK: - Execute Command

    struct TaskResult {
        let body: [String: Any]?
        let status: Int

        static func failure(_ message: String) -> TaskResult {
            TaskResult(body: ["error": message], status: 500)
        }
    }

    /// Execute a command via UDS and wait for the result.
    ///
    /// - Parameters:
    ///   - callId: Extension|Command key
    ///   - input: Command input parameters
    ///   - streamCallback: Optional callback for streaming responses
    /// - Returns: TaskResult with response body and status
    static func call(
        callId: String,
        stateId: String = UUID().uuidString,
        input: [String: Any] = [:],
        streamCallback: (([String: Any]) -> Void)? = nil
    ) async -> TaskResult {

        markRunning(callId)
        let requestId = UUID().uuidString

        let cleanupDelegates: () -> Void = {
            removeDelegate(for: requestId)
            removeCallDelegate(for: callId)
        }

        return await withTaskGroup(of: TaskResult.self) { group in
            // Task 1: The actual continuation-based operation
            group.addTask {
                await withCheckedContinuation { continuation in
                    var nillableContinuation: CheckedContinuation<TaskResult, Never>? = continuation

                    let delegate: OnMessageDelegate = { method, taskContext in
                        let params = taskContext?.inputParams ?? [:]
                        let payloads = params[JobTalk.Keys.payloads] as? [String: Any] ?? [:]

                        switch method {
                        case JobTalk.Methods.exit:
                            taskContext?.completion(["data": ""])
                            markComplete(callId)
                            cleanupDelegates()

                        case JobTalk.Methods.start:
                            taskContext?.completion(["data": ""])
                            let status = payloads["status"] as? Int ?? 0
                            nillableContinuation?.resume(
                                returning: TaskResult(body: payloads, status: status == 0 ? 200 : status))
                            nillableContinuation = nil
                            cleanupDelegates()

                        case JobTalk.Methods.responseStream:
                            taskContext?.completion(["data": ""])
                            streamCallback?(payloads)

                        case JobTalk.Methods.responseContext:
                            taskContext?.completion(["data": ""])
                            streamCallback?(payloads)

                        case JobTalk.Methods.responseEnd:
                            taskContext?.completion(["data": ""])
                            // responseEnd signals the stream is done; resume continuation
                            let status = payloads["status"] as? Int ?? 0
                            nillableContinuation?.resume(
                                returning: TaskResult(body: payloads, status: status == 0 ? 200 : status))
                            nillableContinuation = nil
                            markComplete(callId)
                            cleanupDelegates()

                        default:
                            break
                        }
                    }

                    addDelegate(for: requestId, delegate: delegate)
                    addCallDelegate(for: callId, delegate: delegate)

                    do {
                        try SocketUtil.sendRequestToClient(
                            method: JobTalk.Methods.start,
                            requestId: requestId,
                            callId: callId,
                            stateId: stateId,
                            input: input)
                    } catch {
                        nillableContinuation?.resume(returning: .failure("Send message failed: \(error)"))
                        nillableContinuation = nil
                        cleanupDelegates()
                        markComplete(callId)
                    }
                }
            }

            // Task 2: Timeout after 5 minutes
            group.addTask {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                return .failure("Command timed out after 300s")
            }

            let result = await group.next()!
            group.cancelAll()

            if result.status == 500 {
                cleanupDelegates()
                markComplete(callId)
            }

            return result
        }
    }
}
