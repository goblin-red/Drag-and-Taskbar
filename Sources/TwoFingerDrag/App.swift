import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DragController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ensureSingleInstance() else {
            NSApp.terminate(nil)
            return
        }

        // Приложение-агент: без иконки в Dock, только в трее.
        NSApp.setActivationPolicy(.accessory)
        controller.start()
        LoginItemManager.shared.syncWithPreference()
        SettingsConfig.shared.startAutosave()
    }

    private func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.local.twofingerdrag"
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let alreadyRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != currentPID && !$0.isTerminated }

        if alreadyRunning {
            NSLog("[TwoFingerDrag] Уже запущен другой экземпляр, новый процесс завершается.")
            return false
        }
        return true
    }
}

@main
struct TwoFingerDragApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(tr("Window dragging", "Перетаскивание окон"), systemImage: "hand.draw") {
            MenuView()
                .padding(14)
                .frame(width: 320)
        }
        .menuBarExtraStyle(.window)

        Window("GOBL(in) Drag & Taskbar", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}
