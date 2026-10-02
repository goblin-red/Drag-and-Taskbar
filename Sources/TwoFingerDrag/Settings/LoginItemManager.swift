import Foundation
import ServiceManagement

final class LoginItemManager {
    static let shared = LoginItemManager()

    private init() {}

    var statusTitle: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return tr("Enabled", "Включено")
        case .requiresApproval:
            return tr("Needs approval in macOS settings", "Требуется подтверждение в настройках macOS")
        case .notRegistered:
            return tr("Disabled", "Выключено")
        case .notFound:
            return tr("App not found", "Приложение не найдено")
        @unknown default:
            return tr("Unknown", "Неизвестно")
        }
    }

    func syncWithPreference() {
        setEnabled(UserDefaults.standard.bool(forKey: SettingsKey.launchAtLogin))
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status != .notRegistered else { return }
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[TwoFingerDrag] Не удалось изменить запуск при входе: \(error.localizedDescription)")
        }
    }
}
