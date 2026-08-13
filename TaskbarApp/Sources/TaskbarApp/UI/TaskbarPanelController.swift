import AppKit
import Combine

/// Управляет одной панелью на одном экране: создаёт NSPanel, рендерит плитки приложений,
/// подписывается на TaskbarStore и перестраивает содержимое при изменениях.
///
/// Многомониторность (Фаза 2 по архитектуре) добавляется через создание нескольких
/// экземпляров этого контроллера — один на NSScreen. Для MVP используется один
/// экран (main), полноценный менеджер под все NSScreen.screens подключается отдельно.
@MainActor
final class TaskbarPanelController {

    private let panel: TaskbarPanel
    private let stackView = NSStackView()
    private let startButton = StartButtonView()
    private let store: TaskbarStore
    private var cancellable: AnyCancellable?

    // Геометрия левой зоны с кнопкой "Пуск" (используется и в layout, и в расчёте ширины плиток).
    private let startButtonLeading: CGFloat = 8
    private let startButtonWidth: CGFloat = 32
    private let startButtonGap: CGFloat = 4

    init(screen: NSScreen, store: TaskbarStore) {
        self.panel = TaskbarPanel(screen: screen)
        self.store = store
        setupStackView()
        subscribe()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func setupStackView() {
        guard let contentView = panel.contentView else { return }

        startButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(startButton)

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 4
        // Левый отступ уже обеспечивает кнопка "Пуск", поэтому слева 0.
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 8)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            startButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: startButtonLeading),
            startButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            startButton.widthAnchor.constraint(equalToConstant: startButtonWidth),
            startButton.heightAnchor.constraint(equalToConstant: startButtonWidth),

            stackView.leadingAnchor.constraint(equalTo: startButton.trailingAnchor, constant: startButtonGap),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor)
        ])
    }

    private func subscribe() {
        cancellable = store.$apps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in
                self?.render(apps: apps)
            }
    }

    private func render(apps: [RunningAppInfo]) {
        stackView.views.forEach { $0.removeFromSuperview() }

        guard !apps.isEmpty else { return }

        let (tileWidth, showsTitle) = layoutMetrics(appCount: apps.count)

        for app in apps {
            let tile = AppTileView(
                app: app,
                showsTitle: showsTitle,
                onClick: { [weak self] tappedApp in
                    self?.handleTileClick(app: tappedApp)
                },
                onSnapToggle: { [weak self] tappedApp in
                    self?.handleSnapToggle(app: tappedApp)
                },
                onBringToFront: { [weak self] tappedApp in
                    self?.handleBringToFront(app: tappedApp)
                },
                onMoveToScreen: { [weak self] tappedApp, screenIndex in
                    self?.handleMoveToScreen(app: tappedApp, screenIndex: screenIndex)
                },
                onWindowActivate: { [weak self] tappedApp, window in
                    self?.handleWindowActivate(app: tappedApp, window: window)
                },
                onCloseWindow: { [weak self] tappedApp in
                    self?.handleCloseWindow(app: tappedApp)
                },
                onTerminateApp: { [weak self] tappedApp in
                    self?.handleTerminateApp(app: tappedApp)
                }
            )
            tile.translatesAutoresizingMaskIntoConstraints = false
            tile.widthAnchor.constraint(equalToConstant: tileWidth).isActive = true
            tile.heightAnchor.constraint(equalToConstant: 32).isActive = true
            stackView.addView(tile, in: .leading)
        }
    }

    /// Рассчитывает ширину плитки и режим показа названия в зависимости от
    /// доступного места на панели и числа приложений.
    ///
    /// Переполнение: если все плитки не помещаются на полной ширине (140pt),
    /// равномерно сжимаем их вплоть до минимальной ширины (44pt — только иконка).
    /// При ширине ниже порога (~84pt) название скрывается, остаётся иконка +
    /// бейдж количества окон. Если и при минимальной ширине приложений больше,
    /// чем влезает — оставляем иконки (это ~30+ приложений на 1440pt; полноценный
    /// скролл/overflow-меню — отдельная будущая задача, см. ARCHITECTURE.md).
    private func layoutMetrics(appCount: Int) -> (width: CGFloat, showsTitle: Bool) {
        // Зона плиток начинается после кнопки "Пуск" (leading + width + gap)
        // и заканчивается у правого края (правый inset стека).
        let leftReserved = startButtonLeading + startButtonWidth + startButtonGap
        let rightInset = stackView.edgeInsets.right
        let spacing = stackView.spacing
        let availableWidth = panel.frame.width - leftReserved - rightInset

        let fullTileWidth: CGFloat = 140
        let minTileWidth: CGFloat = 44
        let titleThreshold: CGFloat = 84

        let count = CGFloat(appCount)
        let fullNeeded = count * fullTileWidth + max(0, count - 1) * spacing

        if fullNeeded <= availableWidth {
            return (fullTileWidth, true)
        }

        let perTile = (availableWidth - max(0, count - 1) * spacing) / count
        let width = max(minTileWidth, perTile)
        return (width, width >= titleThreshold)
    }

    private func handleTileClick(app: RunningAppInfo) {
        // MVP: активируем первое не свёрнутое окно приложения, либо первое любое.
        guard let window = app.windows.first(where: { !$0.isMinimized }) ?? app.windows.first else { return }
        store.activate(window: window)
    }

    private func handleBringToFront(app: RunningAppInfo) {
        // Та же логика выбора целевого окна, что и у обычного клика активации.
        guard let window = app.windows.first(where: { !$0.isMinimized }) ?? app.windows.first else { return }
        WindowActionService.bringToFront(window)
    }

    private func handleSnapToggle(app: RunningAppInfo) {
        // Та же логика выбора целевого окна, что и у обычного клика активации.
        guard let window = app.windows.first(where: { !$0.isMinimized }) ?? app.windows.first else { return }
        WindowSnapService.shared.toggleSnap(window)
    }

    private func handleMoveToScreen(app: RunningAppInfo, screenIndex: Int) {
        guard let window = app.windows.first(where: { !$0.isMinimized }) ?? app.windows.first else { return }
        WindowScreenMoveService.moveWindow(window, toScreenAt: screenIndex)
    }

    private func handleWindowActivate(app: RunningAppInfo, window: WindowInfo) {
        store.activate(window: window)
    }

    private func handleCloseWindow(app: RunningAppInfo) {
        // Та же логика выбора целевого окна, что и у остальных действий.
        guard let window = app.windows.first(where: { !$0.isMinimized }) ?? app.windows.first else { return }
        store.close(window: window)
    }

    private func handleTerminateApp(app: RunningAppInfo) {
        store.terminateApp(pid: app.pid)
    }
}
