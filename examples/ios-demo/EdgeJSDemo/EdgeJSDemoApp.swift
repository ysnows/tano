import SwiftUI

@main
struct EdgeJSDemoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        // Forward memory warning to EdgeJSManager to clear JS caches
        // ContentView owns the manager, but we can send via SocketUtil directly
        do {
            try SocketUtil.sendRequestToClient(
                method: "clearCache",
                callId: "system",
                input: [:]
            )
        } catch {
            print("[AppDelegate] Failed to send clearCache: \(error)")
        }
    }
}
