import Foundation
import TanoBridge

#if canImport(UIKit)
import UIKit
#endif

/// Native camera & photo-picker plugin for Tano.
///
/// On iOS, uses UIImagePickerController to capture photos or pick from the
/// photo library. On macOS (test environment), returns a stub error since
/// the camera API is unavailable.
///
/// Supported methods: `takePicture`, `pickImage`.
public final class CameraPlugin: TanoPlugin {

    // MARK: - TanoPlugin conformance

    public static let name = "camera"
    public static let permissions: [String] = ["camera", "photos"]

    public init() {}

    // MARK: - Routing

    public func handle(method: String, params: [String: Any]) async throws -> Any? {
        switch method {
        case "takePicture":
            return try await takePicture(params: params)
        case "pickImage":
            return try await pickImage(params: params)
        default:
            throw CameraPluginError.unknownMethod(method)
        }
    }

    // MARK: - takePicture

    private func takePicture(params: [String: Any]) async throws -> [String: Any] {
        #if os(iOS)
        let cameraDirection = params["camera"] as? String ?? "back"

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                    continuation.resume(throwing: CameraPluginError.cameraUnavailable)
                    return
                }

                let picker = UIImagePickerController()
                picker.sourceType = .camera
                picker.cameraDevice = cameraDirection == "front" ? .front : .rear

                let delegate = CameraDelegate { result in
                    continuation.resume(with: result)
                }

                // Prevent delegate from being deallocated
                objc_setAssociatedObject(picker, &CameraPlugin.delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
                picker.delegate = delegate

                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootVC = scene.windows.first?.rootViewController else {
                    continuation.resume(throwing: CameraPluginError.noViewController)
                    return
                }

                var topVC = rootVC
                while let presented = topVC.presentedViewController {
                    topVC = presented
                }

                topVC.present(picker, animated: true)
            }
        }
        #else
        // macOS / test stub
        throw CameraPluginError.cameraUnavailable
        #endif
    }

    // MARK: - pickImage

    private func pickImage(params: [String: Any]) async throws -> [String: Any] {
        #if os(iOS)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
                    continuation.resume(throwing: CameraPluginError.photoLibraryUnavailable)
                    return
                }

                let picker = UIImagePickerController()
                picker.sourceType = .photoLibrary

                let delegate = CameraDelegate { result in
                    continuation.resume(with: result)
                }

                objc_setAssociatedObject(picker, &CameraPlugin.delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
                picker.delegate = delegate

                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootVC = scene.windows.first?.rootViewController else {
                    continuation.resume(throwing: CameraPluginError.noViewController)
                    return
                }

                var topVC = rootVC
                while let presented = topVC.presentedViewController {
                    topVC = presented
                }

                topVC.present(picker, animated: true)
            }
        }
        #else
        // macOS / test stub
        throw CameraPluginError.cameraUnavailable
        #endif
    }

    // MARK: - Associated object key

    private static var delegateKey: UInt8 = 0
}

// MARK: - iOS Camera Delegate

#if os(iOS)
private final class CameraDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let completion: (Result<[String: Any], Error>) -> Void

    init(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        self.completion = completion
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)

        guard let image = info[.originalImage] as? UIImage else {
            completion(.failure(CameraPluginError.noImageReturned))
            return
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
            completion(.failure(CameraPluginError.encodingFailed))
            return
        }

        let base64 = jpegData.base64EncodedString()
        let result: [String: Any] = [
            "base64": base64,
            "width": Int(image.size.width),
            "height": Int(image.size.height),
        ]
        completion(.success(result))
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        completion(.failure(CameraPluginError.cancelled))
    }
}
#endif

// MARK: - Errors

public enum CameraPluginError: Error, LocalizedError {
    case unknownMethod(String)
    case cameraUnavailable
    case photoLibraryUnavailable
    case noViewController
    case noImageReturned
    case encodingFailed
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unknownMethod(let m):
            return "Unknown camera plugin method: \(m)"
        case .cameraUnavailable:
            return "Camera not available in test environment"
        case .photoLibraryUnavailable:
            return "Photo library not available in test environment"
        case .noViewController:
            return "No root view controller available to present picker"
        case .noImageReturned:
            return "No image was returned from the picker"
        case .encodingFailed:
            return "Failed to encode image as JPEG"
        case .cancelled:
            return "Image picker was cancelled by the user"
        }
    }
}
