import Foundation

/// The same text in Chinese and English; the viewer's language picks one.
@MainActor func L(_ zh: String, _ en: String) -> String {
    Settings.shared.isChinese ? zh : en
}

@MainActor enum Fmt {
    private static var cache: [String: DateFormatter] = [:]

    private static func formatter(_ zh: String, _ en: String) -> DateFormatter {
        let chinese = Settings.shared.isChinese
        let key = (chinese ? "zh|" : "en|") + (chinese ? zh : en)
        if let f = cache[key] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: chinese ? "zh_CN" : "en_US")
        f.dateFormat = chinese ? zh : en
        cache[key] = f
        return f
    }

    /// "周一 20:04" or "Mon 8:04 PM".
    static func dayTime(_ d: Date) -> String { formatter("EEE HH:mm", "EEE h:mm a").string(from: d) }
    /// "20:04" or "8:04 PM".
    static func time(_ d: Date) -> String { formatter("HH:mm", "h:mm a").string(from: d) }
    static func clock(_ d: Date) -> String { formatter("HH:mm:ss", "h:mm:ss a").string(from: d) }
    /// "10/14" in both languages.
    static func monthDay(_ d: Date) -> String { formatter("M/d", "M/d").string(from: d) }
    /// "周三" or "Wed".
    static func weekday(_ d: Date) -> String { formatter("EEE", "EEE").string(from: d) }

    /// "1 分钟前" or "1 min ago", then the weekday and time once it is a day old.
    static func ago(_ d: Date, now: Date) -> String {
        let s = max(0, now.timeIntervalSince(d))
        if s < 60 { return L("刚刚", "just now") }
        if s < 3600 { let m = Int(s / 60); return L("\(m) 分钟前", "\(m) min ago") }
        if s < 86400 { let h = Int(s / 3600); return L("\(h) 小时前", "\(h) h ago") }
        return dayTime(d)
    }

    /// How old something is: "35 分钟" or "35 min", then hours, then days to one decimal.
    static func age(_ s: TimeInterval) -> String {
        if s < 3600 { let m = max(1, Int(s / 60)); return L("\(m) 分钟", "\(m) min") }
        if s < 86400 { let h = Int(s / 3600); return L("\(h) 小时", h == 1 ? "1 hour" : "\(h) hours") }
        let d = String(format: "%.1f", s / 86400)
        return L("\(d) 天", "\(d) days")
    }

    /// "68 分钟" or "68 min", hours past two hours.
    static func duration(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        if m < 120 { return L("\(m) 分钟", "\(m) min") }
        return L("\(m / 60) 小时", "\(m / 60) h")
    }

    static func pct(_ v: Double, digits: Int = 0) -> String {
        if v > 0 && v < 0.1 && digits > 0 { return "<0.1%" }
        return String(format: "%.\(digits)f%%", v)
    }

    static func usd(_ v: Double, cents: Bool = false) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = cents ? 2 : 0
        f.minimumFractionDigits = cents ? 2 : 0
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }

    static func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : "\(n / 1000)k"
    }

    static func modelName(_ family: String) -> String {
        switch family {
        case "opus": return "Opus"
        case "sonnet": return "Sonnet"
        case "haiku": return "Haiku"
        case "fable": return "Fable"
        default: return L("其他", "Other")
        }
    }

    static func family(ofModel model: String) -> String {
        for f in ["opus", "sonnet", "haiku", "fable"] where model.contains(f) { return f }
        return "other"
    }

    /// "Opus · xhigh", with an unset effort named the same way in both places it shows.
    static func kind(family: String, effort: String) -> String {
        modelName(family) + " · " + (effort == "n/a" ? L("未标注", "unset") : effort)
    }
}
