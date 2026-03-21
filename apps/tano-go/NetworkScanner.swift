import Foundation
import Network

/// Scans the local network for Tano dev servers advertised via Bonjour (mDNS).
///
/// Dev servers register the `_tano._tcp` service type so that Tano Go can
/// discover them automatically without manual URL entry.
class TanoNetworkScanner: ObservableObject {
    @Published var discoveredServers: [(host: String, port: UInt16, name: String)] = []
    private var browser: NWBrowser?

    func startScanning() {
        let params = NWParameters()
        browser = NWBrowser(for: .bonjour(type: "_tano._tcp", domain: nil), using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.discoveredServers = results.compactMap { result in
                    if case .service(let name, _, _, _) = result.endpoint {
                        return (host: name, port: 18899, name: name)
                    }
                    return nil
                }
            }
        }

        browser?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[Tano Go] Network scanner ready")
            case .failed(let error):
                print("[Tano Go] Network scanner failed: \(error)")
            default:
                break
            }
        }

        browser?.start(queue: .main)
    }

    func stopScanning() {
        browser?.cancel()
        browser = nil
    }
}
