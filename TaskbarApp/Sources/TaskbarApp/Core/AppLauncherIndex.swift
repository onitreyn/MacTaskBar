import AppKit

/// Индекс установленных приложений: прямой скан стандартных каталогов вместо
/// Spotlight-запроса — быстрее, детерминированно, не требует доп. разрешений.
/// Используется для запуска/закрепления приложений и показа их иконок.
///
/// Заимствовано из macTaskbar (https://github.com/damonroberts95/macTaskbar),
/// лицензия MIT, адаптировано под нашу архитектуру.
@MainActor
final class AppLauncherIndex {

    static let shared = AppLauncherIndex()

    struct Entry {
        let bundleIdentifier: String
        let name: String
        let icon: NSImage?
        let url: URL
    }

    private(set) var entries: [Entry] = []

    private init() {}

    private static let searchDirectories = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications"
    ]

    func refresh() {
        var seenBundleIDs = Set<String>()
        var result: [Entry] = []

        for directory in Self.searchDirectories {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = directory + "/" + item
                let url = URL(fileURLWithPath: path)
                guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
                guard seenBundleIDs.insert(bundleID).inserted else { continue }

                let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? (item as NSString).deletingPathExtension

                result.append(Entry(
                    bundleIdentifier: bundleID,
                    name: name,
                    icon: NSWorkspace.shared.icon(forFile: path),
                    url: url
                ))
            }
        }

        entries = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Возвращает запись по bundle id: сначала из кэша, иначе резолвом через NSWorkspace.
    func entry(forBundleIdentifier bundleIdentifier: String) -> Entry? {
        if let cached = entries.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let bundle = Bundle(url: url)
        else {
            return nil
        }
        let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return Entry(
            bundleIdentifier: bundleIdentifier,
            name: name,
            icon: NSWorkspace.shared.icon(forFile: url.path),
            url: url
        )
    }

    func launch(bundleIdentifier: String) {
        // Запускаем по URL из нашего скана каталогов (надёжнее, чем повторный
        // резолв через LaunchServices, который для некоторых приложений
        // возвращает nil и тогда запуск молча не происходит).
        guard let url = entry(forBundleIdentifier: bundleIdentifier)?.url else { return }
        NSWorkspace.shared.open(url)
    }
}
