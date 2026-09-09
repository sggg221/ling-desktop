import AppKit
import CoreGraphics

enum CaptureError: LocalizedError {
    case permission, failed(String), invalidImage
    var errorDescription: String? {
        switch self {
        case .permission: return "需要屏幕录制权限。请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许「百灵视觉助手」，再重新打开应用。"
        case .failed(let detail): return "截图失败：\(detail)"
        case .invalidImage: return "无法读取所选区域的截图，请重新框选。"
        }
    }
}

@MainActor
final class ScreenCapture {
    private var process: Process?

    var isRunning: Bool { process != nil }

    func selectRegion() async throws -> Data? {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw CaptureError.permission
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ling-capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("selection.png")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-s", "-x", "-t", "png", output.path]
        let errors = Pipe()
        task.standardError = errors
        process = task
        defer { process = nil }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
            do { try task.run() }
            catch { continuation.resume(throwing: error) }
        }
        // Escape in the system selection UI produces no file.
        guard FileManager.default.fileExists(atPath: output.path) else {
            if status > 1 {
                let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "\(status)"
                throw CaptureError.failed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return nil
        }
        let data = try Data(contentsOf: output)
        guard let source = NSBitmapImageRep(data: data), let cgImage = source.cgImage else {
            throw CaptureError.invalidImage
        }
        // Bound request size while retaining native pixels for ordinary selections.
        let scale = min(1, 2400 / Double(max(cgImage.width, cgImage.height)))
        if scale == 1 { return data }
        let width = max(1, Int(Double(cgImage.width) * scale))
        let height = max(1, Int(Double(cgImage.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaptureError.invalidImage
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: resized).representation(using: .png, properties: [:]) else {
            throw CaptureError.invalidImage
        }
        return png
    }

    func cancel() {
        if let process, process.isRunning { process.terminate() }
    }
}
