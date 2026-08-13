import AppKit
import ScreenCaptureKit

/// Разовый (по требованию) захват превью окна по CGWindowID через ScreenCaptureKit —
/// не постоянный стрим. Требует разрешение Screen Recording; при его отсутствии тихо
/// возвращает nil, UI просто не показывает превью.
///
/// Заимствовано из macTaskbar (https://github.com/damonroberts95/macTaskbar),
/// лицензия MIT, адаптировано под нашу архитектуру.
@MainActor
final class ThumbnailProvider {

    static let shared = ThumbnailProvider()

    private init() {}

    func captureThumbnail(windowID: CGWindowID) async -> NSImage? {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            return nil
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.width = max(Int(scWindow.frame.width), 1)
            config.height = max(Int(scWindow.frame.height), 1)
            config.showsCursor = false

            // SCScreenshotManager доступен с macOS 14; на 13 превью просто не показываем.
            guard #available(macOS 14.0, *) else { return nil }
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: cgImage, size: scWindow.frame.size)
        } catch {
            return nil
        }
    }
}
