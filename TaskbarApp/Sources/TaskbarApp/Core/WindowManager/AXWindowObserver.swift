import ApplicationServices

/// Подписка на AX-события окон одного приложения (per-pid): создание/уничтожение,
/// смена заголовка, минимизация/разминимизация, смена фокуса.
///
/// Системного «окна изменились»-уведомления не существует, поэтому регистрируем
/// отдельного AXObserver на каждый pid. Это событийный аналог поллинга в
/// `TaskbarStore` — изменения подхватываются мгновенно, а периодический опрос
/// остаётся только как self-heal подстраховка (медленнее, чем был поллинг).
///
/// Заимствовано из macTaskbar (https://github.com/damonroberts95/macTaskbar),
/// лицензия MIT, адаптировано под нашу архитектуру.
final class AXWindowObserver {

    private let observer: AXObserver
    private let onEvent: () -> Void

    private static let notifications: [CFString] = [
        kAXWindowCreatedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString,
        kAXTitleChangedNotification as CFString,
        kAXWindowMiniaturizedNotification as CFString,
        kAXWindowDeminiaturizedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString
    ]

    /// Возвращает nil, если не удалось создать observer (например, процесс ещё
    /// не готов отдавать AX-дерево) — вызывающий код просто пропускает такой pid.
    init?(pid: pid_t, onEvent: @escaping () -> Void) {
        self.onEvent = onEvent

        var observerRef: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<AXWindowObserver>.fromOpaque(refcon).takeUnretainedValue().onEvent()
        }

        guard AXObserverCreate(pid, callback, &observerRef) == .success, let observerRef else {
            return nil
        }
        self.observer = observerRef

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.notifications {
            AXObserverAddNotification(observerRef, appElement, notification, refcon)
        }

        // Observer доставляет события через собственный run loop source; подключаем
        // его к главному run loop, чтобы callback'и приходили в main thread.
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observerRef), .defaultMode)
    }

    deinit {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}
