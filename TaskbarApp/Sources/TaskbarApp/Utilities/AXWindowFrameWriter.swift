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

    /// Читает текущий frame (position + size) окна через AX API.
    /// Возвращает `nil`, если атрибуты недоступны. Используется для проверки,
    /// что `apply` реально применил нужную геометрию (некоторые приложения
    /// применяют AX-ресайз не с первого раза).
    static func currentFrame(of axElement: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        let posResult = AXUIElementCopyAttributeValue(axElement, kAXPositionAttribute as CFString, &positionRef)
        let sizeResult = AXUIElementCopyAttributeValue(axElement, kAXSizeAttribute as CFString, &sizeRef)

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
