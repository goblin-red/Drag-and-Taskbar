import Foundation

/// Язык интерфейса: английский по умолчанию, русский по выбору.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case ru

    var id: String { rawValue }

    var title: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        }
    }

    /// Текущий язык из настроек. Читается при каждом обращении, поэтому меняется на лету.
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: SettingsKey.language) ?? "") ?? .en
    }
}

/// Текст на текущем языке интерфейса.
func tr(_ en: String, _ ru: String) -> String {
    AppLanguage.current == .ru ? ru : en
}
