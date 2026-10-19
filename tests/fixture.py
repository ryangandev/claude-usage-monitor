"""A fixed /api/state built from synthetic transcripts, shared by the Python and Swift tests.

The menu bar app decodes tests/fixtures/state.json in its own tests, so a change to the state's shape
that the app does not follow fails there. After changing build_state, write the file again:

    python3 tests/fixture.py
"""
import json
import os
import sys
import tempfile
import time
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import monitor  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "state.json"

# The weekly window opened at T0; "now" is Sunday evening of that week.
T0 = datetime(2026, 10, 14, 15, 0, tzinfo=timezone.utc)
NOW = T0 + timedelta(days=4, hours=6, minutes=30)


def call(session, n, at, model="claude-opus-5-5", out=200_000, effort=None):
    line = {"type": "assistant", "requestId": f"r-{session}-{n}", "timestamp": monitor.iso(at), "sessionId": session,
            "message": {"id": f"m-{session}-{n}", "model": model, "usage": {
                "input_tokens": 10, "output_tokens": out, "cache_read_input_tokens": 50_000,
                "cache_creation": {"ephemeral_5m_input_tokens": 2_000, "ephemeral_1h_input_tokens": 0}}}}
    if effort:
        line["effort"] = effort
    return json.dumps(line) + "\n"


def write_world(root):
    projects = root / "projects"
    web, api = projects / "acme-web", projects / "acme-api"
    for d in (web, api):
        d.mkdir(parents=True)

    # Last week, for the history.
    (api / "s0.jsonl").write_text("".join(call("s0", i, T0 - timedelta(days=3, hours=i)) for i in range(6)))
    # A long session that ran all week, with a finished and a running subagent.
    (web / "s1.jsonl").write_text("".join(call("s1", i, T0 + timedelta(hours=5 + 9 * i)) for i in range(11)))
    agents = web / "s1" / "subagents"
    agents.mkdir(parents=True)
    (agents / "agent-a1.jsonl").write_text("".join(
        call("s1", 100 + i, T0 + timedelta(days=2, minutes=10 * i), out=300_000) for i in range(4)))
    (agents / "agent-a1.meta.json").write_text(json.dumps({"description": "Write migration for orders", "agentType": "general-purpose", "effort": "xhigh"}))
    (agents / "agent-a2.jsonl").write_text("".join(
        call("s1", 200 + i, NOW - timedelta(minutes=40 - 8 * i), model="claude-sonnet-5-5", out=150_000) for i in range(5)))
    (agents / "agent-a2.meta.json").write_text(json.dumps({"description": "Implement search filters", "agentType": "general-purpose", "effort": "high"}))
    # A busy hour just now in another session, so the week runs out early.
    (api / "s2.jsonl").write_text("".join(call("s2", i, NOW - timedelta(minutes=55 - 5 * i), out=400_000) for i in range(11)))
    # A quiet session from midweek.
    (web / "s3.jsonl").write_text("".join(call("s3", i, T0 + timedelta(days=2, hours=3 + i), model="claude-sonnet-5-5") for i in range(3)))

    titles = root / "app" / "claude-code-sessions" / "u" / "o"
    titles.mkdir(parents=True)
    for sid, title in (("s1", "Refactor billing service"), ("s2", "Fix flaky checkout tests"), ("s3", "Draft API docs")):
        (titles / f"local_{sid}.json").write_text(json.dumps({"cliSessionId": sid, "title": title}))

    ms = lambda dt: int(dt.timestamp() * 1000)
    meter = root / "app" / "plan-usage-history.json"
    meter.write_text(json.dumps({"samples": [
        {"t": ms(T0 - timedelta(days=1)), "u": {"sd": 64, "fh": 10}},
        {"t": ms(T0 + timedelta(days=1)), "u": {"sd": 9, "fh": 4}},
        {"t": ms(NOW - timedelta(hours=20)), "u": {"sd": 21, "fh": 0}},
    ]}))
    claude_json = root / "claude.json"
    claude_json.write_text(json.dumps({"oauthAccount": {"organizationRateLimitTier": "default_claude_max_20x"}}))
    return projects, meter, root / "app" / "claude-code-sessions", claude_json


@contextmanager
def utc():
    """`today` is the local calendar day; pin it to UTC so the fixture is the same on every machine."""
    old = os.environ.get("TZ")
    os.environ["TZ"] = "UTC"
    time.tzset()
    try:
        yield
    finally:
        if old is None:
            del os.environ["TZ"]
        else:
            os.environ["TZ"] = old
        time.tzset()


def fixture_state():
    with tempfile.TemporaryDirectory() as tmp, utc():
        projects, meter, sessions, claude_json = write_world(Path(tmp))
        saved = (monitor.PROJECTS, monitor.METER_FILE, monitor.APP_SESSIONS, monitor.CLAUDE_JSON)
        monitor.PROJECTS, monitor.METER_FILE, monitor.APP_SESSIONS, monitor.CLAUDE_JSON = projects, meter, sessions, claude_json
        monitor._history_cache["value"] = None
        try:
            cfg = json.loads(json.dumps(monitor.DEFAULT_CONFIG))  # not load_config: a local config.json must not change the fixture
            cfg["week_anchor"] = monitor.iso(T0)
            store = monitor.Store(":memory:")
            monitor.scan_once(store, cfg, projects)
            monitor.add_reading(store, 27, now=NOW - timedelta(hours=3))
            return monitor.build_state(store, cfg, now=NOW)
        finally:
            monitor.PROJECTS, monitor.METER_FILE, monitor.APP_SESSIONS, monitor.CLAUDE_JSON = saved
            monitor._history_cache["value"] = None


def render(state):
    return json.dumps(state, indent=1, sort_keys=True, ensure_ascii=False) + "\n"


if __name__ == "__main__":
    FIXTURE.parent.mkdir(exist_ok=True)
    FIXTURE.write_text(render(fixture_state()))
    print(f"wrote {FIXTURE.relative_to(Path.cwd()) if FIXTURE.is_relative_to(Path.cwd()) else FIXTURE}")
