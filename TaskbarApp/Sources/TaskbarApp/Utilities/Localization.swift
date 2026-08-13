import Foundation

/// Ручной выбор языка интерфейса. Хранится в собственном ключе (`appLanguage`),
/// а не в системном `AppleLanguages`, чтобы не вмешиваться в системные настройки.
enum AppLanguage: Int, CaseIterable {
    case system = 0
    case russian = 1
    case english = 2

    /// Текущий выбор пользователя, либо `.system`, если язык не переопределялся.
    static var current: AppLanguage {
        switch UserDefaults.standard.string(forKey: "appLanguage") {
        case "ru": return .russian
        case "en": return .english
        default: return .system
        }
    }

    func apply() {
        switch self {
        case .system: UserDefaults.standard.removeObject(forKey: "appLanguage")
        case .russian: UserDefaults.standard.set("ru", forKey: "appLanguage")
        case .english: UserDefaults.standard.set("en", forKey: "appLanguage")
        }
    }
}

/// Локализация строк через `Localizable.strings`.
///
/// В отличие от глобального `NSLocalizedString` (который опирается на
/// кэшируемые `Bundle.preferredLocalizations` и плохо переключается в рантайме),
/// здесь мы явно грузим `Localizable.strings` из нужного lproj-бандла. Это даёт
/// детерминированный runtime-переключатель языка: после смены достаточно
/// вызвать `L10n.reload()` и пересобрать меню.
enum L10n {

    private static var bundle: Bundle? = loadBundle()

    static func t(_ key: String) -> String {
        bundle?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
    }

    /// Пересоздаёт бандл под текущий язык. Вызывать после `AppLanguage.apply()`.
    static func reload() {
        bundle = loadBundle()
    }

    private static func loadBundle() -> Bundle? {
        let code: String
        switch AppLanguage.current {
        case .russian: code = "ru"
        case .english: code = "en"
        case .system:
            code = Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru" : "en"
        }

        let lprojURL = Bundle.main.resourceURL?.appendingPathComponent("\(code).lproj")
        return lprojURL.flatMap { Bundle(path: $0.path) }
    }
}
