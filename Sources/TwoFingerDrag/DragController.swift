import AppKit
import ApplicationServices
import QuartzCore

private struct ResizeGestureMemory {
    let windowKey: String
    let axis: Int
    let rawDirection: CGFloat
    let actionDirection: CGFloat
    let timestamp: CFTimeInterval
}

/// Контроллер: пока зажат модификатор, окно под курсором перемещается.
/// Режим 1 пальца — окно едет за курсором (1:1).
/// Режим 2 пальцев — окно двигается жестом скролла (курсор замирает).
final class DragController {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let windows = WindowAccess()

    // Состояние текущего перетаскивания.
    private var dragging = false
    private var draggedWindow: AXUIElement?
    private var windowStartPos: CGPoint = .zero
    private var dragStartLoc: CGPoint = .zero      // для режима 1 пальца
    private var accumulated: CGSize = .zero         // для режима 2 пальцев
    private var lastScrollTime: CFTimeInterval = 0  // для режима 2 пальцев

    // Состояние распознавания свайпов (режим 1 пальца).
    private var swipeX: CGFloat = 0
    private var swipeY: CGFloat = 0
    private var swipeFired = false
    private var lastSwipeTime: CFTimeInterval = 0
    private var mainModifierDown = false
    private var activationModifierDown = false

    // Режим «правая кнопка мыши» (fingers == 3): жест начался с модификатором,
    // значит правый клик мы поглотили и обязаны поглотить парный rightMouseUp.
    private var rightButtonDragActive = false
    private var lastModifierHoverActivationTime: CFTimeInterval = 0

    // Коды клавиш для системных комбинаций.
    private let keyW: CGKeyCode = 13
    private let keyM: CGKeyCode = 46
    private let keyTab: CGKeyCode = 48

    // Состояние изменения размера (модификатор ресайза + свайп).
    private var resizing = false
    private var resizeWindow: AXUIElement?
    private var resizeTargetFrame: CGRect = .zero
    private var resizeBounds: CGRect?
    private var resizeShares = ResizeEdgeShares.balanced
    private var resAccX: CGFloat = 0
    private var resAccY: CGFloat = 0
    private var resAxis = 0        // 0 — не зафиксирована, 1 — горизонталь, 2 — вертикаль
    private var resInitDir: CGFloat = 0
    private var resInitDirX: CGFloat = 0
    private var resInitDirY: CGFloat = 0
    private var resizeSharesX = ResizeEdgeShares.balanced
    private var resizeSharesY = ResizeEdgeShares.balanced
    private var resizeWindowKey: String?
    private var resizeMemory: ResizeGestureMemory?
    private var lastResizeTime: CFTimeInterval = 0

    // Применение frame (position + size) в фоне со «склейкой».
    private var pendingFrame: CGRect?
    private var frameWindow: AXUIElement?
    private var applyingFrame = false

    // Память для возврата размера после «расширить окно» (зум).
    private var zoomMemory: (window: AXUIElement, frame: CGRect)?

    // Инфо о потоке tap'а для окна настроек (имя + tid).
    static var tapThreadID = "—"

    // Фоновое применение позиции (чтобы медленные AX-вызовы не тормозили event tap).
    private let applyQueue = DispatchQueue(label: "com.local.twofingerdrag.apply")
    private let lock = NSLock()
    private var pendingPos: CGPoint?
    private var applying = false

    // MARK: - Запуск

    func start() {
        registerDefaults()
        SettingsConfig.shared.loadIntoUserDefaults()
        requestAccessibilityIfNeeded()
        // Event tap держим на отдельном потоке со своим run loop, а НЕ на главном:
        // иначе синхронные AX-вызовы в обработчике блокируют UI и приводят
        // к взаимоблокировке с AppKit (замок иерархии вью).
        let thread = Thread { [weak self] in
            var tid: __uint64_t = 0
            pthread_threadid_np(nil, &tid)
            DragController.tapThreadID = "\(Thread.current.name ?? "tap") #\(tid)"
            self?.setupEventTap()
            CFRunLoopRun()
        }
        thread.name = "com.local.twofingerdrag.tap"
        thread.start()
    }

    private func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.enabled: true,
            SettingsKey.launchAtLogin: true,
            SettingsKey.modifier: DragModifier.option.rawValue,
            SettingsKey.fingers: 1,
            SettingsKey.shiftCancelsDrag: true,
            SettingsKey.sensitivity: 2.0,
            SettingsKey.swipes: true,
            SettingsKey.swipeMethod: "window",
            SettingsKey.swipeLeftAction: WindowSwipeAction.minimize.rawValue,
            SettingsKey.swipeRightAction: WindowSwipeAction.minimize.rawValue,
            SettingsKey.swipeThreshold: 50.0,
            SettingsKey.swipeFlick: 18.0,
            SettingsKey.swipeIndicatorGain: 1.8,
            SettingsKey.zoom: false,
            SettingsKey.exitFullscreenOnSwipeDown: true,
            SettingsKey.activateOnControl: true,
            SettingsKey.activateOnModifierPress: true,
            SettingsKey.activateOnModifierHover: true,
            SettingsKey.activateModifier: DragModifier.control.rawValue,
            SettingsKey.optionMouseDrag: true,
            SettingsKey.optionSwipeHorizontal: true,
            SettingsKey.optionSwipeVertical: true,
            SettingsKey.appSwitcherEnabled: true,
            SettingsKey.appSwitcherModifier: DragModifier.option.rawValue,
            SettingsKey.appSwitcherMode: AppSwitcherMode.compact.rawValue,
            SettingsKey.resizeEnabled: true,
            SettingsKey.resizeModifier: DragModifier.control.rawValue,
            SettingsKey.resizeGain: 2.0,
            SettingsKey.resizeTwoAxis: false,
            SettingsKey.resizeMemorySeconds: 5.0,
            SettingsKey.language: AppLanguage.en.rawValue,
        ])
    }

    @discardableResult
    func requestAccessibilityIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    // MARK: - Event Tap

    private func setupEventTap() {
        let mask = (1 << CGEventType.mouseMoved.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)
                 | (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.scrollWheel.rawValue)
                 | (1 << CGEventType.leftMouseDown.rawValue)
                 | (1 << CGEventType.rightMouseDown.rawValue)
                 | (1 << CGEventType.rightMouseDragged.rawValue)
                 | (1 << CGEventType.rightMouseUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<DragController>.fromOpaque(refcon).takeUnretainedValue()
            return controller.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[TwoFingerDrag] Не удалось создать event tap — нужны разрешения Accessibility.")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[TwoFingerDrag] Event tap запущен.")
    }

    // MARK: - Обработка событий

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Система иногда отключает tap по таймауту — включаем обратно.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.enabled) else {
            mainModifierDown = false
            activationModifierDown = false
            rightButtonDragActive = false
            DispatchQueue.main.async { AppSwitcherController.shared.cancel() }
            DispatchQueue.main.async { SwipeIndicatorOverlay.shared.hide() }
            endDrag(); endResize()
            return Unmanaged.passUnretained(event)
        }

        let appSwitcherResult = handleAppSwitcher(type: type, event: event, defaults: defaults)
        if appSwitcherResult.handled {
            return appSwitcherResult.event
        }

        // --- Свитчер приложений виден: пока пользователь выбирает приложение,
        //     нельзя тащить/ресайзить чужое окно. Сбрасываем любые активные жесты
        //     и пропускаем событие как есть, чтобы системный mouseMoved дошёл до цели. ---
        let appSwitcherMod = DragModifier(
            rawValue: defaults.string(forKey: SettingsKey.appSwitcherModifier) ?? ""
        ) ?? .option
        if AppSwitcherController.shared.isVisible,
           event.flags.contains(appSwitcherMod.cgFlag) {
            endDrag()
            endResize()
            return Unmanaged.passUnretained(event)
        }

        // --- Изменение размера: СВОЙ модификатор, проверяем ПЕРВЫМ (приоритет над drag) ---
        if defaults.bool(forKey: SettingsKey.resizeEnabled) {
            let resizeMod = DragModifier(rawValue: defaults.string(forKey: SettingsKey.resizeModifier) ?? "")
                ?? .control
            if event.flags.contains(resizeMod.cgFlag) {
                if type == .scrollWheel {
                    return handleResize(event: event, defaults: defaults)
                }
            } else {
                endResize()
            }
        } else {
            endResize()
        }

        // --- Перетаскивание / свайпы / зум: модификатор перетаскивания ---
        let modifier = DragModifier(rawValue: defaults.string(forKey: SettingsKey.modifier) ?? "")
            ?? .command
        let isMainModifierDown = event.flags.contains(modifier.cgFlag)
        let activationModifier = DragModifier(rawValue: defaults.string(forKey: SettingsKey.activateModifier) ?? "")
            ?? modifier
        let isActivationModifierDown = event.flags.contains(activationModifier.cgFlag)

        // Зажатый Shift отменяет перетаскивание окна, оставляя только перевод фокуса
        // (поведение как при Control). Свайпы/зум под модификатором не затрагиваются.
        let shiftCancelsDrag = defaults.bool(forKey: SettingsKey.shiftCancelsDrag)
            && event.flags.contains(.maskShift)

        if type == .flagsChanged {
            if defaults.bool(forKey: SettingsKey.activateOnModifierPress) {
                if isActivationModifierDown && !activationModifierDown {
                    activationModifierDown = true
                    let loc = currentPointerLocation()
                    applyQueue.async { [weak self] in self?.windows.activateWindowUnderPoint(at: loc) }
                } else if !isActivationModifierDown {
                    activationModifierDown = false
                }
            } else {
                activationModifierDown = false
            }

            if isMainModifierDown && !mainModifierDown {
                mainModifierDown = true
            } else if !isMainModifierDown {
                mainModifierDown = false
            }
        }

        if type == .mouseMoved,
           defaults.bool(forKey: SettingsKey.activateOnModifierHover),
           isActivationModifierDown {
            activateWindowUnderMovingPointer(at: event.location)
        }

        let fingers = defaults.integer(forKey: SettingsKey.fingers)

        // --- Режим «правая кнопка мыши»: модификатор + зажатая ПКМ тащат окно за курсором ---
        // Правый клик поглощаем ТОЛЬКО когда зажат модификатор перетаскивания, поэтому
        // обычное контекстное меню (без модификатора) продолжает работать как раньше.
        if fingers == 3 {
            switch type {
            case .rightMouseDown where isMainModifierDown:
                rightButtonDragActive = true
                if shiftCancelsDrag {
                    endDrag()
                    followFocusOnHover(at: event.location, defaults: defaults)
                } else {
                    beginDrag(at: event.location)
                }
                return nil // поглощаем: контекстное меню не появится

            case .rightMouseDragged where rightButtonDragActive:
                if isMainModifierDown && !shiftCancelsDrag {
                    handleOneFinger(location: event.location)
                } else {
                    // Модификатор отпущен (или зажат Shift) — окно больше не двигаем,
                    // но жест держим до отпускания кнопки, чтобы поглотить парный up.
                    endDrag()
                    if shiftCancelsDrag {
                        followFocusOnHover(at: event.location, defaults: defaults)
                    }
                }
                return nil

            case .rightMouseUp where rightButtonDragActive:
                rightButtonDragActive = false
                endDrag()
                return nil

            default:
                break
            }
        }

        if type == .mouseMoved,
           fingers == 1,
           !isMainModifierDown,
           event.flags.contains(DragModifier.option.cgFlag),
           defaults.bool(forKey: SettingsKey.optionMouseDrag) {
            if shiftCancelsDrag {
                endDrag()
                followFocusOnHover(at: event.location, defaults: defaults)
            } else {
                handleOneFinger(location: event.location)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .scrollWheel,
           fingers == 1,
           !isMainModifierDown,
           event.flags.contains(DragModifier.option.cgFlag) {
            let optionHorizontal = defaults.bool(forKey: SettingsKey.optionSwipeHorizontal)
            let optionVertical = defaults.bool(forKey: SettingsKey.optionSwipeVertical)
            if optionHorizontal || optionVertical {
                return handleSwipe(
                    event: event,
                    defaults: defaults,
                    allowHorizontal: optionHorizontal,
                    allowVertical: optionVertical,
                    requireGlobalSwipes: false,
                    invertHorizontalIndicator: true
                )
            }
        }

        guard isMainModifierDown else {
            DispatchQueue.main.async { SwipeIndicatorOverlay.shared.hide() }
            endDrag()
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .mouseMoved where fingers == 1:
            if shiftCancelsDrag {
                endDrag()
                followFocusOnHover(at: event.location, defaults: defaults)
            } else {
                handleOneFinger(location: event.location)
            }
            return Unmanaged.passUnretained(event) // НЕ поглощаем — курсор должен двигаться

        case .scrollWheel where fingers == 2:
            if shiftCancelsDrag {
                endDrag()
                return Unmanaged.passUnretained(event) // перетаскивание отменено — скролл пропускаем
            }
            return handleTwoFinger(event: event)

        case .scrollWheel where fingers == 1:
            return handleSwipe(
                event: event,
                defaults: defaults,
                invertHorizontalIndicator: event.flags.contains(DragModifier.option.cgFlag)
            )

        case .leftMouseDown where defaults.bool(forKey: SettingsKey.zoom):
            // Двойной клик: второй down имеет clickState == 2.
            if event.getIntegerValueField(.mouseEventClickState) == 2 {
                let loc = event.location
                applyQueue.async { [weak self] in self?.zoomWindow(at: loc) }
                return nil // поглощаем двойной клик
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleAppSwitcher(type: CGEventType, event: CGEvent, defaults: UserDefaults) -> (handled: Bool, event: Unmanaged<CGEvent>?) {
        guard defaults.bool(forKey: SettingsKey.appSwitcherEnabled) else {
            if type == .flagsChanged {
                DispatchQueue.main.async { AppSwitcherController.shared.cancel() }
            }
            return (false, nil)
        }

        let modifier = DragModifier(rawValue: defaults.string(forKey: SettingsKey.appSwitcherModifier) ?? "")
            ?? .option
        let isModifierDown = event.flags.contains(modifier.cgFlag)

        if type == .keyDown,
           isModifierDown,
           CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == keyTab {
            DispatchQueue.main.async { AppSwitcherController.shared.advance() }
            return (true, nil)
        }

        if type == .leftMouseDown {
            let location = event.location
            var clickedSwitcher = false
            DispatchQueue.main.sync {
                clickedSwitcher = AppSwitcherController.shared.click(atTopLeftLocation: location)
            }
            if clickedSwitcher {
                return (true, nil)
            }
        }

        if type == .mouseMoved, AppSwitcherController.shared.isVisible {
            let location = event.location
            DispatchQueue.main.async {
                AppSwitcherController.shared.updateHover(atTopLeftLocation: location)
            }
        }

        if type == .flagsChanged, !isModifierDown {
            DispatchQueue.main.async { AppSwitcherController.shared.finish() }
        }

        return (false, nil)
    }

    /// Режим 1 пальца: окно едет ровно за курсором.
    private func handleOneFinger(location: CGPoint) {
        if !dragging {
            beginDrag(at: location)
        } else if draggedWindow != nil {
            let newPos = CGPoint(
                x: windowStartPos.x + (location.x - dragStartLoc.x),
                y: windowStartPos.y + (location.y - dragStartLoc.y)
            )
            scheduleApply(newPos)
        }
    }

    /// Режим 2 пальцев: окно двигается жестом скролла.
    private func handleTwoFinger(event: CGEvent) -> Unmanaged<CGEvent>? {
        // Инерция после отпускания пальцев — поглощаем, но окно не двигаем.
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 {
            return nil
        }

        let now = CACurrentMediaTime()
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        if phase == 1 || !dragging || (now - lastScrollTime) > 0.3 {
            beginDrag(at: event.location)
        }
        lastScrollTime = now

        if draggedWindow != nil {
            // Пиксельно-точные дельты трекпада; окно следует за пальцами.
            let axis1 = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) // вертикаль
            let axis2 = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) // горизонталь
            let s = UserDefaults.standard.double(forKey: SettingsKey.sensitivity)
            let sens = s > 0 ? s : 1.0
            accumulated.width  += -axis2 * sens
            accumulated.height += -axis1 * sens
            let newPos = CGPoint(
                x: windowStartPos.x + accumulated.width,
                y: windowStartPos.y + accumulated.height
            )
            scheduleApply(newPos)
        }

        return nil // поглощаем скролл, чтобы контент не прокручивался
    }

    /// Режим 1 пальца: свайп двумя пальцами.
    /// Горизонталь: действие левого/правого свайпа задаётся настройками.
    /// Вертикаль: вверх — максимизировать окно, вниз — вернуть прежний размер.
    private func handleSwipe(
        event: CGEvent,
        defaults: UserDefaults,
        allowHorizontal: Bool = true,
        allowVertical: Bool = true,
        requireGlobalSwipes: Bool = true,
        invertHorizontalIndicator: Bool = false
    ) -> Unmanaged<CGEvent>? {
        guard (!requireGlobalSwipes || defaults.bool(forKey: SettingsKey.swipes)),
              allowHorizontal || allowVertical else {
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 {
            return nil
        }

        let now = CACurrentMediaTime()
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        if phase == 1 || (now - lastSwipeTime) > 0.3 {
            swipeX = 0; swipeY = 0; swipeFired = false
        }
        lastSwipeTime = now

        let axis1 = CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)) // вертикаль
        let axis2 = CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)) // горизонталь
        swipeX += axis2
        swipeY += axis1

        let td = defaults.double(forKey: SettingsKey.swipeThreshold)
        let threshold: CGFloat = td > 0 ? CGFloat(td) : 50
        let fd = defaults.double(forKey: SettingsKey.swipeFlick)
        let flickSpeed: CGFloat = fd > 0 ? CGFloat(fd) : 18

        let location = event.location
        if max(abs(swipeX), abs(swipeY)) > 0 {
            let direction: SwipeIndicatorDirection
            let strength: CGFloat
            if abs(swipeX) >= abs(swipeY) {
                if !allowHorizontal { return Unmanaged.passUnretained(event) }
                direction = swipeX < 0 ? .left : .right
                strength = swipeX
            } else {
                if !allowVertical { return Unmanaged.passUnretained(event) }
                direction = swipeY > 0 ? .up : .down
                strength = swipeY
            }
            let indicatorDirection = invertHorizontalIndicator
                ? invertedHorizontalIndicatorDirection(for: direction)
                : direction
            showSwipeIndicator(at: location, direction: indicatorDirection, strength: strength, defaults: defaults)
        }

        if !swipeFired {
            if abs(swipeX) >= abs(swipeY) {
                guard allowHorizontal else { return Unmanaged.passUnretained(event) }
                // Горизонталь: свернуть / закрыть.
                let flick = abs(axis2) >= flickSpeed && abs(axis2) > abs(axis1)
                if abs(swipeX) > threshold || flick {
                    swipeFired = true
                    let actionKey = swipeX < 0 ? SettingsKey.swipeLeftAction : SettingsKey.swipeRightAction
                    let action = WindowSwipeAction(rawValue: defaults.string(forKey: actionKey) ?? "")
                        ?? .minimize
                    let byWindow = defaults.string(forKey: SettingsKey.swipeMethod) != "keys"
                    applyQueue.async { [weak self] in
                        guard let self = self else { return }
                        if byWindow {
                            self.performSwipeAction(action, at: location)
                        } else {
                            self.performShortcutSwipeAction(action, at: location)
                        }
                    }
                }
            } else {
                guard allowVertical else { return Unmanaged.passUnretained(event) }
                // Вертикаль: вверх — максимизировать, вниз — вернуть размер.
                let flick = abs(axis1) >= flickSpeed && abs(axis1) > abs(axis2)
                if abs(swipeY) > threshold || flick {
                    swipeFired = true
                    let up = swipeY > 0 // ПОДОБРАТЬ знак: вверх → максимизировать
                    applyQueue.async { [weak self] in
                        if up { self?.maximizeWindow(at: location) }
                        else  { self?.restoreWindow(at: location) }
                    }
                }
            }
        }

        return nil // поглощаем жест (и горизонталь, и вертикаль)
    }

    private func invertedHorizontalIndicatorDirection(for direction: SwipeIndicatorDirection) -> SwipeIndicatorDirection {
        switch direction {
        case .left:
            return .right
        case .right:
            return .left
        case .up, .down:
            return direction
        }
    }

    private func performSwipeAction(_ action: WindowSwipeAction, at location: CGPoint) {
        switch action {
        case .minimize:
            windows.minimizeWindow(
                at: location,
                activate: UserDefaults.standard.bool(forKey: SettingsKey.activateOnControl)
            )
        case .close:
            windows.closeWindow(
                at: location,
                activate: UserDefaults.standard.bool(forKey: SettingsKey.activateOnControl)
            )
        }
    }

    private func performShortcutSwipeAction(_ action: WindowSwipeAction, at location: CGPoint) {
        let shouldActivate = UserDefaults.standard.bool(forKey: SettingsKey.activateOnControl)
        windows.activateWindowUnderPointIfNeeded(at: location, shouldActivate: shouldActivate)
        if shouldActivate {
            Thread.sleep(forTimeInterval: 0.04)
        }
        postShortcut(action == .minimize ? keyM : keyW)
    }

    /// Посылает ⌘+<клавиша> активному приложению.
    private func postShortcut(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Логика перетаскивания

    private func beginDrag(at location: CGPoint) {
        dragStartLoc = location
        accumulated = .zero
        if let window = windows.windowUnderPoint(location) {
            draggedWindow = window
            windows.activateWindowIfNeeded(
                window,
                shouldActivate: UserDefaults.standard.bool(forKey: SettingsKey.activateOnControl)
            )
            windowStartPos = windows.windowPosition(window) ?? .zero
            dragging = true
        } else {
            draggedWindow = nil
            dragging = false
        }
    }

    private func endDrag() {
        dragging = false
        draggedWindow = nil
        swipeX = 0; swipeY = 0; swipeFired = false
        lock.lock()
        pendingPos = nil
        lock.unlock()
    }

    /// Кладёт новую целевую позицию и при необходимости запускает фоновый цикл.
    private func scheduleApply(_ pos: CGPoint) {
        lock.lock()
        pendingPos = pos
        let needStart = !applying
        if needStart { applying = true }
        lock.unlock()

        guard needStart else { return }
        applyQueue.async { [weak self] in self?.applyLoop() }
    }

    /// Применяет самую свежую позицию, отбрасывая промежуточные.
    private func applyLoop() {
        while true {
            lock.lock()
            guard let pos = pendingPos, let window = draggedWindow else {
                applying = false
                lock.unlock()
                return
            }
            pendingPos = nil
            lock.unlock()
            windows.setWindowPosition(window, pos)
        }
    }

    // MARK: - Изменение размера (модификатор ресайза + свайп двумя пальцами)

    /// Меняет размер окна под курсором, распределяя расширение по свободному месту у краёв.
    /// Если есть свежая память жеста для этого окна и оси, направление продолжает прошлую логику.
    private func handleResize(event: CGEvent, defaults: UserDefaults) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 {
            return nil
        }

        let now = CACurrentMediaTime()
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        if phase == 1 || !resizing || (now - lastResizeTime) > 0.3 {
            beginResize(at: event.location)
        }
        lastResizeTime = now

        guard resizing, resizeWindow != nil else { return nil }

        resAccX += CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)) // горизонталь
        resAccY += CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)) // вертикаль

        if defaults.bool(forKey: SettingsKey.resizeTwoAxis) {
            return handleTwoAxisResize(event: event, defaults: defaults, now: now)
        }

        // Фиксируем ось и направление «роста» по первому уверенному движению.
        if resAxis == 0, max(abs(resAccX), abs(resAccY)) > 6 {
            if abs(resAccX) >= abs(resAccY) {
                resAxis = 1
                resInitDir = resizeInitialDirection(axis: resAxis, rawDirection: sign(resAccX), now: now, defaults: defaults)
            } else {
                resAxis = 2
                resInitDir = resizeInitialDirection(axis: resAxis, rawDirection: sign(resAccY), now: now, defaults: defaults)
            }
            resetResizeShares(for: resizeTargetFrame)
        }

        if resAxis != 0 {
            let g = defaults.double(forKey: SettingsKey.resizeGain)
            let gain = CGFloat(g > 0 ? g : 2.0)
            let frame = resizeTargetFrame
            let bounds = resizeBounds
            var rect = frame
            var rawStep: CGFloat = 0
            if resAxis == 1 {
                rawStep = CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
            } else {
                rawStep = CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
            }
            let actionStep = rawStep * resInitDir
            let vector = resAxis == 1
                ? CGVector(dx: resAccX, dy: 0)
                : CGVector(dx: 0, dy: -resAccY)
            showResizeIndicator(
                at: event.location,
                vector: vector,
                defaults: defaults
            )
            rect = ResizeCalculator.resizeFrame(
                frame,
                axis: resAxis,
                delta: gain * actionStep,
                bounds: bounds,
                shares: resizeShares
            )
            resizeTargetFrame = rect
            rememberResizeStep(axis: resAxis, rawStep: rawStep, actionStep: actionStep, now: now)
            scheduleApplyFrame(window: resizeWindow!, rect: rect)
        }

        return nil // поглощаем скролл
    }

    private func handleTwoAxisResize(event: CGEvent, defaults: UserDefaults, now: CFTimeInterval) -> Unmanaged<CGEvent>? {
        if resInitDirX == 0, abs(resAccX) > 6 {
            resInitDirX = resizeInitialDirection(axis: 1, rawDirection: sign(resAccX), now: now, defaults: defaults)
            resizeSharesX = ResizeCalculator.edgeShares(
                for: resizeTargetFrame,
                bounds: resizeBounds,
                axis: 1,
                accX: resAccX,
                accY: 0
            )
        }
        if resInitDirY == 0, abs(resAccY) > 6 {
            resInitDirY = resizeInitialDirection(axis: 2, rawDirection: sign(resAccY), now: now, defaults: defaults)
            resizeSharesY = ResizeCalculator.edgeShares(
                for: resizeTargetFrame,
                bounds: resizeBounds,
                axis: 2,
                accX: 0,
                accY: resAccY
            )
        }

        guard resInitDirX != 0 || resInitDirY != 0 else { return nil }

        let rawX = CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
        let rawY = CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        let g = defaults.double(forKey: SettingsKey.resizeGain)
        let gain = CGFloat(g > 0 ? g : 2.0)
        var rect = resizeTargetFrame

        if resInitDirX != 0 {
            let actionStepX = rawX * resInitDirX
            rect = ResizeCalculator.resizeFrame(
                rect,
                axis: 1,
                delta: gain * actionStepX,
                bounds: resizeBounds,
                shares: resizeSharesX
            )
            rememberResizeStep(axis: 1, rawStep: rawX, actionStep: actionStepX, now: now)
        }

        if resInitDirY != 0 {
            let actionStepY = rawY * resInitDirY
            rect = ResizeCalculator.resizeFrame(
                rect,
                axis: 2,
                delta: gain * actionStepY,
                bounds: resizeBounds,
                shares: resizeSharesY
            )
            rememberResizeStep(axis: 2, rawStep: rawY, actionStep: actionStepY, now: now)
        }

        resizeTargetFrame = rect
        showResizeIndicator(
            at: event.location,
            vector: CGVector(
                dx: resInitDirX != 0 ? resAccX : 0,
                dy: resInitDirY != 0 ? -resAccY : 0
            ),
            defaults: defaults
        )
        scheduleApplyFrame(window: resizeWindow!, rect: rect)
        return nil
    }

    private func beginResize(at location: CGPoint) {
        resAccX = 0; resAccY = 0; resAxis = 0; resInitDir = 0; resInitDirX = 0; resInitDirY = 0
        if let window = windows.windowUnderPoint(location), let frame = windows.windowFrame(window) {
            resizeWindow = window
            resizeWindowKey = windows.windowIdentity(window)
            windows.activateWindowIfNeeded(
                window,
                shouldActivate: UserDefaults.standard.bool(forKey: SettingsKey.activateOnControl)
            )
            resizeTargetFrame = frame
            resizeBounds = windows.visibleFrameTopLeft(containing: CGPoint(x: frame.midX, y: frame.midY))
            resizeShares = .balanced
            resizeSharesX = .balanced
            resizeSharesY = .balanced
            resizing = true
        } else {
            resizeWindow = nil
            resizeWindowKey = nil
            resizeBounds = nil
            resizing = false
        }
    }

    private func endResize() {
        resizing = false
        resizeWindow = nil
        resizeWindowKey = nil
        resizeBounds = nil
        resInitDirX = 0
        resInitDirY = 0
        DispatchQueue.main.async { SwipeIndicatorOverlay.shared.hide() }
        lock.lock()
        pendingFrame = nil
        lock.unlock()
    }

    private func showSwipeIndicator(
        at location: CGPoint,
        direction: SwipeIndicatorDirection,
        strength: CGFloat,
        defaults: UserDefaults
    ) {
        let rawGain = defaults.double(forKey: SettingsKey.swipeIndicatorGain)
        let gain = CGFloat(rawGain > 0 ? rawGain : 1.8)
        DispatchQueue.main.async {
            SwipeIndicatorOverlay.shared.update(
                cursorTopLeft: location,
                direction: direction,
                strength: strength,
                gain: gain
            )
        }
    }

    private func showResizeIndicator(
        at location: CGPoint,
        vector: CGVector,
        defaults: UserDefaults
    ) {
        guard abs(vector.dx) > 0.01 || abs(vector.dy) > 0.01 else { return }
        let rawGain = defaults.double(forKey: SettingsKey.swipeIndicatorGain)
        let gain = CGFloat(rawGain > 0 ? rawGain : 1.8)
        DispatchQueue.main.async {
            SwipeIndicatorOverlay.shared.updateResize(
                cursorTopLeft: location,
                vector: vector,
                gain: gain
            )
        }
    }

    private func resizeInitialDirection(axis: Int, rawDirection: CGFloat, now: CFTimeInterval, defaults: UserDefaults) -> CGFloat {
        let memorySeconds = max(0, defaults.double(forKey: SettingsKey.resizeMemorySeconds))
        guard memorySeconds > 0,
              let windowKey = resizeWindowKey,
              let memory = resizeMemory,
              memory.windowKey == windowKey,
              memory.axis == axis,
              now - memory.timestamp <= memorySeconds else {
            return rawDirection
        }

        let desiredAction = memory.rawDirection == rawDirection
            ? memory.actionDirection
            : -memory.actionDirection
        return desiredAction * rawDirection
    }

    private func rememberResizeStep(axis: Int, rawStep: CGFloat, actionStep: CGFloat, now: CFTimeInterval) {
        guard abs(rawStep) > 0.01, abs(actionStep) > 0.01,
              let windowKey = resizeWindowKey else { return }
        resizeMemory = ResizeGestureMemory(
            windowKey: windowKey,
            axis: axis,
            rawDirection: sign(rawStep),
            actionDirection: sign(actionStep),
            timestamp: now
        )
    }

    private func sign(_ value: CGFloat) -> CGFloat {
        value >= 0 ? 1 : -1
    }

    private func resetResizeShares(for frame: CGRect) {
        resizeShares = ResizeCalculator.edgeShares(
            for: frame,
            bounds: resizeBounds,
            axis: resAxis,
            accX: resAccX,
            accY: resAccY
        )
    }

    /// Фоновое применение frame (position + size) со «склейкой».
    private func scheduleApplyFrame(window: AXUIElement, rect: CGRect) {
        lock.lock()
        pendingFrame = rect
        frameWindow = window
        let needStart = !applyingFrame
        if needStart { applyingFrame = true }
        lock.unlock()

        guard needStart else { return }
        applyQueue.async { [weak self] in self?.applyFrameLoop() }
    }

    private func applyFrameLoop() {
        while true {
            lock.lock()
            guard let rect = pendingFrame, let window = frameWindow else {
                applyingFrame = false
                lock.unlock()
                return
            }
            pendingFrame = nil
            lock.unlock()
            windows.setWindowPosition(window, rect.origin)
            windows.setWindowSize(window, rect.size)
        }
    }

    // MARK: - «Расширить окно» (максимизация / возврат)

    /// Двойной клик: переключает максимизацию (макс ↔ прежний размер).
    private func zoomWindow(at location: CGPoint) {
        guard let window = windows.windowUnderPoint(location),
              let current = windows.windowFrame(window) else { return }
        let center = CGPoint(x: current.midX, y: current.midY)
        guard let target = windows.visibleFrameTopLeft(containing: center) else { return }

        if let mem = zoomMemory, CFEqual(mem.window, window), windows.framesApproxEqual(current, target) {
            restoreWindow(at: location)
        } else {
            maximizeWindow(at: location)
        }
    }

    /// Разворачивает окно под курсором по visibleFrame экрана, запоминая прежний размер.
    private func maximizeWindow(at location: CGPoint) {
        guard let window = windows.windowUnderPoint(location),
              let current = windows.windowFrame(window) else { return }
        // Нативный fullscreen блокирует kAXSize/kAXPosition — не пытаемся менять.
        // Свайп вверх по уже полноэкранному окну = noop (ожидаемое поведение).
        if windows.isFullScreen(window) { return }
        let center = CGPoint(x: current.midX, y: current.midY)
        guard let target = windows.visibleFrameTopLeft(containing: center) else { return }
        if windows.framesApproxEqual(current, target) { return } // уже максимизировано
        windows.activateWindowIfNeeded(
            window,
            shouldActivate: UserDefaults.standard.bool(forKey: SettingsKey.activateOnControl)
        )
        zoomMemory = (window, current)
        windows.setWindowPosition(window, target.origin)
        windows.setWindowSize(window, target.size)
    }

    /// Возвращает прежний размер окна под курсором (если он запомнен).
    /// Если окно в нативном fullscreen и включено `exitFullscreenOnSwipeDown`, выходим из fullscreen
    /// до проверки zoomMemory — macOS сам анимирует возврат к прежнему «обычному» размеру.
    private func restoreWindow(at location: CGPoint) {
        guard let window = windows.windowUnderPoint(location) else { return }

        if UserDefaults.standard.bool(forKey: SettingsKey.exitFullscreenOnSwipeDown),
           windows.isFullScreen(window) {
            windows.activateWindowIfNeeded(
                window,
                shouldActivate: UserDefaults.standard.bool(forKey: SettingsKey.activateOnControl)
            )
            windows.setFullScreen(window, false)
            // После выхода из fullscreen Space сменится, ранее запомненный обычный frame
            // больше не нужен — macOS сам вернёт окно к «оконному» размеру.
            zoomMemory = nil
            return
        }

        guard let mem = zoomMemory, CFEqual(mem.window, window) else { return }
        windows.activateWindowIfNeeded(
            window,
            shouldActivate: UserDefaults.standard.bool(forKey: SettingsKey.activateOnControl)
        )
        windows.setWindowPosition(window, mem.frame.origin)
        windows.setWindowSize(window, mem.frame.size)
        zoomMemory = nil
    }

    private func currentPointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Перевод фокуса за курсором (как при Control): активирует окно под курсором,
    /// если включена активация по движению. Используется, когда Shift отменяет перетаскивание.
    private func followFocusOnHover(at location: CGPoint, defaults: UserDefaults) {
        guard defaults.bool(forKey: SettingsKey.activateOnModifierHover) else { return }
        activateWindowUnderMovingPointer(at: location)
    }

    private func activateWindowUnderMovingPointer(at location: CGPoint) {
        let now = CACurrentMediaTime()
        guard now - lastModifierHoverActivationTime >= 0.08 else { return }
        lastModifierHoverActivationTime = now
        applyQueue.async { [weak self] in
            self?.windows.activateWindowUnderPoint(at: location)
        }
    }
}
