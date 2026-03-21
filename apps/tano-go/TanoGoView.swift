import SwiftUI

struct TanoGoView: View {
    @State private var serverURL: String = ""
    @State private var isConnected = false
    @State private var recentServers: [String] = UserDefaults.standard.stringArray(forKey: "recentServers") ?? []
    @State private var errorMessage: String?
    @StateObject private var scanner = TanoNetworkScanner()

    var body: some View {
        if isConnected {
            TanoGoWebView(url: serverURL)
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    Button(action: { isConnected = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding()
                }
        } else {
            connectView
                .onAppear { scanner.startScanning() }
                .onDisappear { scanner.stopScanning() }
        }
    }

    // MARK: - Connect View

    var connectView: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Logo / Header
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                        Text("Tano Go")
                            .font(.largeTitle.bold())
                        Text("Connect to a Tano dev server")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 32)

                    // URL Input
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "link")
                                .foregroundColor(.secondary)
                            TextField("http://192.168.1.100:18899", text: $serverURL)
                                .textFieldStyle(.plain)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .keyboardType(.URL)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                        Button(action: connect) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                Text("Connect")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(serverURL.isEmpty ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .font(.headline)
                        }
                        .disabled(serverURL.isEmpty)
                    }
                    .padding(.horizontal)

                    // Error message
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Discovered servers
                    if !scanner.discoveredServers.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Discovered Servers", systemImage: "wifi")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(scanner.discoveredServers, id: \.name) { server in
                                Button(action: {
                                    serverURL = "http://\(server.host):\(server.port)"
                                    connect()
                                }) {
                                    HStack {
                                        Image(systemName: "server.rack")
                                            .foregroundColor(.blue)
                                        VStack(alignment: .leading) {
                                            Text(server.name)
                                                .font(.body)
                                            Text("\(server.host):\(server.port)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Recent servers
                    if !recentServers.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Recent Servers", systemImage: "clock")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(recentServers, id: \.self) { url in
                                Button(action: {
                                    serverURL = url
                                    connect()
                                }) {
                                    HStack {
                                        Image(systemName: "globe")
                                            .foregroundColor(.green)
                                        Text(url)
                                            .font(.body)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                            }

                            Button(action: clearRecent) {
                                Text("Clear Recent")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Actions

    private func connect() {
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add http:// if missing
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "http://\(url)"
            serverURL = url
        }

        guard URL(string: url) != nil else {
            errorMessage = "Invalid URL"
            return
        }

        errorMessage = nil
        saveRecent(url)
        isConnected = true
    }

    private func saveRecent(_ url: String) {
        var recents = recentServers
        recents.removeAll { $0 == url }
        recents.insert(url, at: 0)
        if recents.count > 5 {
            recents = Array(recents.prefix(5))
        }
        recentServers = recents
        UserDefaults.standard.set(recents, forKey: "recentServers")
    }

    private func clearRecent() {
        recentServers = []
        UserDefaults.standard.removeObject(forKey: "recentServers")
    }
}
