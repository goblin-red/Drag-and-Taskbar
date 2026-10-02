import AppKit
import SwiftUI

enum SwipeIndicatorDirection {
    case up
    case down
    case left
    case right
}

final class SwipeIndicatorOverlay {
    static let shared = SwipeIndicatorOverlay()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<SwipeIndicatorView>?
    private var hideWorkItem: DispatchWorkItem?

    private let size: CGFloat = 24
    private let cursorSideOffset: CGFloat = 28
    private let maxOffset: CGFloat = 180

    private init() {}

    func update(cursorTopLeft: CGPoint, direction: SwipeIndicatorDirection, strength: CGFloat, gain: CGFloat) {
        assert(Thread.isMainThread)

        hideWorkItem?.cancel()

        let clampedStrength = min(abs(strength) * max(gain, 0.1), maxOffset)
        let topLeftPoint = indicatorTopLeftPoint(
            cursorTopLeft: cursorTopLeft,
            direction: direction,
            strength: clampedStrength
        )
        let frame = appKitFrame(forTopLeftPoint: topLeftPoint, size: size)

        show(view: SwipeIndicatorView(direction: direction), frame: frame)
    }

    func updateResize(cursorTopLeft: CGPoint, vector: CGVector, gain: CGFloat) {
        assert(Thread.isMainThread)

        let length = max(1, hypot(vector.dx, vector.dy))
        let clampedStrength = min(length * max(gain, 0.1), maxOffset)
        let baseX = vector.dx < -0.1
            ? cursorTopLeft.x - cursorSideOffset - size
            : cursorTopLeft.x + cursorSideOffset
        let topLeftPoint = CGPoint(
            x: baseX + vector.dx / length * clampedStrength,
            y: cursorTopLeft.y + vector.dy / length * clampedStrength - size / 2
        )
        let frame = appKitFrame(forTopLeftPoint: topLeftPoint, size: size)

        show(view: SwipeIndicatorView(direction: nil), frame: frame)
    }

    private func show(view: SwipeIndicatorView, frame: NSRect) {
        hideWorkItem?.cancel()

        if let panel = panel, let hostingView = hostingView {
            hostingView.rootView = view
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        } else {
            let panel = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            panel.ignoresMouseEvents = true

            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(origin: .zero, size: frame.size)
            panel.contentView = hostingView

            self.panel = panel
            self.hostingView = hostingView
            panel.orderFrontRegardless()
        }

        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    func hide() {
        assert(Thread.isMainThread)
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel?.orderOut(nil)
    }

    private func appKitFrame(forTopLeftPoint point: CGPoint, size: CGFloat) -> NSRect {
        let screen = screen(containingTopLeftPoint: point)
        let screenMaxY = screen.frame.maxY
        return NSRect(
            x: point.x,
            y: screenMaxY - point.y - size,
            width: size,
            height: size
        )
    }

    private func screen(containingTopLeftPoint point: CGPoint) -> NSScreen {
        let fallback = NSScreen.main ?? NSScreen.screens[0]
        let totalHeight = NSScreen.screens.first?.frame.height ?? fallback.frame.height
        return NSScreen.screens.first { screen in
            let topLeftFrame = CGRect(
                x: screen.frame.minX,
                y: totalHeight - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
            return topLeftFrame.contains(point)
        } ?? fallback
    }

    private func indicatorTopLeftPoint(
        cursorTopLeft: CGPoint,
        direction: SwipeIndicatorDirection,
        strength: CGFloat
    ) -> CGPoint {
        switch direction {
        case .up:
            return CGPoint(
                x: cursorTopLeft.x + cursorSideOffset,
                y: cursorTopLeft.y - strength - size / 2
            )
        case .down:
            return CGPoint(
                x: cursorTopLeft.x + cursorSideOffset,
                y: cursorTopLeft.y + strength - size / 2
            )
        case .left:
            return CGPoint(
                x: cursorTopLeft.x - cursorSideOffset - size - strength,
                y: cursorTopLeft.y - size / 2
            )
        case .right:
            return CGPoint(
                x: cursorTopLeft.x + cursorSideOffset + strength,
                y: cursorTopLeft.y - size / 2
            )
        }
    }
}

private struct SwipeIndicatorView: View {
    let direction: SwipeIndicatorDirection?

    var body: some View {
        Circle()
            .fill(fillColor)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.92), lineWidth: 2)
            )
            .shadow(color: shadowColor, radius: 8, x: 0, y: 0)
            .padding(3)
            .frame(width: 24, height: 24)
    }

    private var fillColor: Color {
        switch direction {
        case .some(.up):
            return Color(red: 1.0, green: 0.18, blue: 0.15, opacity: 0.92)
        case .some(.down):
            return Color(red: 0.16, green: 0.86, blue: 0.32, opacity: 0.92)
        case .some(.left):
            return Color(red: 1.0, green: 0.62, blue: 0.12, opacity: 0.92)
        case .some(.right):
            return Color(red: 0.20, green: 0.55, blue: 1.0, opacity: 0.92)
        case .none:
            return Color(red: 0.68, green: 0.36, blue: 1.0, opacity: 0.92)
        }
    }

    private var shadowColor: Color {
        switch direction {
        case .some(.up):
            return Color.red.opacity(0.55)
        case .some(.down):
            return Color.green.opacity(0.50)
        case .some(.left):
            return Color.orange.opacity(0.52)
        case .some(.right):
            return Color.blue.opacity(0.50)
        case .none:
            return Color.purple.opacity(0.55)
        }
    }
}
