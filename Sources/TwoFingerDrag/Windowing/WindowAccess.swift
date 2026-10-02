import AppKit
import ApplicationServices

/// Единственные ворота к Accessibility/CGWindowList для окон.
/// Новая функциональность не должна вызывать AX напрямую в gesture/UI слоях.
final class WindowAccess {
    struct SwitcherWindow {
        let app: NSRunningApplication
        let window: AXUIElement
        let appName: String
        let windowTitle: String
        let identity: String
        let isMinimized: Bool
    }

    private struct TopWindowInfo {
        let pid: pid_t
        let owner: String
        let name: String
        let number: Int
        let bounds: CGRect
    }

    private let systemWide = AXUIElementCreateSystemWide()

    static func visibleApplicationsForSwitcher() -> [(pid: pid_t, app: NSRunningApplication, name: String)] {
        let ownPID = getpid()
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else {
            return []
        }

        var seen = Set<pid_t>()
        var result: [(pid: pid_t, app: NSRunningApplication, name: String)] = []

        for info in windows {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else {
                continue
            }

            let pid = pidNumber.int32Value
            guard pid != ownPID, !seen.contains(pid),
                  let app = NSRunningApplication(processIdentifier: pid),
                  !app.isTerminated,
                  app.activationPolicy == .regular else {
                continue
            }

            seen.insert(pid)
            let name = app.localizedName ?? (info[kCGWindowOwnerName as String] as? String) ?? "App"
            result.append((pid, app, name))
        }

        return result
    }

    static func windowsForSwitcher() -> [SwitcherWindow] {
        let access = WindowAccess()
        let ownPID = pid_t(getpid())
        let apps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.processIdentifier != ownPID
                    && !app.isTerminated
                    && app.activationPolicy == .regular
            }
            .sorted { lhs, rhs in
                let lhsName = lhs.localizedName ?? ""
                let rhsName = rhs.localizedName ?? ""
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }

        var result: [SwitcherWindow] = []
        var seen = Set<String>()

        for app in apps {
            let appName = app.localizedName ?? "App"
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else {
                continue
            }

            for (index, window) in windows.enumerated() {
                guard access.isStandardWindow(window) else { continue }

                let identity = access.windowIdentity(window)
                guard !seen.contains(identity) else { continue }
                seen.insert(identity)

                let title = access.windowTitle(window)
                let minimized = access.isWindowMinimized(window) ?? false
                let displayTitle = title.isEmpty ? tr("Window \(index + 1)", "Окно \(index + 1)") : title
                result.append(SwitcherWindow(
                    app: app,
                    window: window,
                    appName: appName,
                    windowTitle: displayTitle,
                    identity: identity,
                    isMinimized: minimized
                ))
            }
        }

        return result
    }

    static func topLeftOwnWindowBounds(expectedSize: NSSize) -> CGRect? {
        let ownPID = getpid()
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else {
            return nil
        }

        for info in windows {
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  pidNumber.int32Value == ownPID,
                  let boundsDict = info[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary),
                  abs(bounds.width - expectedSize.width) < 4,
                  abs(bounds.height - expectedSize.height) < 4 else {
                continue
            }
            return bounds
        }

        return nil
    }

    func windowUnderPoint(_ point: CGPoint) -> AXUIElement? {
        // КРИТИЧНО: не трогаем собственные окна. AX-операции над своим же процессом
        // выполняются внутрипроцессно и приводят к взаимоблокировке с главным потоком.
        // Владельца окна определяем через оконный сервер (CGWindowList), без AX.
        if isPointOverOwnWindow(point) { return nil }

        var element: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(
            systemWide, Float(point.x), Float(point.y), &element
        )
        if err == .success, let element = element, let window = enclosingWindow(of: element) {
            return window
        }

        guard let info = topWindowInfo(at: point) else { return nil }
        return windowFromTopWindowInfo(info, containing: point)
    }

    func minimizeWindow(at location: CGPoint, activate: Bool) {
        guard let window = windowUnderPoint(location) else { return }
        activateWindowIfNeeded(window, shouldActivate: activate)
        let err = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        if err == .success, isWindowMinimized(window) == true {
            return
        }

        var buttonRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizeButtonAttribute as CFString, &buttonRef) == .success,
           let buttonRef = buttonRef {
            AXUIElementPerformAction((buttonRef as! AXUIElement), kAXPressAction as CFString)
        }
    }

    func closeWindow(at location: CGPoint, activate: Bool) {
        guard let window = windowUnderPoint(location) else { return }
        activateWindowIfNeeded(window, shouldActivate: activate)
        var buttonRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &buttonRef) == .success,
           let buttonRef = buttonRef {
            AXUIElementPerformAction((buttonRef as! AXUIElement), kAXPressAction as CFString)
        }
    }

    func activateWindowUnderPoint(at location: CGPoint) {
        guard let window = windowUnderPoint(location) else { return }
        activateWindow(window)
    }

    func activateWindowIfNeeded(_ window: AXUIElement, shouldActivate: Bool) {
        guard shouldActivate else { return }
        activateWindow(window)
    }

    func activateWindow(_ window: AXUIElement) {
        var pid: pid_t = 0
        if AXUIElementGetPid(window, &pid) == .success, pid != getpid() {
            NSRunningApplication(processIdentifier: pid)?
                .activate(options: [.activateIgnoringOtherApps])

            let app = AXUIElementCreateApplication(pid)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, window)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
    }

    func activateSwitcherWindow(_ window: AXUIElement) {
        if isWindowMinimized(window) == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        activateWindow(window)
    }

    func activateWindowUnderPointIfNeeded(at location: CGPoint, shouldActivate: Bool) {
        guard shouldActivate else { return }
        activateWindowUnderPoint(at: location)
    }

    func windowPosition(_ window: AXUIElement) -> CGPoint? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &valueRef) == .success,
              let valueRef = valueRef else { return nil }
        var point = CGPoint.zero
        if AXValueGetValue(valueRef as! AXValue, .cgPoint, &point) {
            return point
        }
        return nil
    }

    func setWindowPosition(_ window: AXUIElement, _ position: CGPoint) {
        var pos = position
        if let value = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    func windowSize(_ window: AXUIElement) -> CGSize? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &valueRef) == .success,
              let valueRef = valueRef else { return nil }
        var size = CGSize.zero
        if AXValueGetValue(valueRef as! AXValue, .cgSize, &size) {
            return size
        }
        return nil
    }

    func setWindowSize(_ window: AXUIElement, _ size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
    }

    func windowFrame(_ window: AXUIElement) -> CGRect? {
        guard let pos = windowPosition(window), let size = windowSize(window) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    /// Нативный полноэкранный режим (зелёная кнопка / ⌃⌘F). Атрибут `AXFullScreen`
    /// формально приватный, но стабильно поддерживается AppKit-приложениями и
    /// используется Rectangle, Magnet, BetterTouchTool и т.п.
    /// Возвращает `false`, если окно не в fullscreen ИЛИ приложение не поддерживает атрибут.
    func isFullScreen(_ window: AXUIElement) -> Bool {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &valueRef) == .success,
              let valueRef = valueRef else {
            return false
        }
        return CFBooleanGetValue((valueRef as! CFBoolean))
    }

    /// Включает/выключает нативный полноэкранный режим окна.
    /// При `false` macOS сам анимирует выход и возвращает окну прежний «обычный» размер.
    func setFullScreen(_ window: AXUIElement, _ value: Bool) {
        AXUIElementSetAttributeValue(
            window,
            "AXFullScreen" as CFString,
            value ? kCFBooleanTrue : kCFBooleanFalse
        )
    }

    func visibleFrameTopLeft(containing point: CGPoint) -> CGRect? {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return nil }
        let totalHeight = primary.frame.height
        // Точка в координатах сверху-слева → переводим в снизу-слева для сравнения с NSScreen.frame.
        let flipped = CGPoint(x: point.x, y: totalHeight - point.y)
        let screen = screens.first(where: { $0.frame.contains(flipped) }) ?? primary
        let vf = screen.visibleFrame // снизу-слева
        return CGRect(x: vf.origin.x,
                      y: totalHeight - (vf.origin.y + vf.height),
                      width: vf.width, height: vf.height)
    }

    func framesApproxEqual(_ a: CGRect, _ b: CGRect, tol: CGFloat = 3) -> Bool {
        abs(a.origin.x - b.origin.x) < tol && abs(a.origin.y - b.origin.y) < tol &&
        abs(a.size.width - b.size.width) < tol && abs(a.size.height - b.size.height) < tol
    }

    func windowIdentity(_ window: AXUIElement) -> String {
        var pid: pid_t = 0
        _ = AXUIElementGetPid(window, &pid)

        var numberRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &numberRef) == .success,
           let number = numberRef as? NSNumber {
            return "\(pid):\(number.intValue)"
        }

        return "\(pid):\(CFHash(window))"
    }

    private func isPointOverOwnWindow(_ point: CGPoint) -> Bool {
        guard let info = topWindowInfo(at: point) else { return false }
        return info.pid == pid_t(getpid())
    }

    private func isWindowMinimized(_ window: AXUIElement) -> Bool? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &valueRef) == .success,
              let valueRef = valueRef else {
            return nil
        }
        return CFBooleanGetValue((valueRef as! CFBoolean))
    }

    private func isStandardWindow(_ window: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef) == .success,
              (roleRef as? String) == (kAXWindowRole as String) else {
            return false
        }

        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String,
           subrole == (kAXSystemDialogSubrole as String) {
            return false
        }

        if isWindowMinimized(window) == true {
            return true
        }

        guard let frame = windowFrame(window) else { return false }
        return frame.width >= 80 && frame.height >= 40
    }

    private func windowTitle(_ window: AXUIElement) -> String {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else {
            return ""
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func topWindowInfo(at point: CGPoint) -> TopWindowInfo? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else {
            return nil
        }

        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary),
                  bounds.contains(point) else {
                continue
            }

            let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
            let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
            let name = info[kCGWindowName as String] as? String ?? ""
            let number = (info[kCGWindowNumber as String] as? NSNumber)?.intValue ?? -1
            return TopWindowInfo(pid: pid, owner: owner, name: name, number: number, bounds: bounds)
        }

        return nil
    }

    private func windowFromTopWindowInfo(_ info: TopWindowInfo, containing point: CGPoint) -> AXUIElement? {
        guard info.pid != pid_t(getpid()) else { return nil }

        let app = AXUIElementCreateApplication(info.pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }

        if let byNumber = windows.first(where: { axWindowNumber($0) == info.number }) {
            return byNumber
        }

        let containingWindows = windows.filter { window in
            guard let frame = windowFrame(window) else { return false }
            return frame.contains(point)
        }

        if let closest = containingWindows.min(by: { lhs, rhs in
            let lhsFrame = windowFrame(lhs) ?? .zero
            let rhsFrame = windowFrame(rhs) ?? .zero
            return frameDistance(lhsFrame, info.bounds) < frameDistance(rhsFrame, info.bounds)
        }) {
            return closest
        }

        return nil
    }

    private func axWindowNumber(_ window: AXUIElement) -> Int? {
        var numberRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &numberRef) == .success,
              let number = numberRef as? NSNumber else {
            return nil
        }
        return number.intValue
    }

    private func frameDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.origin.x - b.origin.x)
            + abs(a.origin.y - b.origin.y)
            + abs(a.width - b.width)
            + abs(a.height - b.height)
    }

    private func enclosingWindow(of element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        var depth = 0
        while let node = current, depth < 25 {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &roleRef) == .success,
               (roleRef as? String) == (kAXWindowRole as String) {
                return node
            }
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(node, kAXWindowAttribute as CFString, &windowRef) == .success,
               let windowRef = windowRef {
                return (windowRef as! AXUIElement)
            }
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &parentRef) == .success,
               let parentRef = parentRef {
                current = (parentRef as! AXUIElement)
            } else {
                current = nil
            }
            depth += 1
        }
        return nil
    }
}
