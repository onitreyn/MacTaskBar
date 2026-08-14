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

    /// Переключает snap-состояние окна: если окно сейчас в snap-позиции —
    /// возвращает к сохранённому размеру, иначе — сохраняет текущий размер
    /// и разворачивает под Taskbar.
    func toggleSnap(_ window: WindowInfo) {
        // Читаем АКТУАЛЬНЫЙ frame через AX, а не доверяем `window.frame` из снапшота:
        // тот мог устареть (например, сразу после «Переместить на экран N» без
        // промежуточного рефреша), из-за чего окно снапалось бы на старый экран.
        guard let currentFrame = AXWindowFrameWriter.currentFrame(of: window.axElement) else { return }
        guard let screen = screenContaining(currentFrame) else { return }

        let snapFrame = snapFrame(for: screen)

        if AXWindowFrameWriter.isApproximatelyEqual(currentFrame, snapFrame) {
            restore(window)
        } else {
            savedFrames[window.id] = currentFrame
            AXWindowFrameWriter.applyWithRetry(snapFrame, to: window.axElement)
        }
    }

    // MARK: - Private

    /// Сбрасывает сохранённый pre-snap frame окна. Вызывается при переносе окна
    /// на другой экран (`WindowScreenMoveService`): сохранённая до снапа
    /// позиция становится неактуальной, и повторный «Растянуть» не должен
    /// возвращать окно на старый экран.
    func invalidateSavedFrame(forWindowID id: String) {
        savedFrames.removeValue(forKey: id)
    }

    private func restore(_ window: WindowInfo) {
        guard let previousFrame = savedFrames[window.id] else {
            // Нет сохранённого состояния (например, TaskbarApp был перезапущен
            // между snap и повторным кликом) — просто ничего не делаем, окно
            // остаётся в текущем (snap) состоянии, пользователь подвинет сам.
            return
        }
        AXWindowFrameWriter.applyWithRetry(previousFrame, to: window.axElement)
        savedFrames.removeValue(forKey: window.id)
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

        // В Quartz Y растёт вниз: origin.y прямоугольника — это его ВЕРХНЯЯ
        // граница, а не нижняя (в отличие от Cocoa). "Верх под menu bar" —
        // это origin экрана + высота menu bar (menu bar есть на каждом экране),
        // а "низ над нашей панелью" — нижняя граница экрана минус высота панели.
        let topY = screenQuartz.origin.y + ScreenCoordinateConverter.menuBarHeight
        let bottomY = screenQuartz.origin.y + screenQuartz.height - TaskbarConstants.panelHeight

        return CGRect(
            x: screenQuartz.origin.x,
            y: topY,
            width: screenQuartz.width,
            height: max(0, bottomY - topY)
        )
    }
}
