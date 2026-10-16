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
        def agent(model, effort, hours, active=False):
            return {"model": model, "effort": effort, "first": monitor.iso(T0 + timedelta(hours=hours)), "active": active}
        counts = monitor.agent_counts([
            agent("claude-opus-5-5", "xhigh", 1), agent("claude-opus-5-5", "xhigh", 30, active=True),
            agent("claude-sonnet-5-5", "high", 2), agent("claude-opus-5-5", "xhigh", -3),
        ], T0)
        self.assertEqual((counts["total"], counts["active"], counts["per_day"]), (4, 1, [3, 1, 0, 0, 0, 0, 0]))
        self.assertEqual(counts["by_kind"][0], {"family": "opus", "effort": "xhigh", "count": 3})


if __name__ == "__main__":
    unittest.main()
