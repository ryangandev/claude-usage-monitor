import Foundation

/// What the screens show, worked out from one state so every surface agrees.
struct Usage {
    let s: UsageState

    enum Status { case normal, early, almostFull, full }

    var weekly: Double { s.weekly.estimate }
    var fiveHour: Double { s.fiveHour.estimate }
    var weekStart: Date { s.weekly.start ?? s.now }
    var weekEnd: Date { s.weekly.end ?? s.now }
    var elapsed: Double { min(1, max(0, s.now.timeIntervalSince(weekStart) / weekEnd.timeIntervalSince(weekStart))) }
    var burnPerHour: Double { s.weekly.burnPctPerHour ?? s.burnLastHour / s.weekly.dollarsPerPct }

    /// Dollars that make 1% of the weekly limit, chosen so that this week's spend adds up to the estimate.
    var dollarsPerPct: Double {
        let d = s.weekly.effectiveDollarsPerPct ?? s.weekly.dollarsPerPct
        return d > 0 ? d : 1
    }

    func pct(_ dollars: Double) -> Double { dollars / dollarsPerPct }

    /// When the last hour's pace would use the rest of the week, if that comes before the reset.
    var runsOutAt: Date? {
        guard let eta = s.weekly.etaFull else { return nil }
        return (s.weekly.runsOutEarly ?? (eta < weekEnd)) ? eta : nil
    }

    var status: Status {
        if weekly >= 100 { return .full }
        if weekly >= 80 { return .almostFull }
        if runsOutAt != nil { return .early }
        return .normal
    }

    var fiveHourMatters: Bool { fiveHour >= 70 }

    var hoursLeft: Double? { burnPerHour > 0.01 ? (100 - weekly) / burnPerHour : nil }

    var forecastAtReset: Double? { s.weekly.forecastAtReset }

    var calibrated: Bool { s.weekly.rateSource == "calibrated" }

    /// The kind to count "how many more" in: Opus xhigh when it ran this week, else the costliest kind.
    var referenceKind: UsageState.AgentCounts.Kind? {
        let kinds = s.agentCounts.byKind.filter { ($0.medianCost ?? 0) > 0 }
        return kinds.first { $0.family == "opus" && $0.effort == "xhigh" } ?? kinds.max { ($0.cost ?? 0) < ($1.cost ?? 0) }
    }

    var moreOfReference: Int? {
        guard let k = referenceKind, let m = k.medianCost, m > 0 else { return nil }
        return Int(((100 - weekly) / pct(m)).rounded(.down))
    }

    var running: [UsageState.Agent] { s.agents.filter(\.active).sorted { $0.cost > $1.cost } }

    /// Each session's subagents this week, running ones first, then by quota used.
    var agentsBySession: [String: [UsageState.Agent]] {
        Dictionary(grouping: s.agents.filter { $0.session != nil }, by: { $0.session! })
            .mapValues { $0.sorted { a, b in a.active != b.active ? a.active : a.cost > b.cost } }
    }

    var sessions: [UsageState.Session] {
        (s.allSessions.flatMap { $0.isEmpty ? nil : $0 } ?? s.sessions).sorted { a, b in
            let aa = isActive(a), ba = isActive(b)
            return aa != ba ? aa : a.total > b.total
        }
    }

    func isActive(_ x: UsageState.Session) -> Bool { x.active ?? (s.now.timeIntervalSince(x.last) < 600) }

    struct Project: Identifiable {
        var name: String
        var sessions: [UsageState.Session]
        var total: Double { sessions.reduce(0) { $0 + $1.total } }
        var sub: Double { sessions.reduce(0) { $0 + $1.sub } }
        var agents: Int { sessions.reduce(0) { $0 + $1.agents } }
        var last: Date { sessions.map(\.last).max() ?? .distantPast }
        var id: String { name }
    }

    var projects: [Project] {
        let groups = Dictionary(grouping: sessions, by: \.project)
        return groups.map { Project(name: $0.key, sessions: $0.value) }.sorted { a, b in
            let aa = a.sessions.contains(where: isActive), ba = b.sessions.contains(where: isActive)
            return aa != ba ? aa : a.total > b.total
        }
    }

    var subagentShare: Double { s.week.total > 0 ? s.week.subagent / s.week.total : 0 }

    /// Each of the week's seven days, in percent of the weekly limit.
    var dailyPct: [(start: Date, opus: Double, other: Double, state: String)] {
        s.weekDays.map { ($0.start, pct($0.opus), pct($0.total - $0.opus), $0.state) }
    }

    var weeksWithUse: [UsageState.Week] { s.weeks.filter { $0.total > 0 } }

    /// This week's spend if the week's average pace holds to the reset.
    var forecastSpend: Double? { elapsed > 0.02 ? s.week.total / elapsed : nil }

    var officialAge: TimeInterval? { s.weekly.officialAt.map { s.now.timeIntervalSince($0) } }
}
