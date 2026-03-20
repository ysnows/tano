import Foundation

class SocketUtil {

    static func cancelTask(callId: String, chatConversationId: String) {
        do {
            try SocketUtil.sendRequestToClient(
                method: JobTalk.Methods.cancel, callId: callId, stateId: chatConversationId, input: [:])
        } catch {
            print("[SocketUtil] Send cancel failed: \(error)")
        }
    }

    static func sendRequestToClient(
        method: String,
        requestId: String = UUID().uuidString,
        callId: String,
        stateId: String? = nil,
        input: [String: Any] = [:]
    ) throws {
        guard let clients = SocketManager.shared.server?.sockClients, !clients.isEmpty else {
            return
        }
        for client in clients {
            let params: [String: Any] = [
                JobTalk.Keys.method: method,
                JobTalk.Keys.callId: callId,
                JobTalk.Keys.stateId: stateId ?? "",
                JobTalk.Keys.requestId: requestId,
                JobTalk.Keys.type: JobTalk.Types.request,
                JobTalk.Keys.payloads: input,
            ]
            try client.sendMessageDict(params)
        }
    }

    static func sendDataToClient(data: Data) {
        guard let clients = SocketManager.shared.server?.sockClients else { return }
        clients.forEach { client in
            do {
                try client.sendMessageData(data: data)
            } catch {
                print("[SocketUtil] Send data failed: \(error)")
            }
        }
    }

    static func sendResult(
        method: String,
        callId: String,
        requestId: String,
        payloads: [String: Any],
        stateId: String? = nil,
        type: String = JobTalk.Types.request
    ) {
        SocketManager.shared.server?.sockClients.forEach { client in
            do {
                let params: [String: Any] = [
                    JobTalk.Keys.method: method,
                    JobTalk.Keys.stateId: stateId ?? "",
                    JobTalk.Keys.callId: callId,
                    JobTalk.Keys.requestId: requestId,
                    JobTalk.Keys.type: type,
                    JobTalk.Keys.payloads: payloads,
                ]
                try client.sendMessageDict(params)
            } catch {
                print("[SocketUtil] Send result failed: \(error)")
            }
        }
    }

    static func sendResponse(
        method: String,
        callId: String,
        requestId: String,
        payloads: [String: Any],
        type: String = JobTalk.Types.response
    ) {
        SocketManager.shared.server?.sockClients.forEach { client in
            do {
                let params: [String: Any] = [
                    JobTalk.Keys.method: method,
                    JobTalk.Keys.callId: callId,
                    JobTalk.Keys.requestId: requestId,
                    JobTalk.Keys.type: type,
                    JobTalk.Keys.payloads: payloads,
                ]
                try client.sendMessageDict(params)
            } catch {
                print("[SocketUtil] Send response failed: \(error)")
            }
        }
    }
}
