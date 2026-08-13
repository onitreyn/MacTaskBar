import AppKit

/// Кнопка "Пуск" в левом краю панели задач (аналог кнопки Start в Windows и
/// "uBar Menu" в uBar). По клику открывает меню с быстрыми действиями:
/// Finder, Системные настройки, список установленных программ, выход.
final class StartButtonView: NSView {

    private let imageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6

        // Иконка Finder — явно показывает, что кнопка связана с навигацией по системе.
        imageView.image = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    override func mouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(buildMenu(), with: event, for: self)
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let finder = NSMenuItem(title: "Открыть Finder", action: #selector(openFinder), keyEquivalent: "")
        finder.target = self
        menu.addItem(finder)

        let settings = NSMenuItem(title: "Системные настройки", action: #selector(openSystemSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let programs = NSMenuItem(title: "Программы", action: nil, keyEquivalent: "")
        programs.submenu = applicationsSubmenu()
        menu.addItem(programs)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Выйти из TaskbarApp", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func applicationsSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let apps = installedApplications()

        if apps.isEmpty {
            submenu.addItem(NSMenuItem(title: "(пусто)", action: nil, keyEquivalent: ""))
            return submenu
        }

        for app in apps {
            let item = NSMenuItem(title: app.displayName, action: #selector(openApplication(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.path
            submenu.addItem(item)
        }
        return submenu
    }

    // MARK: - Actions

    @objc private func openFinder() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
    }

    @objc private func openSystemSettings() {
        let url = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
    }

    @objc private func openApplication(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func installedApplications() -> [(displayName: String, path: String)] {
        let dir = URL(fileURLWithPath: "/Applications")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "app" }
            .map { ($0.deletingPathExtension().lastPathComponent, $0.path) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }
}
