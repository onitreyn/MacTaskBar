import AppKit
import ApplicationServices

/// Проверка и запрос разрешения Accessibility, без которого AXUIElement API не работает.
final class PermissionsService {

    static let shared = PermissionsService()

    private init() {}

    /// true, если приложению уже выдано разрешение Accessibility.
    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Показывает системный диалог запроса разрешения (если ещё не выдано).
    /// Диалог откроет System Settings → Privacy & Security → Accessibility.
    func requestAccessibilityIfNeeded() {
        guard !isAccessibilityGranted else { return }
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Периодическая проверка — полезно, чтобы обновить UI после того,
    /// как пользователь вручную выдал разрешение в System Settings.
    func pollUntilGranted(interval: TimeInterval = 1.0, onGranted: @escaping () -> Void) {
        guard !isAccessibilityGranted else {
            onGranted()
            return
        }
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                DispatchQueue.main.async {
                    onGranted()
                }
            }
        }
    }
}
