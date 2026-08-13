import AppKit

/// Определяет, какие окна находятся на текущем Space, сверяя on-screen снапшот
/// `CGWindowList` (только видимые сейчас окна) с окнами, перечисленными через AX.
///
/// Публичного per-window Space ID не существует, поэтому это самый хрупкий участок
/// API. Реализован аддитивно: если снапшот получить не удалось (пустой список),
/// вызывающий код просто не фильтрует окна по Space (мягкая деградация).
///
/// Заимствовано из macTaskbar (https://github.com/damonroberts95/macTaskbar),
/// лицензия MIT, адаптировано под нашу архитектуру.
enum SpaceObserver {

    struct OnScreenWindow {
        let ownerPID: pid_t
        let windowNumber: CGWindowID
        let bounds: CGRect
    }

    /// Список окон, физически видимых на текущем Space прямо сейчас.
    /// `optionOnScreenOnly` отсекает окна на других Space'ах и свёрнутые.
    static func currentSpaceOnScreenWindows() -> [OnScreenWindow] {
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
