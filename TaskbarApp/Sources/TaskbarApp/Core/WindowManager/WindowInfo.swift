import AppKit

/// Модель одного окна приложения, как её видит панель задач.
struct WindowInfo: Identifiable, Hashable {
    /// Стабильный идентификатор в рамках сессии — не сохраняется между запусками.
    let id: String

    /// PID процесса-владельца окна.
    let ownerPID: pid_t

    /// Ссылка на AXUIElement окна — используется для активации/закрытия.
    /// AXUIElement не Hashable/Equatable по значению из коробки, поэтому
    /// оборачиваем и сравниваем/хешируем по `id`.
    let axElement: AXUIElement

    /// Заголовок окна (может быть пустым, например у некоторых системных окон).
    var title: String

    /// Свёрнуто ли окно в данный момент.
    var isMinimized: Bool

    /// Границы окна на экране (в координатах AppKit, low-left origin приведён отдельно при необходимости).
    var frame: CGRect

    /// CGWindowID окна (из CGWindowList) — используется для превью через ScreenCaptureKit.
    /// nil, если окно не сопоставлено on-screen снапшоту (например, свёрнуто).
    var windowNumber: CGWindowID?

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Модель запущенного приложения, агрегирующая его окна.
/// Также используется для закреплённых, но не запущенных приложений
/// (`isRunning == false`, пустые окна) — тогда клик по плитке запускает приложение.
struct RunningAppInfo: Identifiable, Hashable {
    /// Для запущенных приложений — "pid-<pid>", для закреплённых не запущенных —
    /// "bundle-<bundleID>".
    var id: String { isRunning ? "pid-\(pid)" : "bundle-\(bundleIdentifier ?? "\(pid)")" }

    let pid: pid_t
    let bundleIdentifier: String?
    let localizedName: String
    let icon: NSImage?

    /// Окна, принадлежащие приложению. Обновляется TaskbarStore. Пусто у
    /// закреплённых не запущенных приложений.
    var windows: [WindowInfo]

    /// Активно ли приложение (foreground) в данный момент.
    var isActive: Bool

    /// Запущено ли приложение. У закреплённых не запущенных — false.
    var isRunning: Bool

    static func == (lhs: RunningAppInfo, rhs: RunningAppInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
