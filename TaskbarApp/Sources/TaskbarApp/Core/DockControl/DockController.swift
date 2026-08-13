import AppKit

/// Управляет видимостью системного Dock из самого приложения.
///
/// ВАЖНО (см. инцидент от 05.08): простое "скрыть Dock и восстановить при
/// нормальном выходе" НЕДОСТАТОЧНО — если процесс убит жёстко (kill -9, крах,
/// обрыв сессии, выключение питания), Dock останется скрытым навсегда без
/// дополнительной подстраховки. Поэтому здесь три независимых уровня защиты:
///
/// 1. Марker-файл на диске (`dock_hidden_by_us`) — переживает краш процесса,
///    следующий владелец файла (watchdog) видит, что Dock был скрыт нами.
/// 2. `applicationWillTerminate` в AppDelegate вызывает `restoreIfNeeded()`
///    при штатном выходе (Cmd+Q, System Events quit).
/// 3. Независимый launchd LaunchAgent (см. scripts/dock_watchdog.sh +
///    com.local.taskbarapp.dockwatchdog.plist) проверяет каждые 15 секунд
///    и сразу при логине: если marker-файл существует, а TaskbarApp не
///    запущен — восстанавливает Dock сам, без участия TaskbarApp вообще.
///    Это единственный уровень, который сработает, если наше приложение
///    в принципе никогда больше не запустится.
final class DockController {

    static let shared = DockController()

    private let markerURL: URL

    private init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TaskbarApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        self.markerURL = supportDir.appendingPathComponent("dock_hidden_by_us")
    }

    /// true, если в данный момент Dock скрыт по нашей инициативе.
    var isHiddenByUs: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// Скрывает системный Dock (autohide с большой задержкой появления).
    /// Пишет marker-файл ПЕРЕД изменением настроек — это важно: если процесс
    /// упадёт прямо во время выполнения `defaults write`, watchdog должен
    /// увидеть marker и на всякий случай попытаться восстановить Dock,
    /// а не решить, что "мы ничего не трогали".
    func hide() {
        writeMarker()
        runDefaults(["write", "com.apple.dock", "autohide", "-bool", "true"])
        runDefaults(["write", "com.apple.dock", "autohide-delay", "-float", "1000"])
        restartDock()
    }

    /// Восстанавливает штатное поведение Dock и удаляет marker-файл.
    func show() {
        runDefaults(["delete", "com.apple.dock", "autohide-delay"])
        runDefaults(["write", "com.apple.dock", "autohide", "-bool", "false"])
        restartDock()
        removeMarker()
    }

    /// Вызывается при штатном завершении приложения (уровень защиты №2).
    func restoreIfNeededOnTerminate() {
        guard isHiddenByUs else { return }
        show()
    }

    // MARK: - Private

    private func writeMarker() {
        FileManager.default.createFile(atPath: markerURL.path, contents: Date().description.data(using: .utf8))
    }

    private func removeMarker() {
        try? FileManager.default.removeItem(at: markerURL)
    }

    private func runDefaults(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }

    private func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
        process.waitUntilExit()
    }
}
