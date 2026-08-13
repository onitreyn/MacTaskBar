import AppKit
import Combine

/// Единый источник истины для UI панели задач.
///
/// Для MVP (Фаза 1) используется гибридный подход:
/// - NSWorkspace-события (`AppLifecycleObserver`) дают немедленную реакцию на запуск/закрытие/активацию;
/// - лёгкий периодический опрос окон (`refreshTimer`) закрывает случаи, которые не ловятся событиями
///   NSWorkspace напрямую (переименование заголовка окна, открытие нового окна в уже запущенном приложении,
///   сворачивание через Cmd+M и т.п.). Полноценный AXObserver для этих событий запланирован в Фазе 2 —
///   он эффективнее, но сложнее в отладке, поэтому в MVP сознательно выбран более простой путь.
@MainActor
final class TaskbarStore: ObservableObject {

    @Published private(set) var apps: [RunningAppInfo] = []
    @Published private(set) var isAccessibilityGranted: Bool = PermissionsService.shared.isAccessibilityGranted

    private let lifecycleObserver = AppLifecycleObserver()
    private var windowManagers: [pid_t: WindowManager] = [:]
    private var refreshTimer: Timer?

    /// Интервал опроса окон. 500 мс — компромисс между отзывчивостью и нагрузкой на CPU,
    /// как зафиксировано в разделе рисков архитектуры (п.13.4).
    private let pollInterval: TimeInterval = 0.5

    init() {
        setupLifecycleCallbacks()
    }

    /// Запускает наблюдение. Вызывается после того, как получено разрешение Accessibility,
    /// иначе AXUIElement-вызовы будут молча возвращать пустые данные.
    func start() {
        guard isAccessibilityGranted else {
            PermissionsService.shared.requestAccessibilityIfNeeded()
            PermissionsService.shared.pollUntilGranted { [weak self] in
                self?.isAccessibilityGranted = true
                self?.start()
            }
            return
        }

        refreshAllApps()
        startPolling()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Actions (проксируем в WindowActionService, чтобы UI не знал про AX напрямую)

    func activate(window: WindowInfo) {
        WindowActionService.activate(window)
    }

    func minimize(window: WindowInfo) {
        WindowActionService.minimize(window)
        refreshAllApps()
    }

    func close(window: WindowInfo) {
        WindowActionService.close(window)
        // Небольшая задержка, чтобы AX-дерево успело обновиться после закрытия окна.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refreshAllApps()
        }
    }

    func terminateApp(pid: pid_t) {
        WindowActionService.terminateApp(pid: pid)
        // Обновление подхватит onAppTerminated (app.terminate() шлёт событие NSWorkspace),
        // но страхуемся ручным рефрешем на случай, если событие задержалось.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshAllApps()
        }
    }

    // MARK: - Private

    private func setupLifecycleCallbacks() {
        lifecycleObserver.onAppLaunched = { [weak self] app in
            self?.refreshAllApps()
        }
        lifecycleObserver.onAppTerminated = { [weak self] app in
            self?.windowManagers.removeValue(forKey: app.processIdentifier)
            self?.refreshAllApps()
        }
        lifecycleObserver.onAppActivated = { [weak self] app in
            self?.markActive(pid: app.processIdentifier)
        }
    }

    private func startPolling() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllApps()
            }
        }
    }

    private func markActive(pid: pid_t) {
        for index in apps.indices {
            apps[index].isActive = (apps[index].pid == pid)
        }
    }

    private func refreshAllApps() {
        let runningApps = lifecycleObserver.currentRegularApplications()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        var updated: [RunningAppInfo] = []

        for app in runningApps {
            let pid = app.processIdentifier
            let manager = windowManagers[pid] ?? {
                let newManager = WindowManager(pid: pid)
                windowManagers[pid] = newManager
                return newManager
            }()

            let windows = manager.fetchWindows()

            // Приложения без окон (например, чисто фоновые agent-процессы,
            // случайно попавшие под .regular policy) не показываем в панели.
            guard !windows.isEmpty else { continue }

            updated.append(
                RunningAppInfo(
                    pid: pid,
                    bundleIdentifier: app.bundleIdentifier,
                    localizedName: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
                    icon: app.icon,
                    windows: windows,
                    isActive: pid == frontmostPID
                )
            )
        }

        apps = updated.sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
    }
}
