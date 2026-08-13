import Combine
import Foundation

/// Хранит закреплённые (pinned) приложения как упорядоченный список bundle id.
/// Персистентность — UserDefaults. Порядок закрепления сохраняется (drag-reorder
/// не реализован, но структура к этому готова).
///
/// Заимствовано из macTaskbar (https://github.com/damonroberts95/macTaskbar),
/// лицензия MIT, адаптировано под нашу архитектуру.
@MainActor
final class PinnedItemsStore: ObservableObject {

    @Published private(set) var pinnedBundleIdentifiers: [String] = []

    private let defaults: UserDefaults
    private static let storageKey = "TaskbarApp.pinnedBundleIdentifiers"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var isEmpty: Bool { pinnedBundleIdentifiers.isEmpty }

    func isPinned(_ bundleIdentifier: String) -> Bool {
        pinnedBundleIdentifiers.contains(bundleIdentifier)
    }

    func togglePin(bundleIdentifier: String) {
        if let index = pinnedBundleIdentifiers.firstIndex(of: bundleIdentifier) {
            pinnedBundleIdentifiers.remove(at: index)
        } else {
            pinnedBundleIdentifiers.append(bundleIdentifier)
        }
        persist()
    }

    private func load() {
        pinnedBundleIdentifiers = defaults.stringArray(forKey: Self.storageKey) ?? []
    }

    private func persist() {
        defaults.set(pinnedBundleIdentifiers, forKey: Self.storageKey)
    }
}
