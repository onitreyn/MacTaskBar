import AppKit
import ApplicationServices

/// Читает список окон конкретного приложения через Accessibility API.
///
/// Один экземпляр на приложение (pid). Не хранит состояние между вызовами —
/// каждый вызов `fetchWindows()` заново опрашивает AX-дерево приложения.
/// Это дороже, чем инкрементальные обновления через AXObserver, но для MVP
/// (Фаза 1) достаточно и значительно проще в отладке.
final class WindowManager {

    private let appElement: AXUIElement
    private let pid: pid_t

    init(pid: pid_t) {
        self.pid = pid
        self.appElement = AXUIElementCreateApplication(pid)
    }

    /// Возвращает окна приложения, пригодные для показа в панели задач.
    /// Отфильтровывает служебные окна без роли kAXWindowRole и окна без заголовка,
    /// которые обычно являются HUD/panel-элементами интерфейса.
    func fetchWindows() -> [WindowInfo] {
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )

        guard result == .success, let windowsRef else { return [] }
        guard let axWindows = windowsRef as? [AXUIElement] else { return [] }

        return axWindows.compactMap { axWindow in
            makeWindowInfo(from: axWindow)
        }
    }

    private func makeWindowInfo(from axWindow: AXUIElement) -> WindowInfo? {
        // Роль окна — отсекаем панели/HUD, которые не являются обычными окнами документа.
        guard let role = copyStringAttribute(axWindow, kAXRoleAttribute), role == kAXWindowRole as String else {
            return nil
        }

        let title = copyStringAttribute(axWindow, kAXTitleAttribute) ?? ""
        let isMinimized = copyBoolAttribute(axWindow, kAXMinimizedAttribute) ?? false
        let frame = copyFrameAttribute(axWindow) ?? .zero

        // Идентификатор строим из pid + указателя на AXUIElement, приведённого к строке.
        // AXUIElement — CFType, поэтому используем его CFHash как стабильный (в рамках сессии) ключ.
        let elementHash = CFHash(axWindow)
        let id = "\(pid)-\(elementHash)"

        return WindowInfo(
            id: id,
            ownerPID: pid,
            axElement: axWindow,
            title: title,
            isMinimized: isMinimized,
            frame: frame
        )
    }

    // MARK: - AX attribute helpers

    private func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        guard result == .success else { return nil }
        return ref as? String
    }

    private func copyBoolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        guard result == .success else { return nil }
        return (ref as? Bool) ?? (ref as? NSNumber)?.boolValue
    }

    private func copyFrameAttribute(_ element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        let posResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        guard posResult == .success, sizeResult == .success,
              let positionRef, let sizeRef else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero

        // swiftlint:disable force_cast
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        // swiftlint:enable force_cast

        return CGRect(origin: origin, size: size)
    }
}
