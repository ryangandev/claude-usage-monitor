import XCTest
@testable import ClaudeUsage

final class UsageTests: XCTestCase {
    func testDatesWithMicrosecondsMillisecondsOrNoFractionAllParse() {
        let a = UsageState.parseDate("2026-10-19T01:59:43.483181Z")
        let b = UsageState.parseDate("2026-10-17T06:11:45.340000Z")
        let c = UsageState.parseDate("2026-10-14T15:00:00Z")
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertEqual(c?.timeIntervalSince1970, 1_791_990_000)
        XCTAssertEqual(a!.timeIntervalSince1970, 1_792_375_183.483, accuracy: 0.001)
    }

    /// The forecast, not the amount used, decides the status, and shares use the dollars that add up to the estimate.
    func testAStateThatRunsOutBeforeTheResetIsEarly() throws {
        let u = Usage(s: try UsageState.decode(Data(Self.state.utf8)))
        XCTAssertEqual(u.status, .early)
        XCTAssertEqual(u.runsOutAt, UsageState.parseDate("2026-10-20T03:04:45Z"))
        XCTAssertEqual(u.pct(24.8), 1, accuracy: 0.0001)
        XCTAssertEqual(u.hoursLeft!, 60.4 / 2.4, accuracy: 0.001)
        XCTAssertEqual(u.referenceKind?.effort, "xhigh")
        XCTAssertEqual(u.moreOfReference, Int(60.4 / (4.96 / 24.8)))
        // The active session comes first even though it spent less.
        XCTAssertEqual(u.sessions.map(\.title), ["b", "a"])
        XCTAssertEqual(u.projects.map(\.name), ["p2", "p1"])
    }

    func testAStateFromAnOlderServerStillDecodes() throws {
        var old = Self.state
        for key in ["\"api_version\": 2,", "\"runs_out_early\": true,", "\"all_sessions\": [],", "\"week_curve\": [],"] {
            old = old.replacingOccurrences(of: key, with: "")
        }
        let u = Usage(s: try UsageState.decode(Data(old.utf8)))
        XCTAssertEqual(u.status, .early)
    }

    static let state = """
    {"api_version": 2, "now": "2026-10-19T01:29:00Z", "tier": "default_claude_max_20x",
     "weekly": {"official": 26, "official_at": "2026-10-17T06:11:45.340000Z", "estimate": 39.6, "start": "2026-10-14T15:00:00Z",
                "end": "2026-10-21T15:00:00Z", "dollars_per_pct": 23.5, "rate_source": "fallback", "eta_full": "2026-10-20T03:04:45Z",
                "runs_out_early": true, "burn_pct_per_hour": 2.4, "forecast_at_reset": 62.4, "effective_dollars_per_pct": 24.8},
     "five_hour": {"official": null, "official_at": null, "estimate": 11.1, "start": "2026-10-19T00:12:43Z", "end": "2026-10-19T05:12:43Z",
                   "dollars_per_pct": 6.6, "rate_source": "fallback", "eta_full": null},
     "burn_last_hour": 55.45, "today": 273.15, "week": {"total": 982.0, "calls": 15000, "subagent": 690.0},
     "hours": [], "agents": [], "sessions": [],
     "all_sessions": [],
     "week_days": [], "agent_counts": {"total": 2, "active": 0, "per_day": [2, 0, 0, 0, 0, 0, 0],
        "by_kind": [{"family": "sonnet", "effort": "high", "count": 1, "cost": 300, "median_cost": 3.0},
                    {"family": "opus", "effort": "xhigh", "count": 1, "cost": 200, "median_cost": 4.96}]},
     "week_elapsed_days": 4.44, "daily_budget": 335.71, "weeks": [], "week_curve": [], "last_call": "2026-10-19T01:28:55Z"}
    """.replacingOccurrences(of: "\"sessions\": []", with: """
    "sessions": [{"session": "s1", "title": "a", "project": "p1", "main": 100, "sub": 500, "total": 600, "agents": 3, "last": "2026-10-18T23:00:00Z", "active": false},
                 {"session": "s2", "title": "b", "project": "p2", "main": 10, "sub": 0, "total": 10, "agents": 0, "last": "2026-10-19T01:28:00Z", "active": true}]
    """)
}
