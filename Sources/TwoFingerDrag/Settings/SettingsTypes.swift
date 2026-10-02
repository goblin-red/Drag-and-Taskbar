import AppKit

/// Доступные модификаторы для активации перетаскивания.
enum DragModifier: String, CaseIterable, Identifiable {
    case command
    case option
    case control

    var id: String { rawValue }

    var title: String {
        switch self {
        case .command: return "⌘ Command"
        case .option:  return "⌥ Option"
        case .control: return "⌃ Control"
        }
    }

    var cgFlag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option:  return .maskAlternate
        case .control: return .maskControl
        }
    }
}

/// Действие горизонтального свайпа.
enum WindowSwipeAction: String, CaseIterable, Identifiable {
    case minimize
    case close

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimize: return tr("Minimize", "Свернуть")
        case .close: return tr("Close", "Закрыть")
        }
    }
}

/// Режим отображения панели modifier+Tab.
enum AppSwitcherMode: String, CaseIterable, Identifiable {
    case compact
    case windows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return tr("Compact", "Сокращённый")
        case .windows: return tr("Extended", "Расширенный")
        }
    }
}

/// Ключи настроек в UserDefaults.
enum SettingsKey {
    static let enabled     = "enabled"
    static let launchAtLogin = "launchAtLogin"
    static let modifier    = "modifier"
    static let fingers     = "fingers"
    static let shiftCancelsDrag = "shiftCancelsDrag"
    static let sensitivity = "sensitivity"
    static let swipes      = "swipes"
    static let swipeMethod = "swipeMethod"
    static let swipeLeftAction = "swipeLeftAction"
    static let swipeRightAction = "swipeRightAction"
    static let swipeThreshold = "swipeThreshold"
    static let swipeFlick     = "swipeFlick"
    static let swipeIndicatorGain = "swipeIndicatorGain"
    static let zoom           = "zoom"
    static let exitFullscreenOnSwipeDown = "exitFullscreenOnSwipeDown"
    static let activateOnControl = "activateOnControl"
    static let activateOnModifierPress = "activateOnModifierPress"
    static let activateOnModifierHover = "activateOnModifierHover"
    static let activateModifier = "activateModifier"
    static let optionMouseDrag = "optionMouseDrag"
    static let optionSwipeHorizontal = "optionSwipeHorizontal"
    static let optionSwipeVertical = "optionSwipeVertical"
    static let appSwitcherEnabled = "appSwitcherEnabled"
    static let appSwitcherModifier = "appSwitcherModifier"
    static let appSwitcherMode = "appSwitcherMode"
    static let resizeEnabled  = "resizeEnabled"
    static let resizeModifier = "resizeModifier"
    static let resizeGain     = "resizeGain"
    static let resizeTwoAxis  = "resizeTwoAxis"
    static let resizeMemorySeconds = "resizeMemorySeconds"
    static let language = "language"
}
