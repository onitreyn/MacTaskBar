import ApplicationServices
import CoreGraphics

/// Запись позиции/размера окна через Accessibility API. Общий код для всех
/// сервисов, которые двигают/ресайзят чужие окна (`WindowSnapService`,
/// `WindowScreenMoveService`).
///
/// Важно: AX-записи на мульти-мониторных конфигурациях с разным scale-фактором
/// (например, Retina MacBook + внешний FullHD) применяются асинхронно и «гоняются»,
/// поэтому одиночная пара «размер + позиция» ненадёжна: либо размер, либо позиция
/// теряются (зависит от направления и порядка). Универсальная последовательность
/// размер → позиция → размер → позиция с паузами покрывает оба случая:
/// - рост (снап на весь экран): первый «размер» может вылезти за край и быть
///   отброшен, но после переноса позиции повторный «размер» применяется;
/// - сжатие + перенос (перемещение на меньший экран): первый «размер» уменьшает
///   окно, чтобы его вообще можно было перенести на меньший экран, затем позиция
///   переносит, повторные шаги страхуют.
enum AXWindowFrameWriter {

    /// Допуск в points при сравнении текущего frame окна с целевым — AX API
    /// возвращает координаты с плавающей точкой, точное совпадение не
    /// гарантировано даже сразу после того, как мы сами его выставили.
    static let toleranceInPoints: CGFloat = 2

    private static let stepDelay: TimeInterval = 0.3

    // MARK: - Public

    /// Применяет frame (в координатах Quartz — той же системе, в которой
    /// задан `WindowInfo.frame`) к окну через `axElement`. Выполняет
    /// последовательность размер→позиция→размер→позиция с паузами, затем
    /// через короткую паузу проверяет фактический frame и при несовпадении
    /// повторяет всю последовательность (до `attemptsLeft` раз).
    static func applyWithRetry(_ frame: CGRect, to axElement: AXUIElement, attemptsLeft: Int = 2) {
        applySequence(frame, to: axElement)
        schedule(after: stepDelay) {
            guard let current = currentFrame(of: axElement) else { return }
            if !isApproximatelyEqual(current, frame), attemptsLeft > 0 {
                applyWithRetry(frame, to: axElement, attemptsLeft: attemptsLeft - 1)
            }
        }
    }

    /// Читает текущий frame (position + size) окна через AX API.
    /// Возвращает `nil`, если атрибуты недоступны. Используется для проверки,
    /// что `apply` реально применил нужную геометрию.
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

    /// Сравнение двух frame с учётом допуска `toleranceInPoints`.
    static func isApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= toleranceInPoints &&
        abs(lhs.origin.y - rhs.origin.y) <= toleranceInPoints &&
        abs(lhs.width - rhs.width) <= toleranceInPoints &&
        abs(lhs.height - rhs.height) <= toleranceInPoints
    }

    // MARK: - Private

    private enum WriteStep {
        case size(CGSize)
        case position(CGPoint)

        func write(to axElement: AXUIElement) {
            switch self {
            case .size(let size):
                var value = size
                guard let axValue = AXValueCreate(.cgSize, &value) else { return }
                AXUIElementSetAttributeValue(axElement, kAXSizeAttribute as CFString, axValue)
            case .position(let origin):
                var value = origin
                guard let axValue = AXValueCreate(.cgPoint, &value) else { return }
                AXUIElementSetAttributeValue(axElement, kAXPositionAttribute as CFString, axValue)
            }
        }
    }

    private static func applySequence(_ frame: CGRect, to axElement: AXUIElement) {
        let steps: [WriteStep] = [
            .size(frame.size),
            .position(frame.origin),
            .size(frame.size),
            .position(frame.origin),
        ]
        write(steps: steps, index: 0, to: axElement)
    }

    private static func write(steps: [WriteStep], index: Int, to axElement: AXUIElement) {
        guard index < steps.count else { return }
        steps[index].write(to: axElement)
        schedule(after: stepDelay) {
            write(steps: steps, index: index + 1, to: axElement)
        }
    }

    private static func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }
}
