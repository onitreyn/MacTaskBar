import AppKit

/// Плитка одного приложения в панели задач: иконка + (опционально) название +
/// бейдж количества окон + клик для активации.
///
/// `showsTitle` управляет компактным режимом: когда места на панели мало и
/// плитки сжимаются до иконок, название скрывается (см. TaskbarPanelController).
final class AppTileView: NSView {

    private let app: RunningAppInfo
    private let showsTitle: Bool
    private let onClick: (RunningAppInfo) -> Void
    private let onSnapToggle: (RunningAppInfo) -> Void
    private let onBringToFront: (RunningAppInfo) -> Void
    private let onMoveToScreen: (RunningAppInfo, Int) -> Void
    private let onWindowActivate: (RunningAppInfo, WindowInfo) -> Void
    private let onCloseWindow: (RunningAppInfo) -> Void
    private let onTerminateApp: (RunningAppInfo) -> Void

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let activeIndicator = NSView()
    private let countBadge = NSView()
    private let countBadgeLabel = NSTextField(labelWithString: "")

    init(
        app: RunningAppInfo,
        showsTitle: Bool,
        onClick: @escaping (RunningAppInfo) -> Void,
        onSnapToggle: @escaping (RunningAppInfo) -> Void,
        onBringToFront: @escaping (RunningAppInfo) -> Void,
        onMoveToScreen: @escaping (RunningAppInfo, Int) -> Void,
        onWindowActivate: @escaping (RunningAppInfo, WindowInfo) -> Void,
        onCloseWindow: @escaping (RunningAppInfo) -> Void,
        onTerminateApp: @escaping (RunningAppInfo) -> Void
    ) {
        self.app = app
        self.showsTitle = showsTitle
        self.onClick = onClick
        self.onSnapToggle = onSnapToggle
        self.onBringToFront = onBringToFront
        self.onMoveToScreen = onMoveToScreen
        self.onWindowActivate = onWindowActivate
        self.onCloseWindow = onCloseWindow
        self.onTerminateApp = onTerminateApp
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
            menuItem(title: "Вывести на передний план", dotColor: .systemBlue, action: #selector(handleBringToFront))
        )

        menu.addItem(
            menuItem(title: "Развернуть под Taskbar", dotColor: .systemPurple, action: #selector(handleSnapToggle))
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
                    title: "Переместить на экран \(index + 1)",
                    dotColor: beige,
                    action: #selector(handleMoveToScreen(_:))
                )
                item.tag = index
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        menu.addItem(
            menuItem(title: "Закрыть окно", dotColor: .systemOrange, action: #selector(handleCloseWindow))
        )
        menu.addItem(
            menuItem(title: "Завершить приложение", dotColor: .systemRed, action: #selector(handleTerminateApp))
        )

        menu.items.forEach { $0.target = self }
        return menu
    }

    /// Заголовок пункта списка окон: цветная точка (зелёная — обычное,
    /// серая — свёрнутое) + название окна, обрезанное по длине.
    private func windowListTitle(for window: WindowInfo) -> NSAttributedString {
        let dotColor: NSColor = window.isMinimized ? .systemGray : .systemGreen

        var title = window.title.isEmpty ? "(без названия)" : window.title
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

    @objc private func handleBringToFront() {
        DispatchQueue.main.async { [onBringToFront, app] in
            onBringToFront(app)
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

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = app.isActive
            ? NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            : NSColor.clear.cgColor
    }
}
