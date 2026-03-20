import Foundation

struct TaskContext {
    let callId: String
    let requestId: String
    let stateId: String
    let sendId: String
    let type: String
    let inputParams: [String: Any]
    let payloads: [String: Any]
    let client: UDSClient?
    let completion: ([String: Any]) -> Void
}

typealias ProducerTask = (TaskContext) async -> Void
typealias OnTaskMessageDelegate = (_ method: String, _ taskContext: TaskContext) -> Void
typealias OnMessageDelegate = (_ method: String, _ taskContext: TaskContext?) -> Void
