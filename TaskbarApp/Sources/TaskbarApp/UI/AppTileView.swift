import AppKit

/// Плитка одного приложения в панели задач: иконка + (опционально) название +
/// бейдж количества окон + клик для активации.
///
/// `showsTitle` управляет компактным режимом: когда места на панели мало и
/// плитки сжимаются до иконок, название скрывается (см. TaskbarPanelController).
final class AppTileView: NSView {

    private let app: RunningAppInfo
    private let showsTitle: Bool
    private let isPinned: Bool
    private let onClick: (RunningAppInfo) -> Void
    private let onSnapToggle: (RunningAppInfo) -> Void
    private let onMoveToScreen: (RunningAppInfo, Int) -> Void
    private let onWindowActivate: (RunningAppInfo, WindowInfo) -> Void
    private let onCloseWindow: (RunningAppInfo) -> Void
    private let onTerminateApp: (RunningAppInfo) -> Void
    private let onTogglePin: (RunningAppInfo) -> Void

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let activeIndicator = NSView()
    private let countBadge = NSView()
    private let countBadgeLabel = NSTextField(labelWithString: "")

    private var previewPanel: NSPanel?
    private var isHovering = false

    init(
        app: RunningAppInfo,
        showsTitle: Bool,
        isPinned: Bool,
        onClick: @escaping (RunningAppInfo) -> Void,
        onSnapToggle: @escaping (RunningAppInfo) -> Void,
        onMoveToScreen: @escaping (RunningAppInfo, Int) -> Void,
        onWindowActivate: @escaping (RunningAppInfo, WindowInfo) -> Void,
        onCloseWindow: @escaping (RunningAppInfo) -> Void,
        onTerminateApp: @escaping (RunningAppInfo) -> Void,
        onTogglePin: @escaping (RunningAppInfo) -> Void
    ) {
        self.app = app
        self.showsTitle = showsTitle
        self.isPinned = isPinned
        self.onClick = onClick
        self.onSnapToggle = onSnapToggle
        self.onMoveToScreen = onMoveToScreen
        self.onWindowActivate = onWindowActivate
        self.onCloseWindow = onCloseWindow
        self.onTerminateApp = onTerminateApp
        self.onTogglePin = onTogglePin
        super.init(frame: .zero)
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setupSubviews() {
        wantsLayer = true
        layer?.cornerRadius = 6

        imageView.image = app.icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        if showsTitle {
            titleLabel.stringValue = app.localizedName
            titleLabel.font = .systemFont(ofSize: 12)
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(titleLabel)
        }

        activeIndicator.wantsLayer = true
        activeIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        activeIndicator.layer?.cornerRadius = 1.5
        activeIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activeIndicator)
        activeIndicator.isHidden = !app.isActive

        setupCountBadge()

        var constraints: [NSLayoutConstraint] = [
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 22),
            imageView.heightAnchor.constraint(equalToConstant: 22),

            activeIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            activeIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            activeIndicator.widthAnchor.constraint(equalToConstant: 14),
            activeIndicator.heightAnchor.constraint(equalToConstant: 3),

            countBadge.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            countBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
        ]

        if showsTitle {
            constraints += [
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                // Оставляем запас справа под бейдж количества окон.
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
        } else {
            constraints += [
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            ]
        }

        NSLayoutConstraint.activate(constraints)

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)

        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
    }

    deinit {
        previewPanel?.orderOut(nil)
        previewPanel = nil
    }

    // MARK: - Hover preview

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        showPreviewIfPossible()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        previewPanel?.orderOut(nil)
    }

    private func showPreviewIfPossible() {
        // Превью только для запущенных приложений и окон, у которых известен CGWindowID.
        guard app.isRunning,
              let window = app.windows.first(where: { !$0.isMinimized }),
              let windowID = window.windowNumber else { return }

        Task { @MainActor [weak self] in
            guard let image = await ThumbnailProvider.shared.captureThumbnail(windowID: windowID) else { return }
            guard let self, self.isHovering else { return }
            self.displayPreview(image)
        }
    }

    private func displayPreview(_ image: NSImage) {
        let panel = previewPanel ?? makePreviewPanel()
        let imageView = panel.contentView?.subviews.compactMap { $0 as? NSImageView }.first ?? {
            let iv = NSImageView(frame: .zero)
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.autoresizingMask = [.width, .height]
            panel.contentView?.addSubview(iv)
            return iv
        }()

        let size = Self.previewSize(for: image)
        panel.setContentSize(size)
        imageView.frame = panel.contentView?.bounds ?? .zero
        imageView.image = image
        positionPreviewPanel()
        panel.orderFrontRegardless()
    }

    private func makePreviewPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        // Выше панели задач, но ниже системных элементов вроде меню батареи.
        panel.level = .statusBar
        previewPanel = panel
        return panel
    }

    private func positionPreviewPanel() {
        guard let panel = previewPanel, let window = self.window else { return }
        let tileOnScreen = window.convertToScreen(frame)
        let x = tileOnScreen.midX - panel.frame.width / 2
        let y = tileOnScreen.maxY + 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private static func previewSize(for image: NSImage) -> NSSize {
        let maxSize = NSSize(width: 320, height: 200)
        let source = image.size
        guard source.width > 0, source.height > 0 else { return maxSize }
        let scale = min(maxSize.width / source.width, maxSize.height / source.height, 1)
        return NSSize(width: max(source.width * scale, 1), height: max(source.height * scale, 1))
    }

    private func setupCountBadge() {
        let count = app.windows.count
        countBadge.isHidden = count <= 1

        countBadge.wantsLayer = true
        countBadge.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
        countBadge.layer?.cornerRadius = 7
        countBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countBadge)

        countBadgeLabel.stringValue = "\(count)"
        countBadgeLabel.font = .systemFont(ofSize: 9, weight: .bold)
        countBadgeLabel.textColor = .white
        countBadgeLabel.alignment = .center
        countBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        countBadge.addSubview(countBadgeLabel)

        NSLayoutConstraint.activate([
            countBadge.widthAnchor.constraint(equalToConstant: 14),
            countBadge.heightAnchor.constraint(equalToConstant: 14),
            countBadgeLabel.centerXAnchor.constraint(equalTo: countBadge.centerXAnchor),
            countBadgeLabel.centerYAnchor.constraint(equalTo: countBadge.centerYAnchor),
        ])
    }

    @objc private func handleClick() {
        onClick(app)
    }

    /// Стандартный AppKit-механизм показа контекстного меню по правому клику —
    /// не конфликтует с `NSClickGestureRecognizer`, который обрабатывает
    /// обычный (левый) клик активации окна.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        if app.isRunning {
            buildRunningMenu(menu)
        } else {
            // Закреплённое, но не запущенное приложение — только запуск и открепление.
            menu.addItem(plainItem(title: L10n.t("action.launch"), action: #selector(handleLaunch)))
            menu.addItem(.separator())
            menu.addItem(plainItem(title: L10n.t("action.unpin"), action: #selector(handleTogglePin)))
        }

        menu.items.forEach { $0.target = self }
        return menu
    }

    private func buildRunningMenu(_ menu: NSMenu) {
        // Если у приложения несколько окон — выводим их списком в начале меню,
        // чтобы можно было переключиться на конкретное окно (как у браузера).
        if app.windows.count > 1 {
            for window in app.windows {
                let item = NSMenuItem(title: "", action: #selector(handleWindowActivate(_:)), keyEquivalent: "")
                item.attributedTitle = windowListTitle(for: window)
                item.representedObject = window
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        menu.addItem(
            menuItem(title: L10n.t("action.snap"), dotColor: .systemPurple, action: #selector(handleSnapToggle))
        )

        // Пункты переноса на экран показываем, только если экранов больше
        // одного — иначе перенос "на экран 1" при единственном мониторе
        // бессмысленен и только загромождает меню.
        let screens = NSScreen.screens
        if screens.count > 1 {
            menu.addItem(.separator())
            // "Бежевый" — #D2B48C (tan). Системного named-цвета beige в AppKit нет.
            let beige = NSColor(srgbRed: 0.82, green: 0.71, blue: 0.55, alpha: 1.0)
            for index in screens.indices {
                let item = menuItem(
                    title: String(format: L10n.t("action.moveToScreen"), index + 1),
                    dotColor: beige,
                    action: #selector(handleMoveToScreen(_:))
                )
                item.tag = index
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        menu.addItem(
            menuItem(title: L10n.t("action.closeWindow"), dotColor: .systemOrange, action: #selector(handleCloseWindow))
        )
        menu.addItem(
            menuItem(title: L10n.t("action.quitApp"), dotColor: .systemRed, action: #selector(handleTerminateApp))
        )

        menu.addItem(.separator())
        menu.addItem(
            plainItem(title: isPinned ? L10n.t("action.unpin") : L10n.t("action.pin"), action: #selector(handleTogglePin))
        )
    }

    /// Заголовок пункта списка окон: цветная точка (зелёная — обычное,
    /// серая — свёрнутое) + название окна, обрезанное по длине.
    private func windowListTitle(for window: WindowInfo) -> NSAttributedString {
        let dotColor: NSColor = window.isMinimized ? .systemGray : .systemGreen

        var title = window.title.isEmpty ? L10n.t("window.untitled") : window.title
        if title.count > 50 {
            title = String(title.prefix(50)) + "…"
        }

        let attributed = NSMutableAttributedString(string: "●  \(title)")
        attributed.addAttribute(
            .foregroundColor,
            value: dotColor,
            range: NSRange(location: 0, length: 1)
        )
        return attributed
    }

    /// Пункт меню с цветной жирной точкой "●" перед названием.
    private func menuItem(title: String, dotColor: NSColor, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")

        let fullTitle = "●  \(title)"
        let attributed = NSMutableAttributedString(string: fullTitle)
        attributed.addAttribute(
            .foregroundColor,
            value: dotColor,
            range: NSRange(location: 0, length: 1)
        )
        item.attributedTitle = attributed
        return item
    }

    /// Обычный пункт меню без цветной точки (для pin/unpin/launch).
    private func plainItem(title: String, action: Selector) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: "")
    }

    // ВАЖНО: все действия контекстного меню откладываем на следующий tick
    // run loop через `DispatchQueue.main.async`. Причина: NSMenu запускает
    // собственный modal tracking session на закрытие; если внутри его
    // completion-обработчика (куда попадают #selector-действия пунктов меню)
    // сразу вызвать активацию ДРУГОГО приложения (`NSRunningApplication.activate`),
    // AppKit ещё не закончил возвращать фокус нашему процессу после закрытия
    // меню — и этот системный возврат фокуса "перебивает" нашу активацию,
    // окно визуально не поднимается поверх остальных. Обычный клик по плитке
    // (через NSClickGestureRecognizer, без NSMenu) этой проблемы не имеет —
    // там нет modal tracking session меню. Отложенный вызов даёт AppKit
    // время завершить закрытие меню до того, как мы дёргаем активацию.

    @objc private func handleSnapToggle() {
        DispatchQueue.main.async { [onSnapToggle, app] in
            onSnapToggle(app)
        }
    }

    @objc private func handleMoveToScreen(_ sender: NSMenuItem) {
        let screenIndex = sender.tag
        DispatchQueue.main.async { [onMoveToScreen, app] in
            onMoveToScreen(app, screenIndex)
        }
    }

    @objc private func handleWindowActivate(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? WindowInfo else { return }
        DispatchQueue.main.async { [onWindowActivate, app, window] in
            onWindowActivate(app, window)
        }
    }

    @objc private func handleCloseWindow() {
        DispatchQueue.main.async { [onCloseWindow, app] in
            onCloseWindow(app)
        }
    }

    @objc private func handleTerminateApp() {
        DispatchQueue.main.async { [onTerminateApp, app] in
            onTerminateApp(app)
        }
    }

    @objc private func handleTogglePin() {
        DispatchQueue.main.async { [onTogglePin, app] in
            onTogglePin(app)
        }
    }

    @objc private func handleLaunch() {
        DispatchQueue.main.async { [onClick, app] in
            onClick(app)
        }
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = app.isActive
            ? NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            : NSColor.clear.cgColor
    }
}
