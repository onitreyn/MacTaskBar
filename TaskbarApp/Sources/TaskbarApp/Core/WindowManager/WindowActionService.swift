import AppKit
import ApplicationServices

/// Действия над окном через Accessibility API: активировать, закрыть, свернуть/развернуть.
enum WindowActionService {

    /// Выводит окно на передний план и активирует его приложение.
    /// Используется обычным (левым) кликом по плитке — там нет modal tracking
    /// session меню, поэтому прямой вызов надёжен.
    static func activate(_ window: WindowInfo) {
        performActivation(window)
    }

    /// Надёжный вывод окна на передний план из КОНТЕКСТНОГО МЕНЮ.
    ///
    /// Проблема: при открытии контекстного меню наш TaskbarApp на короткое
    /// время становится frontmost (AppKit активирует нас, чтобы "хостить"
    /// меню и принимать события клавиатуры). После закрытия меню macOS
    /// возвращает фокус предыдущему приложению, и в этом post-menu контексте
    /// обычный `NSRunningApplication.activate(.activateIgnoringOtherApps)`
    /// НАДЁЖНО НЕ СРАБАТЫВАЕТ — цель не становится frontmost (эмпирически,
    /// см. ARCHITECTURE.md). Решение:
    ///   1. Активируем цель на СЛЕДУЮЩЕМ тике run loop — уже после того, как
    ///      синхронная часть закрытия меню завершена.
    ///   2. В `performActivation` активация делается максимально "жёсткой":
    ///      `.activateAllWindows` + прямое выставление `kAXFrontmostAttribute`
    ///      через Accessibility API (belt-and-suspenders — AX-атрибут
    ///      срабатывает даже когда `NSRunningApplication.activate` молчит).
    ///   3. Через ~0.25с проверяем, стала ли цель frontmost; если нет —
    ///      повторяем активацию (страховка от редких гонок возврата фокуса).
    ///   ВАЖНО: `NSApp.deactivate()` здесь НЕ вызываем — он оказался вредным
    ///   (см. ARCHITECTURE.md: с ним активация переставала работать совсем).
    static func bringToFront(_ window: WindowInfo) {
        DispatchQueue.main.async {
            performActivation(window)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard frontPID != window.ownerPID else { return }
            performActivation(window)
        }
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
