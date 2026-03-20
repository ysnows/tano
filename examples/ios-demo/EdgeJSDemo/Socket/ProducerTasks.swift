import Foundation
import UIKit
import AVFoundation
import LocalAuthentication
import CryptoKit
import UserNotifications

class ProducerTasks: NSObject {

    lazy var tasks: [String: ProducerTask] = {
        [
            "connected": connected,
            "showToast": showToast,
            "showHUD": showHUD,
            "copy": copyText,
            "getLatestClipboard": getLatestClipboard,
            "playAudio": playAudio,
            "stopAudio": stopAudio,
            "pauseAudio": pauseAudio,
            "resumeAudio": resumeAudio,
            "setKV": setKV,
            "getKV": getKV,
            "writeFile": writeFile,
            "readFile": readFile,
            "encrypt": encrypt,
            "decrypt": decrypt,
            "openURL": openURL,
            "hapticFeedback": hapticFeedback,
            "shareSheet": shareSheet,
            "biometricAuth": biometricAuth,
            "pushNotification": pushNotification,
            "sqlite": sqliteHandler,
        ]
    }()

    /// Try to handle a method. Returns true if handled.
    func handle(method: String, context: TaskContext) -> Bool {
        if let task = tasks[method] {
            Task {
                await task(context)
            }
            return true
        }
        return false
    }

    // MARK: - connected

    private func connected(_ context: TaskContext) async {
        print("[ProducerTasks] Node.js connected via UDS")
        context.completion(["status": "connected"])
    }

    // MARK: - showToast / showHUD

    private func showToast(_ context: TaskContext) async {
        let message = context.payloads["message"] as? String ?? context.payloads["content"] as? String ?? ""
        let title = context.payloads["title"] as? String ?? "Notice"
        print("[ProducerTasks] showToast: \(message)")

        await MainActor.run {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = scene.windows.first?.rootViewController else { return }

            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))

            // Find the topmost presented VC
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(alert, animated: true)
        }
        context.completion(["success": true])
    }

    private func showHUD(_ context: TaskContext) async {
        let message = context.payloads["message"] as? String ?? ""
        print("[ProducerTasks] showHUD: \(message)")

        await MainActor.run {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first else { return }

            let label = UILabel()
            label.text = message
            label.textColor = .white
            label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
            label.textAlignment = .center
            label.layer.cornerRadius = 10
            label.clipsToBounds = true
            label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            label.numberOfLines = 0

            let padding: CGFloat = 32
            let maxWidth = window.bounds.width - 80
            let size = label.sizeThatFits(CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude))
            label.frame = CGRect(
                x: (window.bounds.width - size.width - padding) / 2,
                y: window.bounds.height - 140,
                width: size.width + padding,
                height: size.height + 20
            )

            window.addSubview(label)

            UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: {
                label.alpha = 0
            }, completion: { _ in
                label.removeFromSuperview()
            })
        }
        context.completion(["success": true])
    }

    // MARK: - Clipboard

    private func copyText(_ context: TaskContext) async {
        let text = context.payloads["text"] as? String ?? context.payloads["content"] as? String ?? ""
        await MainActor.run {
            UIPasteboard.general.string = text
        }
        print("[ProducerTasks] Copied \(text.count) chars to clipboard")
        context.completion(["success": true])
    }

    private func getLatestClipboard(_ context: TaskContext) async {
        var content = ""
        await MainActor.run {
            content = UIPasteboard.general.string ?? ""
        }
        context.completion(["content": content])
    }

    // MARK: - Audio (AVFoundation)

    private static var audioPlayer: AVAudioPlayer?

    private func playAudio(_ context: TaskContext) async {
        let filePath = context.payloads["path"] as? String ?? context.payloads["filePath"] as? String ?? ""
        guard !filePath.isEmpty else {
            context.completion(["error": "No file path"])
            return
        }

        let url = URL(fileURLWithPath: filePath)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            ProducerTasks.audioPlayer = player
            player.play()
            context.completion(["success": true, "duration": player.duration])
        } catch {
            context.completion(["error": error.localizedDescription])
        }
    }

    private func stopAudio(_ context: TaskContext) async {
        ProducerTasks.audioPlayer?.stop()
        ProducerTasks.audioPlayer = nil
        context.completion(["success": true])
    }

    private func pauseAudio(_ context: TaskContext) async {
        ProducerTasks.audioPlayer?.pause()
        context.completion(["success": true])
    }

    private func resumeAudio(_ context: TaskContext) async {
        ProducerTasks.audioPlayer?.play()
        context.completion(["success": true])
    }

    // MARK: - Key-Value Store (UserDefaults)

    private func setKV(_ context: TaskContext) async {
        let key = context.payloads["key"] as? String ?? ""
        let value = context.payloads["value"]
        guard !key.isEmpty else {
            context.completion(["error": "No key"])
            return
        }
        UserDefaults.standard.set(value, forKey: "enconvo_kv_\(key)")
        context.completion(["success": true])
    }

    private func getKV(_ context: TaskContext) async {
        let key = context.payloads["key"] as? String ?? ""
        guard !key.isEmpty else {
            context.completion(["error": "No key"])
            return
        }
        let value = UserDefaults.standard.object(forKey: "enconvo_kv_\(key)")
        if let v = value {
            context.completion(["value": v])
        } else {
            context.completion(["value": NSNull()])
        }
    }

    // MARK: - File Operations

    private func writeFile(_ context: TaskContext) async {
        let path = context.payloads["path"] as? String ?? context.payloads["filePath"] as? String ?? ""
        let content = context.payloads["content"] as? String ?? ""
        let base64 = context.payloads["base64"] as? String

        guard !path.isEmpty else {
            context.completion(["error": "No file path"])
            return
        }

        do {
            if let b64 = base64, let data = Data(base64Encoded: b64) {
                try data.write(to: URL(fileURLWithPath: path))
            } else {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
            }
            context.completion(["success": true])
        } catch {
            context.completion(["error": error.localizedDescription])
        }
    }

    private func readFile(_ context: TaskContext) async {
        let path = context.payloads["path"] as? String ?? context.payloads["filePath"] as? String ?? ""
        guard !path.isEmpty else {
            context.completion(["error": "No file path"])
            return
        }

        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            context.completion(["content": content])
        } catch {
            context.completion(["error": error.localizedDescription])
        }
    }

    // MARK: - Encryption (CryptoKit)

    private func encrypt(_ context: TaskContext) async {
        let text = context.payloads["text"] as? String ?? context.payloads["content"] as? String ?? ""
        let keyString = context.payloads["key"] as? String ?? "enconvo_default_key_32bytes!!"

        guard let data = text.data(using: .utf8) else {
            context.completion(["error": "Invalid text"])
            return
        }

        // Use SHA256 of key to get a consistent 32-byte key
        let keyData = SHA256.hash(data: keyString.data(using: .utf8)!)
        let symmetricKey = SymmetricKey(data: keyData)

        do {
            let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
            let combined = sealedBox.combined!
            context.completion(["encrypted": combined.base64EncodedString()])
        } catch {
            context.completion(["error": error.localizedDescription])
        }
    }

    private func decrypt(_ context: TaskContext) async {
        let encrypted = context.payloads["encrypted"] as? String ?? context.payloads["content"] as? String ?? ""
        let keyString = context.payloads["key"] as? String ?? "enconvo_default_key_32bytes!!"

        guard let data = Data(base64Encoded: encrypted) else {
            context.completion(["error": "Invalid base64"])
            return
        }

        let keyData = SHA256.hash(data: keyString.data(using: .utf8)!)
        let symmetricKey = SymmetricKey(data: keyData)

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decrypted = try AES.GCM.open(sealedBox, using: symmetricKey)
            context.completion(["decrypted": String(data: decrypted, encoding: .utf8) ?? ""])
        } catch {
            context.completion(["error": error.localizedDescription])
        }
    }

    // MARK: - openURL

    private func openURL(_ context: TaskContext) async {
        let urlString = context.payloads["url"] as? String ?? ""
        guard let url = URL(string: urlString) else {
            context.completion(["error": "Invalid URL"])
            return
        }

        await MainActor.run {
            UIApplication.shared.open(url)
        }
        context.completion(["success": true])
    }

    // MARK: - iOS-specific: Haptic Feedback

    private func hapticFeedback(_ context: TaskContext) async {
        let style = context.payloads["style"] as? String ?? "medium"
        await MainActor.run {
            let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
            switch style {
            case "light": feedbackStyle = .light
            case "heavy": feedbackStyle = .heavy
            case "rigid": feedbackStyle = .rigid
            case "soft": feedbackStyle = .soft
            default: feedbackStyle = .medium
            }
            let generator = UIImpactFeedbackGenerator(style: feedbackStyle)
            generator.impactOccurred()
        }
        context.completion(["success": true])
    }

    // MARK: - iOS-specific: Share Sheet

    private func shareSheet(_ context: TaskContext) async {
        let text = context.payloads["text"] as? String ?? context.payloads["content"] as? String ?? ""
        let urlString = context.payloads["url"] as? String

        await MainActor.run {
            var items: [Any] = []
            if !text.isEmpty { items.append(text) }
            if let us = urlString, let url = URL(string: us) { items.append(url) }
            guard !items.isEmpty else { return }

            let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)

            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = scene.windows.first?.rootViewController else { return }

            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }

            // iPad popover
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            }

            topVC.present(activityVC, animated: true)
        }
        context.completion(["success": true])
    }

    // MARK: - iOS-specific: Biometric Authentication

    private func biometricAuth(_ context: TaskContext) async {
        let reason = context.payloads["reason"] as? String ?? "Authenticate to continue"

        let laContext = LAContext()
        var error: NSError?

        guard laContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            context.completion(["success": false, "error": error?.localizedDescription ?? "Biometrics unavailable"])
            return
        }

        do {
            let success = try await laContext.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason)
            context.completion(["success": success])
        } catch {
            context.completion(["success": false, "error": error.localizedDescription])
        }
    }

    // MARK: - iOS-specific: Push Notification

    private func pushNotification(_ context: TaskContext) async {
        let title = context.payloads["title"] as? String ?? "Enconvo"
        let body = context.payloads["body"] as? String ?? context.payloads["message"] as? String ?? ""
        let identifier = context.payloads["id"] as? String ?? UUID().uuidString

        let center = UNUserNotificationCenter.current()

        // Request permission if needed
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                context.completion(["error": "Notification permission denied"])
                return
            }
        } catch {
            context.completion(["error": error.localizedDescription])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
            context.completion(["success": true])
        } catch {
            context.completion(["error": error.localizedDescription])
        }
    }

    // MARK: - SQLite Bridge

    private func sqliteHandler(_ context: TaskContext) async {
        SQLiteBridge.shared.handle(context: context)
    }
}
