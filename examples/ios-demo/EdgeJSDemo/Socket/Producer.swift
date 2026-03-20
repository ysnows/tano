import Foundation

class Producer: UDSServerDelegate {
    func handleSocketServerStopped(_ server: UDSServer?) {}

    let producerTasks = ProducerTasks()

    func handleSocketServerMsgDict(
        _ params: [String: Any]?,
        from client: UDSClient?,
        error: Error?
    ) {
        guard let inputParams = params,
              let type = inputParams[JobTalk.Keys.type] as? String,
              let method = inputParams[JobTalk.Keys.method] as? String,
              let callId = inputParams[JobTalk.Keys.callId] as? String,
              let requestId = inputParams[JobTalk.Keys.requestId] as? String
        else {
            return
        }

        let sendId = inputParams[JobTalk.Keys.sendId] as? String ?? ""
        let stateId = inputParams[JobTalk.Keys.stateId] as? String ?? ""
        let needResult = inputParams[JobTalk.Keys.needResult] as? Bool ?? false
        let payloads = inputParams[JobTalk.Keys.payloads] as? [String: Any] ?? [:]

        // Thread-safe once-only wrapper
        let completionLock = NSLock()
        var completionCalled = false
        let safeCompletion: ([String: Any]) -> Void = { result in
            completionLock.lock()
            let alreadyCalled = completionCalled
            completionCalled = true
            completionLock.unlock()
            guard !alreadyCalled else { return }
            if needResult {
                self.sendResult(
                    method: method, callId: callId, requestId: requestId, payloads: result,
                    stateId: stateId, sendId: sendId, needResult: needResult, client: client)
            }
        }

        let result = producerTasks.handle(
            method: method,
            context: TaskContext(
                callId: callId, requestId: requestId, stateId: stateId, sendId: sendId, type: type,
                inputParams: inputParams, payloads: payloads, client: client
            ) { result in
                safeCompletion(result)
            })

        if result == false {
            // Check request-level delegate, then call-level delegate
            let requestDelegate = NodeJsTask.getDelegate(for: requestId)
            let callDelegate = NodeJsTask.getCallDelegate(for: callId)
            var handled = false

            if let delegate = requestDelegate {
                handled = true
                delegate(
                    method,
                    TaskContext(
                        callId: callId, requestId: requestId, stateId: stateId, sendId: sendId, type: type,
                        inputParams: inputParams, payloads: payloads, client: client
                    ) { result in
                        safeCompletion(result)
                    })
            } else if let delegate = callDelegate {
                handled = true
                delegate(
                    method,
                    TaskContext(
                        callId: callId, requestId: requestId, stateId: stateId, sendId: sendId, type: type,
                        inputParams: inputParams, payloads: payloads, client: client
                    ) { result in
                        safeCompletion(result)
                    })
            }

            // Broadcast to global delegates
            Task {
                let delegates = SocketManager.shared.getDelegates()
                await withTaskGroup(of: Void.self) { group in
                    for delegate in delegates {
                        group.addTask {
                            delegate(
                                method,
                                TaskContext(
                                    callId: callId, requestId: requestId, stateId: stateId, sendId: sendId,
                                    type: type, inputParams: inputParams,
                                    payloads: payloads, client: client
                                ) { result in
                                    safeCompletion(result)
                                })
                        }
                    }
                }

                // Only fire fallback if no specific delegate handled the message
                if !handled && delegates.isEmpty {
                    safeCompletion(["success": true])
                }
            }
        } else {
            // ProducerTasks handled it; fallback after 10s
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                safeCompletion(["success": true])
            }
        }
    }

    private func sendResult(
        method: String, callId: String, requestId: String,
        payloads: [String: Any],
        stateId: String? = nil,
        sendId: String? = nil,
        needResult: Bool?, client: UDSClient?
    ) {
        guard needResult != false else { return }
        do {
            let output: [String: Any] = [
                JobTalk.Keys.method: method,
                JobTalk.Keys.callId: callId,
                JobTalk.Keys.stateId: stateId ?? "",
                JobTalk.Keys.sendId: sendId ?? "",
                JobTalk.Keys.requestId: requestId,
                JobTalk.Keys.type: JobTalk.Types.response,
                JobTalk.Keys.payloads: payloads,
            ]
            try client?.sendMessageDict(output)
        } catch {
            print("[Producer] Failed to send result: \(error)")
        }
    }

    func handleConnectionError(_ error: Error?) {
        if let error = error {
            print("[Producer] Connection error: \(error)")
        }
    }
}
