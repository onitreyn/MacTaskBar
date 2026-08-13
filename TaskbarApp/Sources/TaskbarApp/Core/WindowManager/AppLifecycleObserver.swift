import AppKit
import Combine

/// Отслеживает жизненный цикл приложений на системе: запуск, завершение, активацию.
/// Источник данных — NSWorkspace.shared.notificationCenter, который не требует
/// Accessibility-доступа (в отличие от чтения самих окон).
final class AppLifecycleObserver {

    /// Вызывается при запуске нового приложения.
    var onAppLaunched: ((NSRunningApplication) -> Void)?

    /// Вызывается при завершении приложения.
    var onAppTerminated: ((NSRunningApplication) -> Void)?

    /// Вызывается при смене активного (foreground) приложения.
    var onAppActivated: ((NSRunningApplication) -> Void)?

    private var tokens: [NSObjectProtocol] = []

    init() {
        subscribe()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        tokens.forEach { center.removeObserver($0) }
    }

    /// Текущий список обычных пользовательских приложений (activationPolicy == .regular).
    /// Фоновые демоны и агенты (.accessory, .prohibited) отсеиваются — они не показываются в Dock
    /// и не должны показываться в нашей панели задач.
    func currentRegularApplications() -> [NSRunningApplication] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID
        }
    }

    private func subscribe() {
        let center = NSWorkspace.shared.notificationCenter

        let launchToken = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            self?.onAppLaunched?(app)
        }

        let terminateToken = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.onAppTerminated?(app)
        }

        let activateToken = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            self?.onAppActivated?(app)
        }

        tokens = [launchToken, terminateToken, activateToken]
    }
}
