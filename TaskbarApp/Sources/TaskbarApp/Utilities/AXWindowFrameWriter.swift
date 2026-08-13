import ApplicationServices
import CoreGraphics

/// Запись позиции/размера окна через Accessibility API. Общий код для всех
/// сервисов, которые двигают/ресайзят чужие окна (`WindowSnapService`,
/// `WindowScreenMoveService`) — чтобы не дублировать порядок вызовов.
enum AXWindowFrameWriter {

    /// Применяет frame (в координатах Quartz — той же системе, в которой
    /// задан `WindowInfo.frame`) к окну через `axElement`.
    static func apply(_ frame: CGRect, to axElement: AXUIElement) {
        var origin = frame.origin
        var size = frame.size

        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return }

        // Порядок важен: сначала размер, потом позиция. Если сначала выставить
        // позицию для окна, которое сейчас больше целевого размера, некоторые
        // приложения (особенно с минимальным window size) могут скорректировать
        // координаты неожиданным образом при последующем ресайзе.
        AXUIElementSetAttributeValue(axElement, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(axElement, kAXPositionAttribute as CFString, positionValue)
    }
}
