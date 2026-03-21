import SwiftUI
import WebKit

struct TanoGoWebView: UIViewRepresentable {
    let url: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userController = WKUserContentController()

        // Inject Tano bridge JS at document start
        let bridgeScript = WKUserScript(
            source: TanoGoBridgeJS.script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userController.addUserScript(bridgeScript)

        config.userContentController = userController

        // Allow mixed content and local networking for dev
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)

        // Enable Safari Web Inspector for debugging
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        // Allow swipe back/forward navigation
        webView.allowsBackForwardNavigationGestures = true

        if let requestURL = URL(string: self.url) {
            webView.load(URLRequest(url: requestURL))
            print("[Tano Go] Loading dev server: \(requestURL)")
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
