import AppKit

/// Перемещает окно на другой экран, сохраняя его текущий размер и
/// центрируя в видимой области целевого экрана (видимая область = за вычетом
/// системной menu bar и нашей панели задач снизу).
@MainActor
enum WindowScreenMoveService {

    /// Перемещает окно на экран с указанным индексом в `NSScreen.screens`
    /// (0 = экран 1, 1 = экран 2 и т.д. — порядок как в System Settings).
    /// Если индекс вне диапазона или совпадает с текущим экраном окна —
    /// ничего не делает.
    static func moveWindow(_ window: WindowInfo, toScreenAt index: Int) {
        guard index >= 0, index < NSScreen.screens.count else { return }
        let targetScreen = NSScreen.screens[index]

        let currentScreen = ScreenCoordinateConverter.screenContaining(quartzFrame: window.frame)
        if currentScreen === targetScreen { return }

        let targetFrame = centeredFrame(size: window.frame.size, on: targetScreen)
        AXWindowFrameWriter.apply(targetFrame, to: window.axElement)
    }

    /// Прямоугольник заданного размера, отцентрированный в видимой области
    /// целевого экрана (учитывает menu bar сверху и нашу панель снизу),
    /// в координатах Quartz.
    private static func centeredFrame(size: CGSize, on screen: NSScreen) -> CGRect {
        let screenQuartz = ScreenCoordinateConverter.cocoaToQuartz(screen.frame)
        let visibleQuartz = ScreenCoordinateConverter.cocoaToQuartz(screen.visibleFrame)

        let topY = visibleQuartz.origin.y
        let bottomY = screenQuartz.origin.y + screenQuartz.height - TaskbarConstants.panelHeight
        let availableHeight = max(0, bottomY - topY)

        // Размер окна не должен превышать доступную область — иначе окно
        // окажется частично под menu bar или под нашей панелью после переноса.
        let clampedWidth = min(size.width, screenQuartz.width)
        let clampedHeight = min(size.height, availableHeight)

        let x = screenQuartz.origin.x + (screenQuartz.width - clampedWidth) / 2
        let y = topY + (availableHeight - clampedHeight) / 2

        return CGRect(x: x, y: y, width: clampedWidth, height: clampedHeight)
    }
}
