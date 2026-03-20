import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @StateObject private var manager = EdgeJSManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Chat Demo (original WebView)
            WebBridgeView()
                .ignoresSafeArea(.keyboard)
                .tabItem {
                    Image(systemName: "bubble.left.fill")
                    Text("Chat")
                }
                .tag(0)

            // Tab 2: Settings (webapp-powered, like macOS OneSettingsView)
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(1)

            // Tab 3: Terminal
            WebappView(path: "/terminal")
                .ignoresSafeArea(.keyboard)
                .tabItem {
                    Image(systemName: "terminal.fill")
                    Text("Terminal")
                }
                .tag(2)
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                manager.onBackground()
            case .active:
                manager.onForeground()
            default:
                break
            }
        }
        .task {
            guard !manager.isRunning else { return }

            // 1. Start UDS Socket server
            SocketManager.shared.start()
            let socketPath = SocketManager.shared.socketPath
            print("[ContentView] Socket path: \(socketPath)")

            // 2. Determine extension path
            let extensionPath = Self.extensionPath()

            // 3. Start Edge.js runtime (server/index.js)
            if let path = Bundle.main.path(forResource: "index", ofType: "js", inDirectory: "js/server") {
                manager.start(
                    scriptPath: path,
                    socketPath: socketPath,
                    extensionPath: extensionPath
                )
            } else if let path = Bundle.main.path(forResource: "server", ofType: "js", inDirectory: "js") {
                manager.start(
                    scriptPath: path,
                    socketPath: socketPath,
                    extensionPath: extensionPath
                )
            }
        }
    }

    private static func extensionPath() -> String {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        if let baseUrl = urls.first {
            let extDir = baseUrl.appendingPathComponent("extensions")
            if !FileManager.default.fileExists(atPath: extDir.path) {
                try? FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)
            }
            return extDir.path
        }
        return ""
    }
}

// MARK: - Extension List View

struct ExtensionListView: View {
    @State private var extensions: [[String: Any]] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Discovering extensions...")
            } else if extensions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "puzzlepiece")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No extensions found")
                        .foregroundColor(.secondary)
                }
            } else {
                List(extensions.indices, id: \.self) { index in
                    let ext = extensions[index]
                    let extName = ext["name"] as? String ?? ""
                    // For settings, use the extension's primary command (or "chat" for llm_ios)
                    let cmdName = extName == "llm_ios" ? "chat" : (extName == "hello_world" ? "greet" : "chat_command")
                    NavigationLink(destination: ExtensionSettingsView(
                        commandKey: "\(extName)|\(cmdName)"
                    )) {
                        HStack {
                            Image(systemName: "puzzlepiece.extension.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(ext["title"] as? String ?? extName)
                                    .font(.headline)
                                Text("v\(ext["version"] as? String ?? "?") - \(ext["commandCount"] as? Int ?? 0) commands")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Extensions")
        .task {
            await loadExtensions()
        }
    }

    private func loadExtensions() async {
        guard let url = URL(string: "http://127.0.0.1:18899/api/extensions") else {
            isLoading = false
            return
        }

        // Retry up to 10 times (server may not be ready yet)
        for _ in 0..<10 {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let exts = json["extensions"] as? [[String: Any]] {
                    self.extensions = exts
                    self.isLoading = false
                    return
                }
            } catch {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        isLoading = false
    }
}
