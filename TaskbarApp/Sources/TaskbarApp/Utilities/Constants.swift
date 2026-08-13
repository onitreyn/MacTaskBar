import CoreGraphics

/// Общие константы, используемые в нескольких модулях.
enum TaskbarConstants {
    /// Высота панели задач в points. Используется как самой панелью (`TaskbarPanel`),
    /// так и логикой снапа окон (`WindowSnapService`) — окно, развёрнутое "под Taskbar",
    /// не должно перекрываться нашей панелью снизу экрана.
    static let panelHeight: CGFloat = 40
}
