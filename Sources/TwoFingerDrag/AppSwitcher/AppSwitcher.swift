import AppKit
import SwiftUI

struct AppSwitchItem: Identifiable {
    enum Target {
        case application(NSRunningApplication)
        case window(AXUIElement)
    }

    let id: String
    let pid: pid_t
    let app: NSRunningApplication
    let name: String
    let detail: String?
    let icon: NSImage
    let target: Target
    let isMinimized: Bool
}

final class AppSwitcherController {
    static let shared = AppSwitcherController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AppSwitcherOverlayView>?
    private var items: [AppSwitchItem] = []
    private var selectedIndex = 0
    private var hoverIndex: Int?
    private var initialActivePID: pid_t?
    private var recentPIDs: [pid_t] = []
    private var activationObserver: NSObjectProtocol?
    private var isShowing = false

    /// Публичный флаг: видна ли сейчас панель свитчера приложений.
    /// Нужен другим частям кода (например, `DragController`), чтобы подавить
    /// свои жесты, пока пользователь выбирает приложение.
    var isVisible: Bool { isShowing }

    private init() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.rememberActivated(pid: app.processIdentifier)
        }

        if let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            rememberActivated(pid: frontPID)
        }
    }

    func advance() {
        if isShowing {
            guard !items.isEmpty else { return }
            selectedIndex = (selectedIndex + 1) % items.count
        } else {
            initialActivePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if let initialActivePID = initialActivePID {
                rememberActivated(pid: initialActivePID)
            }
            items = switcherItems()
            guard !items.isEmpty else { return }
            selectedIndex = initialSelectionIndex(items)
            hoverIndex = nil
            isShowing = true
        }
        showPanel()
    }

    func finish() {
        guard isShowing else { return }
        let selected = items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
        let previousPID = initialActivePID
        hidePanel()
        activate(selected, previousPID: previousPID)
    }

    func cancel() {
        hidePanel()
    }

    func click(atTopLeftLocation location: CGPoint) -> Bool {
        guard isShowing, let panel = panel else { return false }

        let bounds = topLeftPanelBounds() ?? topLeftBounds(fromAppKitFrame: panel.frame)
        guard bounds.contains(location) else { return false }

        let localX = location.x - bounds.minX
        let localYFromTop = location.y - bounds.minY
        guard let index = itemIndexAt(localX: localX, localYFromTop: localYFromTop) else {
            return true
        }

        activateItem(at: index)
        return true
    }

    func updateHover(atTopLeftLocation location: CGPoint) {
        guard isShowing, let panel = panel else { return }

        let bounds = topLeftPanelBounds() ?? topLeftBounds(fromAppKitFrame: panel.frame)
        let newHover: Int?
        if bounds.contains(location) {
            let localX = location.x - bounds.minX
            let localYFromTop = location.y - bounds.minY
            newHover = itemIndexAt(localX: localX, localYFromTop: localYFromTop)
        } else {
            newHover = nil
        }

        guard hoverIndex != newHover else { return }
        hoverIndex = newHover
        showPanel()
    }

    private func showPanel() {
        let metrics = panelMetrics(for: items.count)
        let view = AppSwitcherOverlayView(
            items: items,
            selectedIndex: selectedIndex,
            hoverIndex: hoverIndex,
            initialActivePID: initialActivePID,
            columns: metrics.columns,
            width: metrics.width,
            height: metrics.height,
            onClick: { [weak self] index in
                self?.activateItem(at: index)
            }
        )

        if let panel = panel, let hostingView = hostingView {
            hostingView.rootView = view
            center(panel, size: NSSize(width: metrics.width, height: metrics.height))
            panel.orderFrontRegardless()
            return
        }

        let rect = centeredRect(size: NSSize(width: metrics.width, height: metrics.height))
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = false

        let hostingView = AppSwitcherHostingView(rootView: view)
        hostingView.onMouseDown = { [weak self] point in
            _ = self?.click(atTopLeftLocation: point)
        }
        hostingView.frame = NSRect(origin: .zero, size: rect.size)
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
        panel.orderFrontRegardless()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        isShowing = false
        items = []
        selectedIndex = 0
        hoverIndex = nil
        initialActivePID = nil
    }

    private func activateItem(at index: Int) {
        guard isShowing, items.indices.contains(index) else { return }
        let item = items[index]
        let previousPID = initialActivePID
        hidePanel()
        activate(item, previousPID: previousPID)
    }

    private func activate(_ item: AppSwitchItem?, previousPID: pid_t?) {
        guard let item = item else { return }
        rememberSwitch(to: item.pid, previousPID: previousPID)
        switch item.target {
        case .application(let app):
            app.activate(options: [.activateIgnoringOtherApps])
        case .window(let window):
            WindowAccess().activateSwitcherWindow(window)
        }
    }

    private func switcherItems() -> [AppSwitchItem] {
        let rawMode = UserDefaults.standard.string(forKey: SettingsKey.appSwitcherMode) ?? AppSwitcherMode.compact.rawValue
        let mode = AppSwitcherMode(rawValue: rawMode) ?? .compact
        let items: [AppSwitchItem]
        switch mode {
        case .compact:
            items = visibleApplications()
        case .windows:
            let windows = windowItems()
            items = windows.isEmpty ? visibleApplications() : windows
        }
        return orderedByRecent(items)
    }

    private func visibleApplications() -> [AppSwitchItem] {
        var result: [AppSwitchItem] = []
        for item in WindowAccess.visibleApplicationsForSwitcher() {
            let icon = item.app.icon ?? NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 64, height: 64))
            result.append(AppSwitchItem(
                id: "app:\(item.pid)",
                pid: item.pid,
                app: item.app,
                name: item.name,
                detail: nil,
                icon: icon,
                target: .application(item.app),
                isMinimized: false
            ))
        }
        return result
    }

    private func windowItems() -> [AppSwitchItem] {
        WindowAccess.windowsForSwitcher().map { item in
            let icon = item.app.icon ?? NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 64, height: 64))
            return AppSwitchItem(
                id: "window:\(item.identity)",
                pid: item.app.processIdentifier,
                app: item.app,
                name: item.windowTitle,
                detail: item.appName,
                icon: icon,
                target: .window(item.window),
                isMinimized: item.isMinimized
            )
        }
    }

    private func initialSelectionIndex(_ items: [AppSwitchItem]) -> Int {
        guard let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return 0
        }

        if let previousPID = recentPIDs.first(where: { $0 != frontPID }),
           let previousIndex = items.firstIndex(where: { $0.pid == previousPID }) {
            return previousIndex
        }

        guard let current = items.firstIndex(where: { $0.pid == frontPID }) else {
            return 0
        }
        return items.count > 1 ? (current + 1) % items.count : current
    }

    private func orderedByRecent(_ source: [AppSwitchItem]) -> [AppSwitchItem] {
        var used = Set<String>()
        var ordered: [AppSwitchItem] = []

        for pid in recentPIDs {
            for item in source where item.pid == pid && !used.contains(item.id) {
                ordered.append(item)
                used.insert(item.id)
            }
        }

        for item in source where !used.contains(item.id) {
            ordered.append(item)
        }

        return ordered
    }

    private func rememberActivated(pid: pid_t) {
        guard pid != pid_t(getpid()) else { return }
        recentPIDs.removeAll { $0 == pid }
        recentPIDs.insert(pid, at: 0)
        trimRecentPIDs()
    }

    private func rememberSwitch(to targetPID: pid_t, previousPID: pid_t?) {
        guard targetPID != pid_t(getpid()) else { return }
        recentPIDs.removeAll { $0 == targetPID || $0 == previousPID }
        recentPIDs.insert(targetPID, at: 0)
        if let previousPID = previousPID, previousPID != targetPID, previousPID != pid_t(getpid()) {
            recentPIDs.insert(previousPID, at: min(1, recentPIDs.count))
        }
        trimRecentPIDs()
    }

    private func trimRecentPIDs() {
        if recentPIDs.count > 30 {
            recentPIDs.removeLast(recentPIDs.count - 30)
        }
    }

    private func panelMetrics(for count: Int) -> (columns: Int, width: CGFloat, height: CGFloat) {
        let columns = max(1, min(5, Int(ceil(sqrt(Double(max(count, 1)))))))
        let rows = Int(ceil(Double(max(count, 1)) / Double(columns)))
        let cell: CGFloat = 86
        let gap: CGFloat = 12
        let padding: CGFloat = 22
        let width = CGFloat(columns) * cell + CGFloat(max(columns - 1, 0)) * gap + padding * 2
        let height = CGFloat(rows) * cell + CGFloat(max(rows - 1, 0)) * gap + padding * 2
        return (columns, width, height)
    }

    private func centeredRect(size: NSSize) -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        return NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func center(_ panel: NSPanel, size: NSSize) {
        panel.setFrame(centeredRect(size: size), display: true)
        hostingView?.frame = NSRect(origin: .zero, size: size)
    }

    private func topLeftPanelBounds() -> CGRect? {
        let expectedSize = panel?.frame.size ?? .zero
        return WindowAccess.topLeftOwnWindowBounds(expectedSize: expectedSize)
    }

    private func topLeftBounds(fromAppKitFrame frame: CGRect) -> CGRect {
        let totalHeight = NSScreen.screens.first?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
        return CGRect(x: frame.minX,
                      y: totalHeight - frame.maxY,
                      width: frame.width,
                      height: frame.height)
    }

    private func itemIndexAt(localX: CGFloat, localYFromTop: CGFloat) -> Int? {
        let metrics = panelMetrics(for: items.count)
        let cell: CGFloat = 86
        let gap: CGFloat = 12
        let padding: CGFloat = 22
        let x = localX - padding
        let y = localYFromTop - padding
        guard x >= 0, y >= 0 else { return nil }

        let pitch = cell + gap
        let column = Int(x / pitch)
        let row = Int(y / pitch)
        guard column >= 0, column < metrics.columns else { return nil }
        guard x - CGFloat(column) * pitch <= cell,
              y - CGFloat(row) * pitch <= cell else { return nil }

        let index = row * metrics.columns + column
        return items.indices.contains(index) ? index : nil
    }
}

struct AppSwitcherOverlayView: View {
    let items: [AppSwitchItem]
    let selectedIndex: Int
    let hoverIndex: Int?
    let initialActivePID: pid_t?
    let columns: Int
    let width: CGFloat
    let height: CGFloat
    let onClick: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(86), spacing: 12), count: columns), spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isSelected = index == selectedIndex
                let isHovered = index == hoverIndex
                let isInitialActive = initialActivePID == item.pid
                VStack(spacing: 7) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(nsImage: item.icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                        if item.isMinimized {
                            Circle()
                                .fill(Color.secondary.opacity(0.92))
                                .frame(width: 11, height: 11)
                                .overlay(Circle().stroke(Color.white.opacity(0.75), lineWidth: 1))
                        }
                    }
                    Text(item.name)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(.primary)
                        .frame(width: 72)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundColor(.secondary)
                            .frame(width: 72)
                    }
                }
                .frame(width: 86, height: 86)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.24) : (isHovered ? Color.white.opacity(0.10) : Color.clear))
                )
                .overlay(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        if isInitialActive {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.green.opacity(0.90), lineWidth: 2)
                                .padding(1)
                        }
                        if isHovered {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.80), lineWidth: 2)
                                .padding(3)
                        }
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.90), lineWidth: 2)
                                .padding(5)
                        }
                    }
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture {
                    onClick(index)
                }
            }
        }
        .padding(22)
        .frame(width: width, height: height)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 24, x: 0, y: 12)
    }
}

final class AppSwitcherHostingView<Content: View>: NSHostingView<Content> {
    var onMouseDown: ((CGPoint) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let totalHeight = NSScreen.screens.first?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
        let appKitPoint = NSEvent.mouseLocation
        onMouseDown?(CGPoint(x: appKitPoint.x, y: totalHeight - appKitPoint.y))
        super.mouseDown(with: event)
    }
}
