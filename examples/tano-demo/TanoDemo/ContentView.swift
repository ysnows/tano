import SwiftUI
import TanoWebView
import TanoBridge

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        #if canImport(UIKit)
        TanoWebView(
            config: TanoWebViewConfig(
                entry: "index.html",
                devMode: false,
                serverPort: 18899
            ),
            pluginRouter: appState.pluginRouter
        )
        .ignoresSafeArea()
        #else
        Text("TanoWebView is iOS-only")
        #endif
    }
}
