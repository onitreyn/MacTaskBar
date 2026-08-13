import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let store = TaskbarStore()
    private var panelControllers: [TaskbarPanelController] = []
    private var hideDockMenuItem: NSMenuItem?
    private var screenChangeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // На этапе разработки держим иконку в Dock, чтобы было легко перезапускать
        // и видеть краши в консоли. В Фазе 3 (после стабилизации) переключим
        // activationPolicy на .accessory — приложение уйдёт из Dock и Cmd+Tab.
        NSApp.setActivationPolicy(.regular)

        setupMainMenu()
        setupPanels()
        observeScreenChanges()
        store.start()

        // Если приложение стартует ПОСЛЕ того, как Dock уже был скрыт нами в
        // предыдущем запуске (marker-файл остался, например, после kill -9),
        // синхронизируем состояние пункта меню с реальностью — но НЕ трогаем
        // сам Dock автоматически. Пользователь явно включает скрытие через меню.
        hideDockMenuItem?.state = DockController.shared.isHiddenByUs ? .on : .off
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // У нас нет обычных окон документа — закрытие последнего окна не должно завершать приложение.
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Уровень защиты №2 (см. DockController): при ЛЮБОМ штатном завершении
        // (Cmd+Q, System Events quit, выход из системы) гарантированно
        // возвращаем системный Dock, если он был скрыт нами.
        DockController.shared.restoreIfNeededOnTerminate()
    }

    /// Создаёт панель на КАЖДОМ подключённом экране — как Windows Taskbar,
    /// который по умолчанию показывается на всех мониторах. Пересобирается
    /// целиком при любом изменении конфигурации дисплеев (подключение/
    /// отключение монитора, смена разрешения, смена Arrangement).
    private func setupPanels() {
        panelControllers.forEach { $0.hide() }

        panelControllers = NSScreen.screens.map { screen in
            let controller = TaskbarPanelController(screen: screen, store: store)
            controller.show()
            return controller
        }
    }

    private func observeScreenChanges() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // NotificationCenter не привязывает closure к MainActor автоматически,
            // хотя queue: .main гарантирует исполнение на главном потоке.
            // Явный переход через Task делает это видимым для проверки конкурентности.
            Task { @MainActor in
                self?.setupPanels()
            }
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let hideDockItem = NSMenuItem(
            title: L10n.t("menu.hideDock"),
            action: #selector(toggleSystemDock),
            keyEquivalent: ""
        )
        hideDockItem.target = self
        hideDockItem.state = DockController.shared.isHiddenByUs ? .on : .off
        appMenu.addItem(hideDockItem)
        hideDockMenuItem = hideDockItem

        // Отдельный явный пункт восстановления — не завязан на состояние тумблера
        // выше. Дополнительная защита пользователя на случай, если чекбокс
        // разошёлся с реальным состоянием Dock (например, после ручного
        // восстановления через терминал, как в инциденте 05.08 — см.
        // ARCHITECTURE.md п.13.5) — тут можно просто нажать и вернуть Dock,
        // не разбираясь, в каком состоянии сейчас переключатель.
        let restoreDockItem = NSMenuItem(
            title: L10n.t("menu.restoreDock"),
            action: #selector(restoreSystemDock),
            keyEquivalent: ""
        )
        restoreDockItem.target = self
        appMenu.addItem(restoreDockItem)

        appMenu.addItem(.separator())

        let languageItem = NSMenuItem(title: L10n.t("menu.language"), action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu()
        appMenu.addItem(languageItem)

        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(title: L10n.t("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )

        NSApp.mainMenu = mainMenu
    }

    /// Подменю выбора языка: «Системный (авто)», «Русский», «English».
    /// Текущий выбор отмечается галочкой.
    private func languageMenu() -> NSMenu {
        let menu = NSMenu()
        for language in AppLanguage.allCases {
            let title: String
            switch language {
            case .system: title = L10n.t("menu.language.system")
            case .russian: title = L10n.t("menu.language.russian")
            case .english: title = L10n.t("menu.language.english")
            }

            let item = NSMenuItem(title: title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.tag = language.rawValue
            item.state = (language == AppLanguage.current) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let language = AppLanguage(rawValue: sender.tag) else { return }
        language.apply()
        L10n.reload()
        // Пересобираем главное меню, чтобы подписи и галочка обновились на новом языке.
        setupMainMenu()
    }

    @objc private func toggleSystemDock() {
        guard let item = hideDockMenuItem else { return }

        if item.state == .on {
            DockController.shared.show()
            item.state = .off
        } else {
            DockController.shared.hide()
            item.state = .on
        }
    }

    @objc private func restoreSystemDock() {
        DockController.shared.show()
        hideDockMenuItem?.state = .off
    }
}
