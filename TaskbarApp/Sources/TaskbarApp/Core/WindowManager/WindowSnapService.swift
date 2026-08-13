import AppKit
import ApplicationServices

/// Разворачивает окно на всю ширину экрана снизу-под-нашей-панелью и
/// сверху-под-системной-menu-bar ("snap под Taskbar"). Повторный вызов для
/// того же окна возвращает его к размеру/позиции, которые были ДО снапа —
/// аналогично поведению стандартной зелёной zoom-кнопки.
///
/// Состояние (сохранённые frame'ы) хранится только в памяти на время жизни
/// процесса — это осознанное упрощение для MVP: если TaskbarApp перезапустят
/// между snap и restore, restore для этого окна выполнить будет уже нельзя,
/// пользователь просто подвинет окно руками. Более надёжный вариант (диск/
/// per-window id, переживающий перезапуск) можно добавить позже, если
/// понадобится.
@MainActor
final class WindowSnapService {

    static let shared = WindowSnapService()

    private init() {}

    /// window.id (см. WindowInfo) -> frame до снапа.
    private var savedFrames: [String: CGRect] = [:]

    /// Допуск в points при сравнении текущего frame окна со snap-frame —
    /// AX API возвращает координаты с плавающей точкой, точное совпадение
    /// не гарантировано даже сразу после того, как мы сами его выставили.
    private let toleranceInPoints: CGFloat = 2

    /// Переключает snap-состояние окна: если окно сейчас в snap-позиции —
    /// возвращает к сохранённому размеру, иначе — сохраняет текущий размер
    /// и разворачивает под Taskbar.
    func toggleSnap(_ window: WindowInfo) {
        guard let screen = screenContaining(window.frame) else { return }

        let snapFrame = snapFrame(for: screen)

        if isFrame(window.frame, approximatelyEqualTo: snapFrame) {
            restore(window)
        } else {
            savedFrames[window.id] = window.frame
            apply(snapFrame, to: window)
        }
    }

    // MARK: - Private

    private func restore(_ window: WindowInfo) {
        guard let previousFrame = savedFrames[window.id] else {
            // Нет сохранённого состояния (например, TaskbarApp был перезапущен
            // между snap и повторным кликом) — просто ничего не делаем, окно
            // остаётся в текущем (snap) состоянии, пользователь подвинет сам.
            return
        }
        apply(previousFrame, to: window)
        savedFrames.removeValue(forKey: window.id)
    }

    private func apply(_ frame: CGRect, to window: WindowInfo) {
        AXWindowFrameWriter.apply(frame, to: window.axElement)
    }

    private func screenContaining(_ quartzFrame: CGRect) -> NSScreen? {
        ScreenCoordinateConverter.screenContaining(quartzFrame: quartzFrame)
    }

    /// Geometry снапа в координатах Quartz (той же системе, в которой заданы
    /// `window.frame` и в которую пишет Accessibility API): полная ширина
    /// экрана (от края до края, по решению пользователя — не visibleFrame),
    /// высота — от верха, ограниченного системной menu bar, до низа,
    /// ограниченного нашей панелью задач (`TaskbarConstants.panelHeight`).
    private func snapFrame(for screen: NSScreen) -> CGRect {
        let screenQuartz = ScreenCoordinateConverter.cocoaToQuartz(screen.frame)
        let visibleQuartz = ScreenCoordinateConverter.cocoaToQuartz(screen.visibleFrame)

        // В Quartz Y растёт вниз: origin.y прямоугольника — это его ВЕРХНЯЯ
        // граница, а не нижняя (в отличие от Cocoa). Поэтому "верх под menu bar"
        // это просто origin.y конвертированного visibleFrame, а "низ над нашей
        // панелью" — это нижняя граница экрана (origin.y + height) минус высота
        // панели.
        let topY = visibleQuartz.origin.y
        let bottomY = screenQuartz.origin.y + screenQuartz.height - TaskbarConstants.panelHeight

        return CGRect(
            x: screenQuartz.origin.x,
            y: topY,
            width: screenQuartz.width,
            height: max(0, bottomY - topY)
        )
    }

    private func isFrame(_ lhs: CGRect, approximatelyEqualTo rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= toleranceInPoints &&
        abs(lhs.origin.y - rhs.origin.y) <= toleranceInPoints &&
        abs(lhs.width - rhs.width) <= toleranceInPoints &&
        abs(lhs.height - rhs.height) <= toleranceInPoints
    }
}
