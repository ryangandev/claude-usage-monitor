import AppKit
import Observation

enum Language: String, CaseIterable { case system, zh, en }
enum Appearance: String, CaseIterable { case system, light, dark }
enum Tab: String, CaseIterable { case overview, agents, sessions, weeks }
enum SessionGrouping: String { case session, project }
enum ChartView: String { case cumulative, daily, hourly }

/// Choices the viewer made, kept in UserDefaults so the app opens the way it was left.
@MainActor @Observable
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    var language: Language { didSet { defaults.set(language.rawValue, forKey: "language") } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance"); applyAppearance() } }
    var tab: Tab { didSet { defaults.set(tab.rawValue, forKey: "tab") } }
    var grouping: SessionGrouping { didSet { defaults.set(grouping.rawValue, forKey: "grouping") } }
    var expandedProjects: Set<String> { didSet { defaults.set(Array(expandedProjects), forKey: "expandedProjects") } }
    var chart: ChartView { didSet { defaults.set(chart.rawValue, forKey: "chart") } }
    var iconOnly: Bool { didSet { defaults.set(iconOnly, forKey: "iconOnly") } }

    private init() {
        language = Language(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        tab = Tab(rawValue: defaults.string(forKey: "tab") ?? "") ?? .overview
        grouping = SessionGrouping(rawValue: defaults.string(forKey: "grouping") ?? "") ?? .session
        expandedProjects = Set(defaults.stringArray(forKey: "expandedProjects") ?? [])
        chart = ChartView(rawValue: defaults.string(forKey: "chart") ?? "") ?? .cumulative
        iconOnly = defaults.bool(forKey: "iconOnly")
    }

    /// Chinese when chosen, or when the system's first preferred language is Chinese.
    var isChinese: Bool {
        switch language {
        case .zh: return true
        case .en: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // Which alerts already went out, per weekly window, so each fires once a week.
    func alertSent(_ key: String, week: Date) -> Bool {
        (defaults.dictionary(forKey: "alerts")?[weekKey(week)] as? [String])?.contains(key) ?? false
    }

    func markAlertSent(_ key: String, week: Date) {
        var all = defaults.dictionary(forKey: "alerts") ?? [:]
        let k = weekKey(week)
        all = all.filter { $0.key == k }  // earlier weeks are no longer needed
        all[k] = ((all[k] as? [String]) ?? []) + [key]
        defaults.set(all, forKey: "alerts")
    }

    private func weekKey(_ d: Date) -> String { String(Int(d.timeIntervalSince1970)) }
}
