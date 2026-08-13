import AppKit
import ApplicationServices

/// Действия над окном через Accessibility API: активировать, закрыть, свернуть/развернуть.
enum WindowActionService {

    /// Выводит окно на передний план и активирует его приложение.
    static func activate(_ window: WindowInfo) {
        performActivation(window)
    }

    // MARK: - Private

    private static func performActivation(_ window: WindowInfo) {
        // Снимаем флаг "свёрнуто", если он был установлен.
        AXUIElementSetAttributeValue(
            window.axElement,
            kAXMinimizedAttribute as CFString,
            kCFBooleanFalse
        )

        // Поднимаем окно (AXRaise action).
        AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)

        // Активируем владельца окна как приложение переднего плана.
        if let app = NSRunningApplication(processIdentifier: window.ownerPID) {
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }

        // Belt-and-suspenders: прямое выставление frontmost через Accessibility
        // API — в post-menu контексте `NSRunningApplication.activate` иногда
        // молча игнорируется системой, а AX-атрибут срабатывает надёжнее.
        let appElement = AXUIElementCreateApplication(window.ownerPID)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    /// Сворачивает окно в панель задач (аналог минимизации в Dock).
    static func minimize(_ window: WindowInfo) {
        AXUIElementSetAttributeValue(
            window.axElement,
            kAXMinimizedAttribute as CFString,
            kCFBooleanTrue
        )
    }

    /// Закрывает окно, если у него есть системная кнопка закрытия (AXCloseButton).
    static func close(_ window: WindowInfo) {
        var closeButtonRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            window.axElement,
            kAXCloseButtonAttribute as CFString,
            &closeButtonRef
        )
        guard result == .success, let closeButtonRef else { return }
        // swiftlint:disable:next force_cast
        let closeButton = closeButtonRef as! AXUIElement
        AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
    }

    /// Полностью завершает приложение-владельца окна (аналог Quit в Dock).
    static func terminateApp(pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.terminate()
        }
    }
}
