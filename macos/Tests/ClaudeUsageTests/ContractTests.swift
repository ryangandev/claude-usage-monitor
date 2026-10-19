import XCTest
@testable import ClaudeUsage

/// Decodes the state monitor.py serves, from tests/fixtures/state.json, which a Python test keeps equal to build_state's output.
/// A field renamed or retyped on either side fails here instead of in the running app.
final class ContractTests: XCTestCase {
    static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("tests/fixtures/state.json")

    func testTheServersStateDecodesWithEveryFieldTheAppUses() throws {
        let s = try UsageState.decode(Data(contentsOf: Self.fixture))
        XCTAssertEqual(s.apiVersion, 3)
        // Optional only so an older server still decodes; the current one sends them all.
        XCTAssertNotNil(s.weekly.runsOutEarly)
        XCTAssertNotNil(s.weekly.burnPctPerHour)
        XCTAssertNotNil(s.weekly.forecastAtReset)
        XCTAssertNotNil(s.weekly.effectiveDollarsPerPct)
        XCTAssertFalse(s.allSessions?.isEmpty ?? true)
        XCTAssertFalse(s.weekCurve?.isEmpty ?? true)
        XCTAssertTrue(s.allSessions!.allSatisfy { $0.active != nil && $0.running != nil })
        XCTAssertTrue(s.agentCounts.byKind.allSatisfy { $0.cost != nil && $0.medianCost != nil })
        XCTAssertTrue(s.weeks.allSatisfy { $0.officialPeakTrusted != nil })
        // A subagent without a meta file has no description, and the app shows its own fallback.
        XCTAssertEqual(s.agents.filter { $0.description == nil }.map(\.agent), ["a3"])

        // What the process sampler saw: the session with its worktree subagent, a terminal session without an id, the app.
        let r = try XCTUnwrap(s.resources)
        XCTAssertEqual(r.cores, 8)
        XCTAssertEqual(r.sessions.map(\.title), ["Refactor billing service", "notes"])
        XCTAssertEqual(r.sessions[0].agents.map(\.description), ["Implement search filters"])
        XCTAssertEqual(r.sessions[0].agents[0].cpu, 74.7)
        XCTAssertNil(r.sessions[1].session)
        XCTAssertEqual(r.app.cpu, 35.7)
    }

    func testTheScreensReadTheFixtureAsTheServerMeantIt() throws {
        let u = Usage(s: try UsageState.decode(Data(contentsOf: Self.fixture)))
        XCTAssertEqual(u.status, .early)
        XCTAssertNotNil(u.runsOutAt)
        XCTAssertEqual(u.weekly, 31.1, accuracy: 0.001)
        // Shares at the effective rate add the week back up to the estimate.
        XCTAssertEqual(u.pct(u.s.week.total), u.weekly, accuracy: 0.1)
        XCTAssertEqual(u.s.weekCurve?.last?.pct ?? 0, u.weekly, accuracy: 0.1)
        XCTAssertEqual(u.running.map(\.description), ["Implement search filters"])
        XCTAssertEqual(u.referenceKind?.family, "opus")
        XCTAssertEqual(u.sessions.map(\.title), ["Fix flaky checkout tests", "Refactor billing service", "Draft API docs"])
        XCTAssertEqual(u.projects.map(\.name), ["acme-api", "acme-web"])
        XCTAssertEqual(u.dailyPct.count, 7)
        XCTAssertEqual(u.dailyPct.filter { $0.state == "current" }.count, 1)
    }
}
