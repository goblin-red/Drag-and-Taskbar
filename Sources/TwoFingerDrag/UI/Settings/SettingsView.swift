import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.enabled) private var enabled: Bool = true
    @AppStorage(SettingsKey.launchAtLogin) private var launchAtLogin: Bool = true
    @AppStorage(SettingsKey.modifier) private var modifierRaw: String = DragModifier.option.rawValue
    @AppStorage(SettingsKey.fingers) private var fingers: Int = 1
    @AppStorage(SettingsKey.shiftCancelsDrag) private var shiftCancelsDrag: Bool = true
    @AppStorage(SettingsKey.sensitivity) private var sensitivity: Double = 2.0
    @AppStorage(SettingsKey.swipes) private var swipes: Bool = true
    @AppStorage(SettingsKey.swipeMethod) private var swipeMethod: String = "window"
    @AppStorage(SettingsKey.swipeLeftAction) private var swipeLeftActionRaw: String = WindowSwipeAction.minimize.rawValue
    @AppStorage(SettingsKey.swipeRightAction) private var swipeRightActionRaw: String = WindowSwipeAction.minimize.rawValue
    @AppStorage(SettingsKey.swipeThreshold) private var swipeThreshold: Double = 50
    @AppStorage(SettingsKey.swipeFlick) private var swipeFlick: Double = 18
    @AppStorage(SettingsKey.swipeIndicatorGain) private var swipeIndicatorGain: Double = 1.8
    @AppStorage(SettingsKey.zoom) private var zoom: Bool = false
    @AppStorage(SettingsKey.exitFullscreenOnSwipeDown) private var exitFullscreenOnSwipeDown: Bool = true
    @AppStorage(SettingsKey.activateOnControl) private var activateOnControl: Bool = true
    @AppStorage(SettingsKey.activateOnModifierPress) private var activateOnModifierPress: Bool = true
    @AppStorage(SettingsKey.activateOnModifierHover) private var activateOnModifierHover: Bool = true
    @AppStorage(SettingsKey.activateModifier) private var activateModifierRaw: String = DragModifier.control.rawValue
    @AppStorage(SettingsKey.optionMouseDrag) private var optionMouseDrag: Bool = true
    @AppStorage(SettingsKey.optionSwipeHorizontal) private var optionSwipeHorizontal: Bool = true
    @AppStorage(SettingsKey.optionSwipeVertical) private var optionSwipeVertical: Bool = true
    @AppStorage(SettingsKey.appSwitcherEnabled) private var appSwitcherEnabled: Bool = true
    @AppStorage(SettingsKey.appSwitcherModifier) private var appSwitcherModifierRaw: String = DragModifier.option.rawValue
    @AppStorage(SettingsKey.appSwitcherMode) private var appSwitcherModeRaw: String = AppSwitcherMode.compact.rawValue
    @AppStorage(SettingsKey.resizeEnabled) private var resizeEnabled: Bool = true
    @AppStorage(SettingsKey.resizeModifier) private var resizeModifierRaw: String = DragModifier.control.rawValue
    @AppStorage(SettingsKey.resizeGain) private var resizeGain: Double = 2.0
    @AppStorage(SettingsKey.resizeTwoAxis) private var resizeTwoAxis: Bool = false
    @AppStorage(SettingsKey.resizeMemorySeconds) private var resizeMemorySeconds: Double = 5.0
    @AppStorage(SettingsKey.language) private var languageRaw: String = AppLanguage.en.rawValue

    private var modifier: Binding<DragModifier> {
        Binding(
            get: { DragModifier(rawValue: modifierRaw) ?? .option },
            set: { modifierRaw = $0.rawValue }
        )
    }

    private var resizeModifier: Binding<DragModifier> {
        Binding(
            get: { DragModifier(rawValue: resizeModifierRaw) ?? .control },
            set: { resizeModifierRaw = $0.rawValue }
        )
    }

    private var activateModifier: Binding<DragModifier> {
        Binding(
            get: { DragModifier(rawValue: activateModifierRaw) ?? .control },
            set: { activateModifierRaw = $0.rawValue }
        )
    }

    private var appSwitcherModifier: Binding<DragModifier> {
        Binding(
            get: { DragModifier(rawValue: appSwitcherModifierRaw) ?? .option },
            set: { appSwitcherModifierRaw = $0.rawValue }
        )
    }

    private var appSwitcherMode: Binding<AppSwitcherMode> {
        Binding(
            get: { AppSwitcherMode(rawValue: appSwitcherModeRaw) ?? .compact },
            set: { appSwitcherModeRaw = $0.rawValue }
        )
    }

    private var swipeLeftAction: Binding<WindowSwipeAction> {
        Binding(
            get: { WindowSwipeAction(rawValue: swipeLeftActionRaw) ?? .minimize },
            set: { swipeLeftActionRaw = $0.rawValue }
        )
    }

    private var swipeRightAction: Binding<WindowSwipeAction> {
        Binding(
            get: { WindowSwipeAction(rawValue: swipeRightActionRaw) ?? .minimize },
            set: { swipeRightActionRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView {
            DragSettingsTab(
                enabled: $enabled,
                modifier: modifier,
                fingers: $fingers,
                sensitivity: $sensitivity,
                shiftCancelsDrag: $shiftCancelsDrag
            )
            .tabItem { Label(tr("Drag", "Перетаскивание"), systemImage: "hand.draw") }

            SwipeSettingsTab(
                fingers: $fingers,
                swipes: $swipes,
                swipeMethod: $swipeMethod,
                swipeLeftAction: swipeLeftAction,
                swipeRightAction: swipeRightAction,
                swipeThreshold: $swipeThreshold,
                swipeFlick: $swipeFlick
            )
            .tabItem { Label(tr("Swipes", "Свайпы"), systemImage: "arrow.left.arrow.right") }

            WindowSettingsTab(
                modifier: modifier,
                zoom: $zoom,
                exitFullscreenOnSwipeDown: $exitFullscreenOnSwipeDown,
                swipeThreshold: $swipeThreshold,
                swipeFlick: $swipeFlick,
                swipeIndicatorGain: $swipeIndicatorGain,
                optionMouseDrag: $optionMouseDrag,
                optionSwipeHorizontal: $optionSwipeHorizontal,
                optionSwipeVertical: $optionSwipeVertical
            )
            .tabItem { Label(tr("Window", "Окно"), systemImage: "macwindow") }

            FocusSettingsTab(
                activateOnControl: $activateOnControl,
                activateOnModifierPress: $activateOnModifierPress,
                activateOnModifierHover: $activateOnModifierHover,
                activateModifier: activateModifier
            )
            .tabItem { Label(tr("Focus", "Фокус"), systemImage: "scope") }

            AppSwitcherSettingsTab(
                appSwitcherEnabled: $appSwitcherEnabled,
                appSwitcherModifier: appSwitcherModifier,
                appSwitcherMode: appSwitcherMode
            )
            .tabItem { Label(tr("Taskbar", "Таск-панель"), systemImage: "square.grid.2x2") }

            ResizeSettingsTab(
                modifier: modifier,
                optionSwipeHorizontal: $optionSwipeHorizontal,
                optionSwipeVertical: $optionSwipeVertical,
                resizeEnabled: $resizeEnabled,
                resizeModifier: resizeModifier,
                resizeGain: $resizeGain,
                resizeTwoAxis: $resizeTwoAxis,
                resizeMemorySeconds: $resizeMemorySeconds
            )
            .tabItem { Label(tr("Resize", "Размер"), systemImage: "arrow.up.left.and.arrow.down.right") }

            AccessSettingsTab(
                launchAtLogin: $launchAtLogin,
                resetDefaults: resetDefaults
            )
                .tabItem { Label(tr("Access", "Доступ"), systemImage: "lock.shield") }
        }
        // при смене языка все вкладки пересоздаются с новыми подписями
        .id(languageRaw)
        .frame(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight)
        .padding(.top, 6)
        .navigationTitle(tr("Settings — GOBL(in) Drag", "Настройки — GOBL(in) Drag"))
    }

    private func resetDefaults() {
        enabled = true
        launchAtLogin = true
        modifierRaw = DragModifier.option.rawValue
        fingers = 1
        shiftCancelsDrag = true
        sensitivity = 2.0
        swipes = true
        swipeMethod = "window"
        swipeLeftActionRaw = WindowSwipeAction.minimize.rawValue
        swipeRightActionRaw = WindowSwipeAction.minimize.rawValue
        swipeThreshold = 50
        swipeFlick = 18
        swipeIndicatorGain = 1.8
        zoom = false
        exitFullscreenOnSwipeDown = true
        activateOnControl = true
        activateOnModifierPress = true
        activateOnModifierHover = true
        activateModifierRaw = DragModifier.control.rawValue
        optionMouseDrag = true
        optionSwipeHorizontal = true
        optionSwipeVertical = true
        appSwitcherEnabled = true
        appSwitcherModifierRaw = DragModifier.option.rawValue
        appSwitcherModeRaw = AppSwitcherMode.compact.rawValue
        resizeEnabled = true
        resizeModifierRaw = DragModifier.control.rawValue
        resizeGain = 2.0
        resizeTwoAxis = false
        resizeMemorySeconds = 5.0
    }
}
