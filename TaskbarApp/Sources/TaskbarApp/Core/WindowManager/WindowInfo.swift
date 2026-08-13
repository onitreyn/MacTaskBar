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

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Модель запущенного приложения, агрегирующая его окна.
struct RunningAppInfo: Identifiable, Hashable {
    /// В качестве id используем PID — уникален пока приложение запущено.
    var id: pid_t { pid }

    let pid: pid_t
    let bundleIdentifier: String?
    let localizedName: String
    let icon: NSImage?

    /// Окна, принадлежащие приложению. Обновляется TaskbarStore.
    var windows: [WindowInfo]

    /// Активно ли приложение (foreground) в данный момент.
    var isActive: Bool

    static func == (lhs: RunningAppInfo, rhs: RunningAppInfo) -> Bool {
        lhs.pid == rhs.pid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }
}
