import AppKit

/// Сопоставляет AX-окна с on-screen снапшотом `CGWindowList`, чтобы получить
/// их `CGWindowID` (нужен для превью через ScreenCaptureKit).
///
/// Публичного способа получить CGWindowID прямо из AXUIElement нет, поэтому
/// сверяем AX-фрейм с границами on-screen окон. Если снапшот пуст, окно просто
/// не получит windowNumber (превью не покажется) — мягкая деградация.
///
/// Заимствовано из macTaskbar (https://github.com/damonroberts95/macTaskbar),
/// лицензия MIT, адаптировано под нашу архитектуру.
enum CGWindowResolver {

    struct OnScreenWindow {
        let ownerPID: pid_t
        let windowNumber: CGWindowID
        let bounds: CGRect
    }

    /// Список окон, физически видимых на экране прямо сейчас.
    /// `optionOnScreenOnly` отсекает свёрнутые и скрытые окна.
    static func currentOnScreenWindows() -> [OnScreenWindow] {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: AnyObject]] else {
            return []
        }

        return info.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let windowNumber = entry[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"], let y = boundsDict["Y"],
                  let width = boundsDict["Width"], let height = boundsDict["Height"]
            else {
                return nil
            }
            return OnScreenWindow(
                ownerPID: pid,
                windowNumber: windowNumber,
                bounds: CGRect(x: x, y: y, width: width, height: height)
            )
        }
    }

    /// Сравнивает AX-фрейм окна с on-screen границами, округляя до целых точек —
    /// AX и CGWindowList могут различаться на доли пикселя.
    static func matches(_ axFrame: CGRect, _ onScreen: OnScreenWindow, pid: pid_t) -> Bool {
        guard onScreen.ownerPID == pid else { return false }
        return abs(axFrame.origin.x - onScreen.bounds.origin.x) < 2
            && abs(axFrame.origin.y - onScreen.bounds.origin.y) < 2
            && abs(axFrame.width - onScreen.bounds.width) < 2
            && abs(axFrame.height - onScreen.bounds.height) < 2
    }
}
