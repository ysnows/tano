import SwiftUI
import TanoCore
import TanoBridge
import TanoWebView
import TanoPluginSQLite
import TanoPluginClipboard
import TanoPluginHaptics
import TanoPluginKeychain
import TanoPluginFS
import TanoPluginCrypto

@main
struct TanoDemoApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .onAppear { appState.start() }
                .onDisappear { appState.stop() }
        }
    }
}

class AppState: ObservableObject {
    var runtime: TanoRuntime?
    var pluginRouter = PluginRouter()

    func start() {
        // Register plugins
        pluginRouter.register(plugin: SQLitePlugin())
        pluginRouter.register(plugin: ClipboardPlugin())
        pluginRouter.register(plugin: HapticsPlugin())
        pluginRouter.register(plugin: KeychainPlugin())
        pluginRouter.register(plugin: FSPlugin(basePath: appDataPath))
        pluginRouter.register(plugin: CryptoPlugin())

        // Start runtime
        let serverJS = Bundle.main.path(forResource: "server", ofType: "js") ?? ""
        let config = TanoConfig(serverEntry: serverJS, env: ["TANO_VERSION": "0.1.0"])
        runtime = TanoRuntime(config: config)
        runtime?.start()
    }

    func stop() {
        runtime?.stop()
    }

    var appDataPath: String {
        NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
    }
}
