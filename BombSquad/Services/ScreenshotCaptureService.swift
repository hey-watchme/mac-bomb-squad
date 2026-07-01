import AppKit
import Foundation

enum ScreenshotCaptureError: LocalizedError {
    case cancelled
    case desktopUnavailable
    case failed(status: Int32)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "スクリーンショットをキャンセルしました。"
        case .desktopUnavailable:
            return "デスクトップの保存先を取得できませんでした。"
        case .failed(let status):
            return "スクリーンショットの撮影に失敗しました（終了コード: \(status)）。"
        case .outputMissing:
            return "スクリーンショットファイルを作成できませんでした。"
        }
    }
}

struct ScreenshotCaptureService {
    func captureInteractive() async throws -> ScreenshotAttachment {
        let outputURL = try Self.makeDesktopOutputURL()
        try? FileManager.default.removeItem(at: outputURL)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", outputURL.path]

                do {
                    try process.run()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        if !FileManager.default.fileExists(atPath: outputURL.path) {
                            continuation.resume(throwing: ScreenshotCaptureError.cancelled)
                        } else {
                            continuation.resume(throwing: ScreenshotCaptureError.failed(status: process.terminationStatus))
                        }
                        return
                    }

                    guard Self.hasNonEmptyFile(at: outputURL) else {
                        continuation.resume(throwing: ScreenshotCaptureError.outputMissing)
                        return
                    }

                    let size = Self.imagePixelSize(at: outputURL)
                    continuation.resume(returning: ScreenshotAttachment(
                        url: outputURL,
                        pixelWidth: size?.width,
                        pixelHeight: size?.height
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func makeDesktopOutputURL() throws -> URL {
        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            throw ScreenshotCaptureError.desktopUnavailable
        }
        let fileName = "BombSquad-\(Self.fileTimestamp()).png"
        return desktop.appendingPathComponent(fileName)
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func hasNonEmptyFile(at url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber
        else { return false }
        return size.intValue > 0
    }

    private static func imagePixelSize(at url: URL) -> (width: Int, height: Int)? {
        guard let image = NSImage(contentsOf: url),
              let representation = image.representations.first
        else { return nil }
        return (representation.pixelsWide, representation.pixelsHigh)
    }
}
