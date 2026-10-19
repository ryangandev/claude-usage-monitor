import json
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import monitor  # noqa: E402

T0 = datetime(2026, 10, 14, 15, 0, tzinfo=timezone.utc)


def assistant(msg_id, req_id, ts, out=100, model="claude-opus-5-5"):
    return json.dumps({
        "type": "assistant", "requestId": req_id, "timestamp": ts, "sessionId": "s1",
        "message": {"id": msg_id, "model": model, "usage": {
            "input_tokens": 1, "output_tokens": out, "cache_read_input_tokens": 1000,
            "cache_creation": {"ephemeral_5m_input_tokens": 10, "ephemeral_1h_input_tokens": 0}}},
    }) + "\n"


class ScanTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.projects = Path(self.tmp.name) / "projects"
        (self.projects / "-Users-x-proj").mkdir(parents=True)
        self.file = self.projects / "-Users-x-proj" / "s1.jsonl"
        self.cfg = monitor.load_config()
        self.store = monitor.Store(":memory:")

    def tearDown(self):
        self.tmp.cleanup()

    def count(self):
        return self.store.db.execute("SELECT count(*), sum(out) FROM calls").fetchone()

    def test_repeated_lines_of_one_call_count_once_with_the_last_usage(self):
        self.file.write_text(assistant("m1", "r1", "2026-10-14T15:00:00Z", out=5) + assistant("m1", "r1", "2026-10-14T15:00:00Z", out=50))
        monitor.scan_once(self.store, self.cfg, self.projects)
        self.assertEqual(self.count(), (1, 50))

    def test_a_partly_written_line_is_read_on_the_next_scan(self):
        line = assistant("m1", "r1", "2026-10-14T15:00:00Z")
        self.file.write_text(line[:40])
        monitor.scan_once(self.store, self.cfg, self.projects)
        self.assertEqual(self.count()[0], 0)
        self.file.write_text(line)
        monitor.scan_once(self.store, self.cfg, self.projects)
        self.assertEqual(self.count()[0], 1)

    def test_calls_survive_when_the_transcript_is_deleted(self):
        self.file.write_text(assistant("m1", "r1", "2026-10-14T15:00:00Z"))
        monitor.scan_once(self.store, self.cfg, self.projects)
        self.file.unlink()
        monitor.scan_once(self.store, self.cfg, self.projects)
        self.assertEqual(self.count()[0], 1)

    def test_a_symlinked_project_folder_is_not_read_again_under_its_old_name(self):
        (self.projects / "-Users-x-old").symlink_to(self.projects / "-Users-x-proj")
        self.file.write_text(assistant("m1", "r1", "2026-10-14T15:00:00Z"))
        monitor.scan_once(self.store, self.cfg, self.projects)
        projects = [p for (p,) in self.store.db.execute("SELECT project FROM calls")]
        self.assertEqual(projects, [monitor.project_name("-Users-x-proj")])
        self.assertEqual(self.store.db.execute("SELECT count(*) FROM files").fetchone()[0], 1)

    def subagent(self, session, meta):
        folder = self.projects / "-Users-x-proj" / session / "subagents"
        folder.mkdir(parents=True)
        (folder / "agent-a1.jsonl").write_text(assistant("m9", "r9", "2026-10-14T15:00:00Z"))
        if meta:
            (folder / "agent-a1.meta.json").write_text(json.dumps({"description": "Write migration", "agentType": "general-purpose", "effort": "xhigh"}))

    def description(self):
        return self.store.db.execute("SELECT description, effort FROM agents WHERE agent = 'a1'").fetchone()

    def test_a_subagent_copied_into_a_resumed_session_keeps_its_description(self):
        # The copy carries no meta file, and can be read before or after the original.
        self.subagent("original", meta=True)
        monitor.scan_once(self.store, self.cfg, self.projects)
        self.subagent("resumed", meta=False)
        monitor.scan_once(self.store, self.cfg, self.projects)
        self.assertEqual(self.description(), ("Write migration", "xhigh"))

        self.store = monitor.Store(":memory:")
        (self.projects / "-Users-x-proj" / "original" / "subagents" / "agent-a1.meta.json").rename(self.projects / "meta.json")
        monitor.scan_once(self.store, self.cfg, self.projects)
        self.assertEqual(self.description(), (None, None))
        (self.projects / "meta.json").rename(self.projects / "-Users-x-proj" / "original" / "subagents" / "agent-a1.meta.json")
        monitor.fill_missing_agent_meta(self.store, self.projects)
        self.assertEqual(self.description(), ("Write migration", "xhigh"))


class MeterTest(unittest.TestCase):
    def test_estimate_adds_spend_since_the_last_official_reading(self):
        samples = [{"t": T0 + timedelta(hours=1), "sd": 10, "fh": None}]
        m = monitor.estimate_meter(samples, "sd", T0, T0 + timedelta(hours=3), 20.0, lambda a, b: 100.0)
        self.assertEqual((m["official"], m["estimate"]), (10, 15.0))

    def test_calibration_skips_pairs_that_straddle_a_reset(self):
        samples = [
            {"t": T0, "sd": 0}, {"t": T0 + timedelta(hours=1), "sd": 10},
            {"t": T0 + timedelta(hours=20), "sd": 30},
        ]
        rate, pct = monitor.calibrate(samples, "sd", T0, lambda a, b: (b - a).total_seconds() / 36, 5)
        self.assertEqual((rate, pct), (10.0, 10))

    def test_five_hour_window_opens_at_the_first_call_after_the_last_one_closed(self):
        times = [T0, T0 + timedelta(hours=2), T0 + timedelta(hours=6)]
        start, end = monitor.five_hour_bounds(times, T0 + timedelta(hours=7))
        self.assertEqual(start, T0 + timedelta(hours=6))

    def test_subagents_count_by_kind_and_by_the_day_they_started(self):
        def agent(model, effort, hours, cost, active=False):
            return {"model": model, "effort": effort, "first": monitor.iso(T0 + timedelta(hours=hours)), "cost": cost, "active": active}
        counts = monitor.agent_counts([
            agent("claude-opus-5-5", "xhigh", 1, 4.0), agent("claude-opus-5-5", "xhigh", 30, 50.0, active=True),
            agent("claude-sonnet-5-5", "high", 2, 1.0), agent("claude-opus-5-5", "xhigh", -3, 6.0),
        ], T0)
        self.assertEqual((counts["total"], counts["active"], counts["per_day"]), (4, 1, [3, 1, 0, 0, 0, 0, 0]))
        # The running one counts and spends, but stays out of the median of a finished one.
        self.assertEqual(counts["by_kind"][0], {"family": "opus", "effort": "xhigh", "count": 3, "cost": 60.0, "median_cost": 5.0})

    def test_week_curve_climbs_by_the_hour_and_ends_now(self):
        calls = [{"t": T0 + timedelta(minutes=30), "cost": 10.0}, {"t": T0 + timedelta(minutes=90), "cost": 20.0}]
        points = monitor.week_curve(calls, T0, T0 + timedelta(minutes=100), 0.5)
        self.assertEqual([p["pct"] for p in points], [0.0, 5.0, 15.0])
        self.assertEqual(points[-1]["t"], monitor.iso(T0 + timedelta(minutes=100)))

    def test_a_peak_that_disagrees_with_the_spend_is_not_trusted(self):
        self.assertFalse(monitor.peak_trusted(100, 69.0, 23.5))
        self.assertTrue(monitor.peak_trusted(100, 5538.0, 23.5))
        self.assertFalse(monitor.peak_trusted(None, 100.0, 23.5))


class ReadingTest(unittest.TestCase):
    def test_a_reading_entered_by_hand_becomes_the_official_base(self):
        store = monitor.Store(":memory:")
        monitor.add_reading(store, 30, now=T0 + timedelta(hours=2))
        with self.assertRaises(ValueError):
            monitor.add_reading(store, 130)
        samples = [s for s in monitor.meter_samples(store) if s["t"] >= T0]
        m = monitor.estimate_meter(samples, "sd", T0, T0 + timedelta(hours=3), 10.0, lambda a, b: 20.0)
        self.assertEqual((m["official"], m["estimate"]), (30, 32.0))



class ProcessTest(unittest.TestCase):
    APP = "/Applications/Claude.app/Contents/MacOS/Claude"
    CLI = "/Users/x/Library/Application Support/Claude/claude-code/2.1/claude.app/Contents/MacOS/claude"
    S1, S2 = "11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"

    def summary(self):
        mb = 2**20
        procs = {  # pid: (ppid, rss, cpu seconds, ps %cpu, command)
            10: (1, 300 * mb, 0, 0, self.APP),
            11: (10, 500 * mb, 0, 0, self.APP.replace("MacOS/Claude", "Frameworks/Claude Helper (Renderer)")),
            20: (10, 1 * mb, 0, 0, f"/Applications/Claude.app/Contents/Helpers/disclaimer --pgroup -- {self.CLI} --resume={self.S1}"),
            21: (20, 200 * mb, 0, 0, f"{self.CLI} --output-format stream-json --resume={self.S1} --model=claude-opus-5-5"),
            30: (21, 2 * mb, 0, 0, "/bin/zsh -c pnpm test"),
            31: (30, 900 * mb, 0, 0, "node playwright test"),
            40: (21, 2 * mb, 0, 0, "/bin/zsh -c git status"),
            50: (40, 150 * mb, 0, 0, f"claude -p review --session-id {self.S2}"),
            60: (1, 80 * mb, 0, 0, "claude"),
        }
        cpu = {10: 5, 11: 40, 21: 12, 30: 0, 31: 80, 40: 1, 50: 3, 60: 2}
        cwds = {21: "/Users/x/proj", 30: "/Users/x/proj/.claude/worktrees/agent-a1f84a2960a626440/web", 31: "/Users/x/proj/.claude/worktrees/agent-a1f84a2960a626440/web",
                40: "/Users/x/proj", 50: "/Users/x/proj", 60: "/Users/x/notes"}
        now = datetime(2026, 10, 19, tzinfo=timezone.utc)
        return monitor.summarize_processes(procs, cpu, lambda pids: {p: cwds[p] for p in pids if p in cwds}, now, 4, 16 * 2**30, 9 * 2**30)

    def test_each_session_counts_its_commands_and_the_subagents_working_in_their_worktrees(self):
        rows = {r["session"]: r for r in self.summary()["sessions"]}
        s1 = rows[self.S1]
        self.assertEqual((s1["self_cpu"], s1["tools"], s1["tools_cpu"]), (12, 1, 1))
        self.assertEqual([(a["agent"], a["cpu"], a["procs"]) for a in s1["agents"]], [("a1f84a2960a626440", 80, 2)])
        self.assertEqual(s1["cpu"], 93)
        self.assertEqual(s1["folder"], "proj")

    def test_a_session_started_from_another_sessions_shell_is_its_own_row(self):
        rows = {r["session"]: r for r in self.summary()["sessions"]}
        self.assertEqual(rows[self.S2]["cpu"], 3)
        self.assertNotIn(50, [a for a in rows[self.S1]["agents"]])
        self.assertEqual(rows[self.S1]["rss"], (200 + 2 + 900 + 2) * 2**20)

    def test_a_terminal_session_is_listed_by_its_folder_and_the_app_by_itself(self):
        r = self.summary()
        terminal = [s for s in r["sessions"] if s["session"] is None]
        self.assertEqual([(s["folder"], s["cpu"]) for s in terminal], [("notes", 2)])
        # The app without its sessions; the disclaimer wrapper counts as the app's.
        self.assertEqual((r["app"]["cpu"], r["app"]["procs"]), (45, 3))
        self.assertEqual(r["cpu_pct"], round((5 + 40 + 12 + 80 + 1 + 3 + 2) / 4, 1))

    def test_cpu_time_parses_every_ps_form(self):
        self.assertEqual(monitor.parse_cputime("0:01.50"), 1.5)
        self.assertEqual(monitor.parse_cputime("12:00.00"), 720)
        self.assertEqual(monitor.parse_cputime("1-02:00:00"), 93600)


class ContractTest(unittest.TestCase):
    def test_the_state_the_app_decodes_is_what_build_state_serves(self):
        import fixture
        self.assertEqual(fixture.FIXTURE.read_text(), fixture.render(fixture.fixture_state()),
                         "the state changed: run python3 tests/fixture.py, then swift test in macos/")


if __name__ == "__main__":
    unittest.main()
