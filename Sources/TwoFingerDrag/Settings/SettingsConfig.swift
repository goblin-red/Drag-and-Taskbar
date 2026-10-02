import Foundation

private enum ConfigValueKind {
    case bool
    case int
    case double
    case string(Set<String>)
}

private struct SettingsConfigEntry {
    let key: String
    let defaultValue: String
    let kind: ConfigValueKind
    let comment: String
    let commentRu: String

    /// Комментарий на текущем языке интерфейса.
    var localizedComment: String { tr(comment, commentRu) }
}

final class SettingsConfig {
    static let shared = SettingsConfig()

    /// Папка проекта: та, в которой лежит сам GOBL(in) Drag.app.
    /// Путь не захардкожен — проект работает из любой директории.
    static let projectDirectory: URL = {
        let bundleURL = Bundle.main.bundleURL
        // Собранное приложение: .../<папка проекта>/GOBL(in) Drag.app
        if bundleURL.pathExtension == "app" {
            return bundleURL.deletingLastPathComponent()
        }
        // Запуск бинарника напрямую (без бандла) — берём папку исполняемого файла.
        return URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
    }()

    let configURL = SettingsConfig.projectDirectory.appendingPathComponent("config.txt")
    let defaultConfigURL = SettingsConfig.projectDirectory.appendingPathComponent("default-config.txt")

    private var observer: NSObjectProtocol?
    private var pendingSave: DispatchWorkItem?

    private static let entries: [SettingsConfigEntry] = [
        .init(key: SettingsKey.enabled, defaultValue: "true", kind: .bool,
              comment: "Master switch of the app.",
              commentRu: "Главный выключатель приложения."),
        .init(key: SettingsKey.launchAtLogin, defaultValue: "true", kind: .bool,
              comment: "Open the app at macOS login.",
              commentRu: "Запускать приложение при входе в macOS."),
        .init(key: SettingsKey.modifier, defaultValue: DragModifier.option.rawValue,
              kind: .string(Set(DragModifier.allCases.map(\.rawValue))),
              comment: "Drag modifier: command, option or control.",
              commentRu: "Модификатор перетаскивания: command, option или control."),
        .init(key: SettingsKey.fingers, defaultValue: "1", kind: .int,
              comment: "Drag mode: 1 - the window follows the cursor, 2 - two-finger gesture, 3 - only while the modifier and the right mouse button are held.",
              commentRu: "Режим перетаскивания: 1 - окно едет за курсором, 2 - жест двумя пальцами, 3 - только при зажатых модификаторе и правой кнопке мыши."),
        .init(key: SettingsKey.shiftCancelsDrag, defaultValue: "true", kind: .bool,
              comment: "Holding Shift cancels the window drag (1 and 2 fingers); focus keeps following the cursor, as with Control.",
              commentRu: "Зажатый Shift отменяет перетаскивание окна (1 и 2 пальца); фокус продолжает следовать за курсором, как при Control."),
        .init(key: SettingsKey.sensitivity, defaultValue: "2.0", kind: .double,
              comment: "Travel gain for the two-finger drag mode.",
              commentRu: "Усиление хода для режима перетаскивания двумя пальцами."),
        .init(key: SettingsKey.swipes, defaultValue: "true", kind: .bool,
              comment: "Enable two-finger swipes in the 1-finger drag mode.",
              commentRu: "Включить свайпы двумя пальцами в режиме перетаскивания 1 палец."),
        .init(key: SettingsKey.swipeMethod, defaultValue: "window",
              kind: .string(Set(["window", "keys"])),
              comment: "How horizontal swipes act: window - the window under the cursor, keys - the active window via Command+M/W.",
              commentRu: "Как выполнять горизонтальные свайпы: window - окно под курсором, keys - активное окно через Command+M/W."),
        .init(key: SettingsKey.swipeLeftAction, defaultValue: WindowSwipeAction.minimize.rawValue,
              kind: .string(Set(WindowSwipeAction.allCases.map(\.rawValue))),
              comment: "Action for the left swipe: close or minimize.",
              commentRu: "Действие для свайпа влево: close - закрыть, minimize - свернуть."),
        .init(key: SettingsKey.swipeRightAction, defaultValue: WindowSwipeAction.minimize.rawValue,
              kind: .string(Set(WindowSwipeAction.allCases.map(\.rawValue))),
              comment: "Action for the right swipe: close or minimize.",
              commentRu: "Действие для свайпа вправо: close - закрыть, minimize - свернуть."),
        .init(key: SettingsKey.swipeThreshold, defaultValue: "50.0", kind: .double,
              comment: "Travel in points that triggers a slow swipe.",
              commentRu: "Ход в пунктах для срабатывания медленного свайпа."),
        .init(key: SettingsKey.swipeFlick, defaultValue: "18.0", kind: .double,
              comment: "Flick speed threshold. Lower - a quick swipe is caught more easily.",
              commentRu: "Порог скорости флика. Меньше - резкий свайп ловится легче."),
        .init(key: SettingsKey.swipeIndicatorGain, defaultValue: "1.8", kind: .double,
              comment: "Movement gain of the gesture indicator circle.",
              commentRu: "Усиление движения кружка-индикатора жеста."),
        .init(key: SettingsKey.zoom, defaultValue: "false", kind: .bool,
              comment: "Command + double click maximizes/restores the window.",
              commentRu: "Command + двойной клик разворачивает/возвращает окно."),
        .init(key: SettingsKey.exitFullscreenOnSwipeDown, defaultValue: "true", kind: .bool,
              comment: "A swipe down takes the window out of native full screen if it is there (the AXFullScreen attribute).",
              commentRu: "Свайп вниз выводит окно из нативного полноэкранного режима, если оно там сейчас (атрибут AXFullScreen)."),
        .init(key: SettingsKey.activateOnControl, defaultValue: "true", kind: .bool,
              comment: "Activate the window when GOBL(in) Drag starts controlling it.",
              commentRu: "Активировать окно, когда GOBL(in) Drag начинает им управлять."),
        .init(key: SettingsKey.activateOnModifierPress, defaultValue: "true", kind: .bool,
              comment: "Activate the window under the cursor on a plain press of the chosen modifier.",
              commentRu: "Активировать окно под курсором при простом нажатии выбранного модификатора."),
        .init(key: SettingsKey.activateOnModifierHover, defaultValue: "true", kind: .bool,
              comment: "Activate the window under the cursor when the mouse moves with the activation modifier held.",
              commentRu: "Активировать окно под курсором при движении мыши с зажатым модификатором активации."),
        .init(key: SettingsKey.activateModifier, defaultValue: DragModifier.control.rawValue,
              kind: .string(Set(DragModifier.allCases.map(\.rawValue))),
              comment: "Modifier that activates a window on press or movement: command, option or control.",
              commentRu: "Модификатор активации окна по нажатию или движению: command, option или control."),
        .init(key: SettingsKey.optionMouseDrag, defaultValue: "true", kind: .bool,
              comment: "Duplicate dragging a window with the cursor on Option+mouse movement.",
              commentRu: "Дублировать на Option+движение мыши перетаскивание окна курсором."),
        .init(key: SettingsKey.optionSwipeHorizontal, defaultValue: "true", kind: .bool,
              comment: "Duplicate the horizontal swipe actions of the main modifier on Option+swipe left/right.",
              commentRu: "Дублировать на Option+свайп влево/вправо действия горизонтальных свайпов основного модификатора."),
        .init(key: SettingsKey.optionSwipeVertical, defaultValue: "true", kind: .bool,
              comment: "Duplicate maximizing and restoring the window on Option+swipe up/down.",
              commentRu: "Дублировать на Option+свайп вверх/вниз разворачивание и возврат размера окна."),
        .init(key: SettingsKey.appSwitcherEnabled, defaultValue: "true", kind: .bool,
              comment: "Enable app switching with modifier+Tab without the system panel.",
              commentRu: "Включить переключение приложений по modifier+Tab без системной панели."),
        .init(key: SettingsKey.appSwitcherModifier, defaultValue: DragModifier.option.rawValue,
              kind: .string(Set(DragModifier.allCases.map(\.rawValue))),
              comment: "App switcher modifier: command, option or control.",
              commentRu: "Модификатор переключателя приложений: command, option или control."),
        .init(key: SettingsKey.appSwitcherMode, defaultValue: AppSwitcherMode.compact.rawValue,
              kind: .string(Set(AppSwitcherMode.allCases.map(\.rawValue))),
              comment: "Switcher panel view: compact - visible apps of the current desktop, windows - all windows of running apps, including minimized ones.",
              commentRu: "Вид панели переключателя: compact - видимые приложения текущего рабочего стола, windows - все окна запущенных приложений, включая свернутые."),
        .init(key: SettingsKey.resizeEnabled, defaultValue: "true", kind: .bool,
              comment: "Enable resizing with a two-finger swipe.",
              commentRu: "Включить изменение размера свайпом двумя пальцами."),
        .init(key: SettingsKey.resizeModifier, defaultValue: DragModifier.control.rawValue,
              kind: .string(Set(DragModifier.allCases.map(\.rawValue))),
              comment: "Resize modifier: command, option or control. Must differ from modifier.",
              commentRu: "Модификатор изменения размера: command, option или control. Должен отличаться от modifier."),
        .init(key: SettingsKey.resizeGain, defaultValue: "2.0", kind: .double,
              comment: "Window resize speed.",
              commentRu: "Скорость изменения размера окна."),
        .init(key: SettingsKey.resizeTwoAxis, defaultValue: "false", kind: .bool,
              comment: "Change the window width and height together during a resize gesture.",
              commentRu: "Менять ширину и высоту окна одновременно при resize-жесте."),
        .init(key: SettingsKey.resizeMemorySeconds, defaultValue: "5.0", kind: .double,
              comment: "How many seconds to remember the last resize gesture direction for a window. 0 - turn the memory off.",
              commentRu: "Сколько секунд помнить последнее направление resize-жеста для окна. 0 - отключить память."),
        .init(key: SettingsKey.language, defaultValue: AppLanguage.en.rawValue,
              kind: .string(Set(AppLanguage.allCases.map(\.rawValue))),
              comment: "Interface language: en or ru.",
              commentRu: "Язык интерфейса: en или ru.")
    ]

    private init() {}

    func loadIntoUserDefaults() {
        let defaults = UserDefaults.standard

        guard FileManager.default.fileExists(atPath: configURL.path),
              let text = try? String(contentsOf: configURL, encoding: .utf8) else {
            writeFromUserDefaults(defaults)
            writeDefaultBackup()
            return
        }

        var loadedKeys = Set<String>()

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !line.isEmpty else { continue }

            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let entry = Self.entries.first(where: { $0.key == key }) else { continue }
            apply(value: value, for: entry, defaults: defaults)
            loadedKeys.insert(key)
        }

        if !loadedKeys.contains(SettingsKey.activateModifier) {
            let currentModifier = defaults.string(forKey: SettingsKey.modifier) ?? DragModifier.option.rawValue
            defaults.set(currentModifier, forKey: SettingsKey.activateModifier)
        }

        writeFromUserDefaults(defaults)
        writeDefaultBackup()
    }

    func saveNow() {
        pendingSave?.cancel()
        writeFromUserDefaults(UserDefaults.standard)
        writeDefaultBackup()
    }

    func startAutosave() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleSave()
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.writeFromUserDefaults(UserDefaults.standard)
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func apply(value: String, for entry: SettingsConfigEntry, defaults: UserDefaults) {
        switch entry.kind {
        case .bool:
            let lower = value.lowercased()
            if ["true", "yes", "1", "on"].contains(lower) {
                defaults.set(true, forKey: entry.key)
            } else if ["false", "no", "0", "off"].contains(lower) {
                defaults.set(false, forKey: entry.key)
            }
        case .int:
            if let intValue = Int(value) {
                defaults.set(intValue, forKey: entry.key)
            }
        case .double:
            if let doubleValue = Double(value) {
                defaults.set(doubleValue, forKey: entry.key)
            }
        case .string(let allowed):
            if allowed.contains(value) {
                defaults.set(value, forKey: entry.key)
            }
        }
    }

    private func writeFromUserDefaults(_ defaults: UserDefaults) {
        let text = render(defaults: defaults)
        try? text.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func writeDefaultBackup() {
        let text = renderDefaultConfig()
        try? text.write(to: defaultConfigURL, atomically: true, encoding: .utf8)
    }

    private func render(defaults: UserDefaults) -> String {
        var lines: [String] = [
            "# GOBL(in) Drag configuration",
            tr("# This file can be edited in a text editor.", "# Файл можно редактировать в текстовом редакторе."),
            tr("# Settings are read when the app starts.", "# Настройки считываются при запуске приложения."),
            tr("# Boolean: true/false. Write strings without quotes.", "# Boolean: true/false. Строки писать без кавычек."),
            ""
        ]

        for entry in Self.entries {
            lines.append("# \(entry.localizedComment)")
            lines.append("\(entry.key) = \(stringValue(for: entry, defaults: defaults))")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func renderDefaultConfig() -> String {
        var lines: [String] = [
            "# GOBL(in) Drag default configuration backup",
            tr("# Factory values of the settings. This file is a backup of the defaults.",
               "# Заводские значения настроек. Этот файл нужен как резервная копия дефолтов."),
            tr("# Boolean: true/false. Write strings without quotes.", "# Boolean: true/false. Строки писать без кавычек."),
            ""
        ]

        for entry in Self.entries {
            lines.append("# \(entry.localizedComment)")
            lines.append("\(entry.key) = \(entry.defaultValue)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func stringValue(for entry: SettingsConfigEntry, defaults: UserDefaults) -> String {
        switch entry.kind {
        case .bool:
            return defaults.bool(forKey: entry.key) ? "true" : "false"
        case .int:
            return "\(defaults.integer(forKey: entry.key))"
        case .double:
            let value = defaults.double(forKey: entry.key)
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.1f", value)
                : "\(value)"
        case .string:
            return defaults.string(forKey: entry.key) ?? entry.defaultValue
        }
    }
}
