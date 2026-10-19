import Foundation

/// The JSON that monitor.py serves at /api/state. Fields an older server leaves out are optional.
struct UsageState: Decodable {
    var apiVersion: Int?
    var now: Date
    var tier: String?
    var weekly: Meter
    var fiveHour: Meter
    var burnLastHour: Double
    var today: Double
    var week: WeekSummary
    var hours: [Hour]
    var agents: [Agent]
    var sessions: [Session]
    var allSessions: [Session]?
    var weekDays: [Day]
    var agentCounts: AgentCounts
    var weekElapsedDays: Double
    var dailyBudget: Double
    var weeks: [Week]
    var weekCurve: [CurvePoint]?
    var lastCall: Date?
    var resources: Resources?

    /// What this Mac's processes cost: each running session with the subagents working in their worktrees and the commands it runs.
    struct Resources: Decodable {
        var sampledAt: Date
        var cores: Int
        var cpuPct: Double
        var memTotal: Double?
        var memUsed: Double?
        var app: Usage
        var sessions: [SessionProcess]

        struct Usage: Decodable {
            var cpu: Double
            var rss: Double
            var procs: Int
        }

        struct SessionProcess: Decodable, Identifiable {
            var session: String?
            var folder: String?
            var pid: Int
            var title: String?
            var project: String?
            var cpu: Double
            var rss: Double
            var selfCpu: Double
            var selfRss: Double
            var toolsCpu: Double
            var toolsRss: Double
            var tools: Int
            var agents: [AgentProcess]
            var id: Int { pid }
        }

        struct AgentProcess: Decodable, Identifiable {
            var agent: String
            var description: String?
            var cpu: Double
            var rss: Double
            var procs: Int
            var id: String { agent }
        }
    }

    struct Meter: Decodable {
        var official: Double?
        var officialAt: Date?
        var estimate: Double
        var start: Date?
        var end: Date?
        var dollarsPerPct: Double
        var rateSource: String
        var etaFull: Date?
        var runsOutEarly: Bool?
        var burnPctPerHour: Double?
        var forecastAtReset: Double?
        var effectiveDollarsPerPct: Double?
    }

    struct WeekSummary: Decodable {
        var total: Double
        var calls: Int
        var subagent: Double
    }

    struct Hour: Decodable {
        var hour: Date
        var opus: Double
        var sonnet: Double
        var haiku: Double
        var fable: Double
        var other: Double
        var total: Double { opus + sonnet + haiku + fable + other }
    }

    struct Agent: Decodable, Identifiable {
        var agent: String
        var cost: Double
        var calls: Int
        var first: Date
        var last: Date
        var session: String?
        var model: String
        var context: Int
        var description: String?
        var effort: String
        var sessionTitle: String
        var active: Bool
        var id: String { agent }
        @MainActor var label: String { description ?? L("（无描述）", "(no description)") }
    }

    struct Session: Decodable, Identifiable {
        var session: String?
        var title: String
        var project: String
        var main: Double
        var sub: Double
        var total: Double
        var agents: Int
        var running: Int?
        var last: Date
        var active: Bool?
        var id: String { session ?? title }
    }

    struct Day: Decodable {
        var start: Date
        var end: Date
        var total: Double
        var opus: Double
        var state: String
    }

    struct AgentCounts: Decodable {
        var total: Int
        var active: Int
        var perDay: [Int]
        var byKind: [Kind]

        struct Kind: Decodable {
            var family: String
            var effort: String
            var count: Int
            var cost: Double?
            var medianCost: Double?
        }
    }

    struct Week: Decodable {
        var start: Date
        var end: Date
        var total: Double
        var subagent: Double
        var opus: Double
        var officialPeak: Double?
        var officialPeakTrusted: Bool?
    }

    struct CurvePoint: Decodable {
        var t: Date
        var pct: Double
    }

    static func decode(_ data: Data) throws -> UsageState {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            if let date = parseDate(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "not a date: \(s)"))
        }
        return try decoder.decode(UsageState.self, from: data)
    }

    private static let plain = ISO8601DateFormatter()
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// The server writes ISO 8601 in UTC, with no fraction, milliseconds or microseconds;
    /// the formatter reads at most milliseconds, so longer fractions are cut to three digits.
    static func parseDate(_ s: String) -> Date? {
        guard let dot = s.firstIndex(of: ".") else { return plain.date(from: s) }
        let digits = s[s.index(after: dot)...].prefix { $0.isNumber }
        let rest = s[s.index(dot, offsetBy: digits.count + 1)...]
        let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        return fractional.date(from: String(s[..<dot]) + "." + millis + String(rest))
    }
}
