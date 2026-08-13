import AppKit

/// Панель задач как NSPanel: `.nonactivatingPanel` не забирает фокус у активного
/// приложения при клике (важно — иначе клик по панели переключал бы фокус на панель,
/// а не на выбранное окно). `.canJoinAllSpaces` — попытка показываться во всех
/// обычных Spaces; в true Fullscreen гарантий нет (см. ARCHITECTURE.md п.4).
final class TaskbarPanel: NSPanel {

    init(screen: NSScreen) {
        let height: CGFloat = TaskbarConstants.panelHeight
        let frame = CGRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y,
            width: screen.frame.width,
            height: height
        )

        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        // Designated init NSWindow не принимает `screen:` — переносим фрейм на нужный
        // экран явным вызовом setFrame после инициализации.
        setFrame(frame, display: false)
        configure()
    }

    private func configure() {
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        isMovable = false
        becomesKeyOnlyIfNeeded = true

        // ВАЖНО: `level` должен устанавливаться ПОСЛЕ `isFloatingPanel = true`.
        // Баг, на который наткнулись эмпирически: сеттер `isFloatingPanel` сам
        // выставляет window level в `.floating` (rawValue 3), затирая любое
        // кастомное значение, установленное до него. Если задать level ДО этого,
        // окно физически окажется на уровне 3 — ниже системного Dock (level 20),
        // и Dock визуально перекрывает содержимое панели снизу экрана.
        // Не полагаемся на семантический .statusBar — на разных версиях macOS
        // фактическое числовое значение Dock-уровня может быть выше ожидаемого.
        // Берём реальный уровень Dock через CGWindowLevelForKey и ставим панель на 1 выше.
        let dockLevel = CGWindowLevelForKey(.dockWindow)
        level = NSWindow.Level(rawValue: Int(dockLevel) + 1)
    }

    // Панель не должна перехватывать фокус клавиатуры у остальной системы.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
