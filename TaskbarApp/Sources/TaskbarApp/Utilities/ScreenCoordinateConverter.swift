import AppKit

/// Конвертация координат между двумя системами, используемыми в приложении:
/// - Cocoa: origin — нижний левый угол ГЛАВНОГО экрана, Y растёт вверх.
///   В этой системе заданы `NSScreen.frame` и `NSScreen.visibleFrame`.
/// - Quartz: origin — верхний левый угол ГЛАВНОГО экрана, Y растёт вниз.
///   В этой системе заданы координаты, которые возвращает и принимает
///   Accessibility API (`kAXPositionAttribute` и т.п.) и `CGWindowListCopyWindowInfo`.
///
/// Все методы статические и не хранят состояния — единственная "магия" здесь
/// в выборе якоря системы координат: используем `NSScreen.screens.first`
/// (экран с origin (0,0) в Cocoa, физически содержащий menu bar), а НЕ
/// `NSScreen.main` (тот следует за клавиатурным фокусом — см. ARCHITECTURE.md,
/// уже наступали на эти грабли при позиционировании панели).
enum ScreenCoordinateConverter {

    static func cocoaToQuartz(_ rect: CGRect) -> CGRect {
        let referenceHeight = NSScreen.screens.first?.frame.height ?? rect.height
        return CGRect(
            x: rect.origin.x,
            y: referenceHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// Обратная операция. Cocoa <-> Quartz конвертация симметрична относительно
    /// той же формулы (переворот вокруг референсной высоты), поэтому повторное
    /// применение той же формулы даёт обратное преобразование.
    static func quartzToCocoa(_ rect: CGRect) -> CGRect {
        cocoaToQuartz(rect)
    }

    /// Экран, на котором находится точка/прямоугольник, заданный в Quartz-
    /// координатах (например, `WindowInfo.frame`). Определяется по центру
    /// прямоугольника. Fallback на `NSScreen.main`, если центр не попал ни в
    /// один известный экран (например, окно осталось "за кадром" сразу после
    /// отключения одного из мониторов).
    static func screenContaining(quartzFrame: CGRect) -> NSScreen? {
        let center = CGPoint(x: quartzFrame.midX, y: quartzFrame.midY)
        return NSScreen.screens.first { cocoaToQuartz($0.frame).contains(center) } ?? NSScreen.main
    }
}
