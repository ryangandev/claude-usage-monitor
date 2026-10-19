"""Live Claude Code usage monitor.

Tails Claude Code's local transcripts into a SQLite store, reads the Claude
app's sampled plan-usage meter, and serves a dashboard on localhost.
Standard library only.
"""

import argparse
import bisect
import glob
import json
import os
import sqlite3
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOME = Path.home()
ROOT = Path(__file__).resolve().parent
PROJECTS = HOME / ".claude" / "projects"
CLAUDE_JSON = HOME / ".claude.json"
APP_DIR = HOME / "Library" / "Application Support" / "Claude"
METER_FILE = APP_DIR / "plan-usage-history.json"
APP_SESSIONS = APP_DIR / "claude-code-sessions"

DEFAULT_CONFIG = {
    "port": 8765,
    "db_path": str(ROOT / "state.db"),
    "scan_seconds": 3,
    # One known weekly reset; later resets are this plus whole weeks.
    "week_anchor": "2026-10-07T15:00:00Z",
    # API-equivalent dollars per 1% of each limit, used until the meter
    # history in the current window is long enough to calibrate.
    "fallback_week_dollars_per_pct": {"default_claude_max_20x": 23.5, "default_claude_max_5x": 8.0, "default": 3.0},
    "fallback_5h_dollars_per_pct": {"default_claude_max_20x": 6.6, "default_claude_max_5x": 2.2, "default": 0.8},
    "min_calibration_pct": 5,
    # Dollars per million tokens: input, output, 5-minute cache write,
    # 1-hour cache write, cache read.
    "prices": {
        "claude-opus-5-5": [4, 20, 5, 8, 0.2],
        "claude-opus-5": [5, 25, 6.25, 10, 0.5],
        "claude-opus-4-8": [5, 25, 6.25, 10, 0.5],
        "claude-fable-5-1": [10, 50, 12.5, 20, 0.25],
        "claude-fable-5": [10, 50, 12.5, 20, 0.25],
        "claude-sonnet-5-5": [2, 10, 2.5, 4, 0.2],
        "claude-sonnet-5": [2, 10, 2.5, 4, 0.2],
        "claude-haiku-5-5": [0.1, 0.5, 0.125, 0.2, 0.01],
    },
    "default_price": [4, 20, 5, 8, 0.2],
}


def load_config():
    cfg = json.loads(json.dumps(DEFAULT_CONFIG))
    override = ROOT / "config.json"
    if override.exists():
        cfg.update(json.loads(override.read_text()))
    return cfg


def parse_ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def iso(dt):
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def call_cost(prices, default, model, inp, out, cw5, cw1, cr):
    p = prices.get(model, default)
    return (inp * p[0] + out * p[1] + cw5 * p[2] + cw1 * p[3] + cr * p[4]) / 1e6


SCHEMA = """
CREATE TABLE IF NOT EXISTS calls (
  msg_id TEXT, req_id TEXT, ts TEXT, model TEXT, project TEXT, session TEXT,
  agent TEXT, effort TEXT, inp INTEGER, out INTEGER, cw5 INTEGER, cw1 INTEGER,
  cr INTEGER, cost REAL, PRIMARY KEY (msg_id, req_id));
CREATE INDEX IF NOT EXISTS calls_ts ON calls(ts);
CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, ino INTEGER, offset INTEGER);
CREATE TABLE IF NOT EXISTS agents (
  agent TEXT PRIMARY KEY, session TEXT, description TEXT, agent_type TEXT, effort TEXT, model TEXT);
CREATE TABLE IF NOT EXISTS readings (t TEXT PRIMARY KEY, sd REAL);
"""

# Bumped when the state's shape changes, so the menu bar app can tell an old server from its own.
API_VERSION = 2


class Store:
    def __init__(self, path):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.executescript(SCHEMA)
        self.lock = threading.Lock()


def project_name(dirname):
    name = dirname
    for prefix in ("-Users-" + HOME.name + "-Documents-GitHub-", "-Users-" + HOME.name + "-"):
        if name.startswith(prefix):
            name = name[len(prefix):]
            break
    return name.split("--claude-worktrees")[0]


def transcript_files(projects=PROJECTS):
    # A symlinked project folder, left by a renamed repository, is another name for a real one: skip it so its calls keep the real name.
    dirs = [d for d in glob.glob(str(projects / "*")) if not os.path.islink(d)]
    return [f for d in dirs for f in glob.glob(os.path.join(d, "*.jsonl")) + glob.glob(os.path.join(d, "*", "subagents", "*.jsonl"))]


def parse_line(line, path, projects, cfg):
    """Turn one transcript line into a call row, or None."""
    if '"usage"' not in line or '"assistant"' not in line:
        return None
    try:
        d = json.loads(line)
    except ValueError:
        return None
    if d.get("type") != "assistant":
        return None
    m = d.get("message") or {}
    u = m.get("usage")
    model = m.get("model")
    if not u or not model or model == "<synthetic>":
        return None
    rel = Path(path).relative_to(projects).parts
    agent = Path(path).stem[len("agent-"):] if "subagents" in rel else None
    cc = u.get("cache_creation") or {}
    cw5 = cc.get("ephemeral_5m_input_tokens", 0) if cc else u.get("cache_creation_input_tokens", 0)
    cw1 = cc.get("ephemeral_1h_input_tokens", 0)
    inp, out, cr = u.get("input_tokens", 0), u.get("output_tokens", 0), u.get("cache_read_input_tokens", 0)
    return (
        m.get("id"), d.get("requestId"), d.get("timestamp"), model, project_name(rel[0]),
        d.get("sessionId"), agent, d.get("effort"), inp, out, cw5, cw1, cr,
        call_cost(cfg["prices"], cfg["default_price"], model, inp, out, cw5, cw1, cr),
    )


def read_agent_meta(store, path, agent, session):
    """Record a subagent's description, type, effort and model from the meta file beside its transcript.

    A resumed or forked session gets copies of its subagents' transcripts without their meta files,
    so a field the copy lacks keeps what another copy already recorded.
    """
    meta_path = path[: -len(".jsonl")] + ".meta.json"
    try:
        meta = json.loads(Path(meta_path).read_text())
    except (OSError, ValueError):
        meta = {}
    store.db.execute(
        """INSERT INTO agents VALUES (?,?,?,?,?,?) ON CONFLICT(agent) DO UPDATE SET
             session = coalesce(agents.session, excluded.session),
             description = coalesce(excluded.description, agents.description),
             agent_type = coalesce(excluded.agent_type, agents.agent_type),
             effort = coalesce(excluded.effort, agents.effort),
             model = coalesce(excluded.model, agents.model)""",
        (agent, session, meta.get("description"), meta.get("agentType"), meta.get("effort"), meta.get("model")),
    )


def fill_missing_agent_meta(store, projects=PROJECTS):
    """Fill the descriptions an older version lost when a copied transcript overwrote them."""
    missing = {a for (a,) in store.db.execute("SELECT agent FROM agents WHERE description IS NULL")}
    if not missing:
        return
    with store.lock:
        for meta_path in glob.glob(str(projects / "*" / "*" / "subagents" / "agent-*.meta.json")):
            agent = Path(meta_path).name[len("agent-"):-len(".meta.json")]
            if agent in missing:
                read_agent_meta(store, meta_path[: -len(".meta.json")] + ".jsonl", agent, None)
        store.db.commit()


def scan_once(store, cfg, projects=PROJECTS):
    """Read whatever was appended to each transcript since the last scan."""
    lines = 0
    with store.lock:
        known = {p: (ino, off) for p, ino, off in store.db.execute("SELECT path, ino, offset FROM files")}
        for path in transcript_files(projects):
            try:
                st = os.stat(path)
            except OSError:
                continue
            ino, off = known.get(path, (None, 0))
            if ino != st.st_ino or st.st_size < off:
                off = 0
            first_read = off == 0
            if st.st_size == off:
                continue
            rows = []
            with open(path, "rb") as fh:
                fh.seek(off)
                for raw in fh:
                    if not raw.endswith(b"\n"):
                        break  # a line still being written; read it next scan
                    off += len(raw)
                    row = parse_line(raw.decode("utf-8", "replace"), path, projects, cfg)
                    if row:
                        rows.append(row)
            if rows:
                store.db.executemany(
                    "INSERT OR REPLACE INTO calls VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", rows
                )
                lines += len(rows)
                agent = rows[0][6]
                if agent and (first_read or agent not in known_agents(store)):
                    read_agent_meta(store, path, agent, rows[0][5])
            store.db.execute(
                "INSERT OR REPLACE INTO files VALUES (?,?,?)", (path, st.st_ino, off)
            )
        store.db.commit()
    return lines


def known_agents(store):
    if not hasattr(store, "_agents") or store._agents_at < time.time() - 30:
        store._agents = {a for (a,) in store.db.execute("SELECT agent FROM agents")}
        store._agents_at = time.time()
    return store._agents


def session_titles():
    titles = {}
    for f in glob.glob(str(APP_SESSIONS / "*" / "*" / "local_*.json")):
        try:
            d = json.loads(Path(f).read_text())
        except (OSError, ValueError):
            continue
        if d.get("cliSessionId") and d.get("title"):
            titles[d["cliSessionId"]] = d["title"]
    for f in glob.glob(str(PROJECTS / "*" / "*" / "custom-title.json")):
        try:
            t = json.loads(Path(f).read_text()).get("customTitle")
        except (OSError, ValueError):
            continue
        if t:
            titles[Path(f).parent.name] = t
    return titles


def plan_tier():
    try:
        acct = json.loads(CLAUDE_JSON.read_text()).get("oauthAccount") or {}
    except (OSError, ValueError):
        return None
    return acct.get("organizationRateLimitTier")


def meter_samples(store=None):
    """The app's sampled meter, plus weekly readings entered by hand, oldest first."""
    try:
        samples = json.loads(METER_FILE.read_text()).get("samples", [])
    except (OSError, ValueError):
        samples = []
    out = []
    for s in samples:
        u = s.get("u") or {}
        if "sd" in u or "fh" in u:
            out.append({"t": datetime.fromtimestamp(s["t"] / 1000, timezone.utc), "sd": u.get("sd"), "fh": u.get("fh")})
    if store is not None:
        with store.lock:
            for t, sd in store.db.execute("SELECT t, sd FROM readings"):
                out.append({"t": parse_ts(t), "sd": sd, "fh": None})
    return sorted(out, key=lambda s: s["t"])


def add_reading(store, pct, now=None):
    """Record a weekly reading the user read off claude.ai, as if the app had sampled it."""
    pct = float(pct)
    if not 0 <= pct <= 100:
        raise ValueError("a reading is a percentage from 0 to 100")
    with store.lock:
        store.db.execute("INSERT OR REPLACE INTO readings VALUES (?, ?)", (iso(now or datetime.now(timezone.utc)), pct))
        store.db.commit()


def week_bounds(now, anchor):
    a = parse_ts(anchor)
    k = (now - a) // timedelta(days=7)
    start = a + k * timedelta(days=7)
    return start, start + timedelta(days=7)


def five_hour_bounds(call_times, now):
    """A 5-hour window opens at the first call after the previous one closed."""
    start = None
    for t in call_times:
        if start is None or t >= start + timedelta(hours=5):
            start = t
    if start is None or now >= start + timedelta(hours=5):
        return None, None
    return start, start + timedelta(hours=5)


def calibrate(samples, key, start, cost_between, minimum, max_gap=timedelta(hours=6)):
    """Dollars per 1% from consecutive meter samples inside [start, now).

    Pairs further apart than max_gap may straddle a reset, so they are skipped.
    """
    pts = [s for s in samples if s["t"] >= start and s[key] is not None]
    d_pct = d_cost = 0.0
    for a, b in zip(pts, pts[1:]):
        if b[key] > a[key] and b["t"] - a["t"] <= max_gap:
            d_pct += b[key] - a[key]
            d_cost += cost_between(a["t"], b["t"])
    if d_pct >= minimum and d_cost > 0:
        return d_cost / d_pct, d_pct
    return None, d_pct


def estimate_meter(samples, key, start, now, rate, cost_between):
    """Last official reading in this window plus spend since, converted to %."""
    inside = [s for s in samples if start <= s["t"] <= now and s[key] is not None]
    if inside:
        base, base_t = inside[-1][key], inside[-1]["t"]
    else:
        base, base_t = 0, start
    since = cost_between(base_t, now)
    est = base + (since / rate if rate else 0)
    return {"official": inside[-1][key] if inside else None,
            "official_at": iso(inside[-1]["t"]) if inside else None,
            "estimate": round(min(est, 100.0), 1), "spend_since_official": round(since, 2)}


def family(model):
    for name in ("opus", "sonnet", "haiku", "fable"):
        if name in model:
            return name
    return "other"

_history_cache = {"at": 0.0, "value": None}


def peak_trusted(peak, spend, rate):
    """Whether a week's highest official reading agrees with what it spent, within a factor of three of the current rate."""
    if not peak or not rate:
        return False
    return rate / 3 <= spend / peak <= rate * 3


def weekly_history(store, cfg, samples, now, rate=None, weeks=8):
    """Spend and the highest official reading for each of the last weekly windows."""
    if _history_cache["value"] is not None and time.time() - _history_cache["at"] < 60:
        return _history_cache["value"]
    w_start, _ = week_bounds(now, cfg["week_anchor"])
    first = w_start - timedelta(days=7 * (weeks - 1))
    out = [{"start": iso(first + timedelta(days=7 * i)), "end": iso(first + timedelta(days=7 * (i + 1))),
            "total": 0.0, "subagent": 0.0, "opus": 0.0, "sonnet": 0.0, "haiku": 0.0, "fable": 0.0, "other": 0.0,
            "official_peak": None} for i in range(weeks)]
    with store.lock:
        rows = store.db.execute("SELECT ts, model, agent, cost FROM calls WHERE ts >= ?", (iso(first),)).fetchall()
    for ts, model, agent, cost in rows:
        i = (parse_ts(ts) - first) // timedelta(days=7)
        if 0 <= i < weeks:
            w = out[i]
            w["total"] += cost
            w[family(model)] += cost
            if agent:
                w["subagent"] += cost
    for s in samples:
        i = (s["t"] - first) // timedelta(days=7)
        if 0 <= i < weeks and s["sd"] is not None:
            # A reading taken right at the reset still shows the old week.
            if s["t"] - (first + timedelta(days=7 * i)) > timedelta(minutes=5):
                out[i]["official_peak"] = max(out[i]["official_peak"] or 0, s["sd"])
    for w in out:
        for k in ("total", "subagent", "opus", "sonnet", "haiku", "fable", "other"):
            w[k] = round(w[k], 2)
        w["official_peak_trusted"] = peak_trusted(w["official_peak"], w["total"], rate)
    _history_cache.update(at=time.time(), value=out)
    return out


def week_days(calls, w_start, now):
    """The current weekly window cut into seven 24-hour days from its reset."""
    days = []
    for i in range(7):
        a, b = w_start + timedelta(days=i), w_start + timedelta(days=i + 1)
        d = {"start": iso(a), "end": iso(b), "total": 0.0, "opus": 0.0, "sonnet": 0.0, "haiku": 0.0,
             "fable": 0.0, "other": 0.0, "state": "past" if b <= now else "current" if a <= now else "future"}
        for c in calls:
            if a <= c["t"] < b:
                d["total"] += c["cost"]
                d[family(c["model"])] += c["cost"]
        days.append({k: (round(v, 2) if isinstance(v, float) else v) for k, v in d.items()})
    return days


def median(xs):
    xs = sorted(xs)
    n = len(xs)
    return (xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2) if n else 0.0


def agent_counts(agents, w_start):
    """How many subagents ran this week, by model and effort, and how many started on each of its seven days.

    Each kind also carries what it spent and what one finished subagent of it typically costs;
    running ones are left out of that median, since they have not spent everything yet.
    """
    kinds, per_day = {}, [0] * 7
    for a in agents:
        k = kinds.setdefault((family(a["model"]), a["effort"]), {"count": 0, "cost": 0.0, "done": []})
        k["count"] += 1
        k["cost"] += a["cost"]
        if not a["active"]:
            k["done"].append(a["cost"])
        day = int((parse_ts(a["first"]) - w_start) / timedelta(days=1))
        per_day[min(max(day, 0), 6)] += 1
    by_kind = [{"family": f, "effort": e, "count": k["count"], "cost": round(k["cost"], 2), "median_cost": round(median(k["done"]), 2)}
               for (f, e), k in kinds.items()]
    return {"total": len(agents), "active": sum(1 for a in agents if a["active"]), "per_day": per_day,
            "by_kind": sorted(by_kind, key=lambda k: -k["count"])}


def week_curve(calls, w_start, now, scale):
    """Percent of the weekly limit used by the end of each hour since the reset, ending at now."""
    points, used, i = [{"t": iso(w_start), "pct": 0.0}], 0.0, 0
    t = w_start + timedelta(hours=1)
    while True:
        end = min(t, now)
        while i < len(calls) and calls[i]["t"] < end:
            used += calls[i]["cost"]
            i += 1
        points.append({"t": iso(end), "pct": round(used * scale, 2)})
        if end >= now:
            return points
        t += timedelta(hours=1)


def build_state(store, cfg, now=None):
    now = now or datetime.now(timezone.utc)
    with store.lock:
        rows = store.db.execute(
            "SELECT ts, model, project, session, agent, effort, inp, out, cw5, cw1, cr, cost FROM calls WHERE ts >= ? ORDER BY ts",
            (iso(now - timedelta(days=8)),),
        ).fetchall()
        agent_meta = {r[0]: r[1:] for r in store.db.execute("SELECT * FROM agents")}
    calls = [dict(zip(("ts", "model", "project", "session", "agent", "effort", "inp", "out", "cw5", "cw1", "cr", "cost"), r)) for r in rows]
    for c in calls:
        c["t"] = parse_ts(c["ts"])

    times = [c["t"] for c in calls]
    cum = [0.0]
    for c in calls:
        cum.append(cum[-1] + c["cost"])

    def cost_between(a, b):
        return cum[bisect.bisect_left(times, b)] - cum[bisect.bisect_left(times, a)]

    tier = plan_tier()
    samples = meter_samples(store)
    w_start, w_end = week_bounds(now, cfg["week_anchor"])
    week = [c for c in calls if c["t"] >= w_start]

    w_rate, w_cal = calibrate(samples, "sd", w_start, cost_between, cfg["min_calibration_pct"])
    w_rate_src = "calibrated" if w_rate else "fallback"
    w_rate = w_rate or cfg["fallback_week_dollars_per_pct"].get(tier, cfg["fallback_week_dollars_per_pct"]["default"])
    weekly = estimate_meter(samples, "sd", w_start, now, w_rate, cost_between)

    h_start, h_end = five_hour_bounds([c["t"] for c in calls if c["t"] >= now - timedelta(hours=10)], now)
    h_rate, h_cal = calibrate(samples, "fh", w_start, cost_between, cfg["min_calibration_pct"], timedelta(hours=2))
    h_rate_src = "calibrated" if h_rate else "fallback"
    h_rate = h_rate or cfg["fallback_5h_dollars_per_pct"].get(tier, cfg["fallback_5h_dollars_per_pct"]["default"])
    five = estimate_meter(samples, "fh", h_start, now, h_rate, cost_between) if h_start else {"official": None, "official_at": None, "estimate": 0, "spend_since_official": 0}

    burn = cost_between(now - timedelta(hours=1), now)

    def eta(pct, rate):
        if burn <= 0 or pct >= 100:
            return None
        return iso(now + timedelta(hours=(100 - pct) * rate / burn))

    titles = session_titles()

    def bucket(rows_, key):
        out = {}
        for c in rows_:
            k = key(c)
            b = out.setdefault(k, {"key": k, "cost": 0.0, "calls": 0, "output_tokens": 0})
            b["cost"] += c["cost"]
            b["calls"] += 1
            b["output_tokens"] += c["out"]
        return sorted(({**b, "cost": round(b["cost"], 2)} for b in out.values()), key=lambda b: -b["cost"])

    def effort_of(c):
        meta = agent_meta.get(c["agent"]) if c["agent"] else None
        return (meta and meta[3]) or c["effort"] or "n/a"

    # Hourly spend for the last 48 hours, split by model family.
    hours = []
    h0 = now.replace(minute=0, second=0, microsecond=0) - timedelta(hours=47)
    idx = {}
    for i in range(48):
        t = h0 + timedelta(hours=i)
        idx[t] = len(hours)
        hours.append({"hour": iso(t), "opus": 0.0, "sonnet": 0.0, "haiku": 0.0, "fable": 0.0, "other": 0.0})
    for c in calls:
        t = c["t"].replace(minute=0, second=0, microsecond=0)
        if t in idx:
            hours[idx[t]][family(c["model"])] += c["cost"]
    for h in hours:
        for k in ("opus", "sonnet", "haiku", "fable", "other"):
            h[k] = round(h[k], 3)

    # Subagents active in the last 15 minutes, and the costliest this week.
    agents = {}
    for c in week:
        if not c["agent"]:
            continue
        a = agents.setdefault(c["agent"], {"agent": c["agent"], "cost": 0.0, "calls": 0, "first": c["ts"], "session": c["session"]})
        a["cost"] += c["cost"]
        a["calls"] += 1
        a["last"] = c["ts"]
        a["model"] = c["model"]
        a["context"] = c["inp"] + c["cr"] + c["cw5"] + c["cw1"]
    for a in agents.values():
        meta = agent_meta.get(a["agent"]) or (None,) * 5
        a["description"] = meta[1] or "(no description)"
        a["effort"] = meta[3] or "n/a"
        a["session_title"] = titles.get(a["session"], (a["session"] or "")[:8])
        a["cost"] = round(a["cost"], 2)
        a["active"] = parse_ts(a["last"]) >= now - timedelta(minutes=15)
    agent_list = sorted(agents.values(), key=lambda a: (not a["active"], -a["cost"]))

    sessions = {}
    for c in week:
        s = sessions.setdefault(c["session"], {"session": c["session"], "title": titles.get(c["session"], (c["session"] or "")[:8]),
                                               "project": c["project"], "main": 0.0, "sub": 0.0, "agents": set(), "running": set(), "last": c["ts"]})
        s["sub" if c["agent"] else "main"] += c["cost"]
        if c["agent"]:
            s["agents"].add(c["agent"])
            if agents[c["agent"]]["active"]:
                s["running"].add(c["agent"])
        s["last"] = c["ts"]
    # A session is active when it made a call in the last 10 minutes.
    session_list = sorted(({**s, "agents": len(s["agents"]), "running": len(s["running"]), "main": round(s["main"], 2), "sub": round(s["sub"], 2),
                            "total": round(s["main"] + s["sub"], 2), "active": parse_ts(s["last"]) >= now - timedelta(minutes=10)}
                           for s in sessions.values()), key=lambda s: -s["total"])

    week_total = sum(c["cost"] for c in week)
    # Dollars per 1% that make this week's spend add up to the estimate; per-session and per-agent shares use it.
    effective = week_total / weekly["estimate"] if weekly["estimate"] > 0 and week_total > 0 else w_rate
    elapsed = (now - w_start) / (w_end - w_start)
    eta_week = eta(weekly["estimate"], w_rate)
    return {
        "api_version": API_VERSION,
        "now": iso(now),
        "tier": tier,
        "weekly": {**weekly, "start": iso(w_start), "end": iso(w_end), "dollars_per_pct": round(w_rate, 2),
                   "rate_source": w_rate_src, "calibration_pct": w_cal, "eta_full": eta_week,
                   "runs_out_early": eta_week is not None and parse_ts(eta_week) < w_end,
                   "burn_pct_per_hour": round(burn / w_rate, 2),
                   "forecast_at_reset": round(weekly["estimate"] / elapsed, 1) if elapsed > 0 else None,
                   "effective_dollars_per_pct": round(effective, 2)},
        "five_hour": {**five, "start": iso(h_start) if h_start else None, "end": iso(h_end) if h_end else None,
                      "dollars_per_pct": round(h_rate, 2), "rate_source": h_rate_src, "calibration_pct": h_cal,
                      "eta_full": eta(five["estimate"], h_rate) if h_start else None},
        "burn_last_hour": round(burn, 2),
        "today": round(sum(c["cost"] for c in calls if c["t"].astimezone().date() == now.astimezone().date()), 2),
        "week": {"total": round(week_total, 2), "calls": len(week),
                 "subagent": round(sum(c["cost"] for c in week if c["agent"]), 2),
                 "by_model": bucket(week, lambda c: c["model"]),
                 "by_effort": bucket(week, lambda c: ("sub" if c["agent"] else "main") + " · " + effort_of(c))},
        "hours": hours,
        "agents": agent_list[:300],
        "active_agents": sum(1 for a in agent_list if a["active"]),
        "sessions": session_list[:20],
        "all_sessions": session_list[:500],
        "week_curve": week_curve(week, w_start, now, 1 / effective),
        "last_call": calls[-1]["ts"] if calls else None,
        "week_days": week_days(week, w_start, now),
        "agent_counts": agent_counts(agent_list, w_start),
        "week_elapsed_days": round((now - w_start) / timedelta(days=1), 2),
        "daily_budget": round(w_rate * 100 / 7, 2),
        "weeks": weekly_history(store, cfg, samples, now, w_rate),
    }


class Handler(BaseHTTPRequestHandler):
    store = None
    cfg = None

    def log_message(self, *args):
        pass

    def send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        # Only the app posts here. A page in a browser cannot send this header to another origin
        # without a preflight, which this server never answers, so no other site can write a reading.
        if self.path != "/api/reading" or self.headers.get("X-Claude-Usage") != "1":
            self.send(403, b"forbidden", "text/plain")
            return
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)))
            add_reading(self.store, body["weekly"])
        except (ValueError, KeyError, TypeError) as exc:
            self.send(400, str(exc).encode(), "text/plain")
            return
        _history_cache["value"] = None
        self.send(204, b"", "text/plain")

    def do_GET(self):
        if self.path == "/api/state":
            body = json.dumps(build_state(self.store, self.cfg)).encode()
            self.send(200, body, "application/json")
        elif self.path in ("/", "/index.html"):
            self.send(200, (ROOT / "static" / "index.html").read_bytes(), "text/html; charset=utf-8")
        else:
            self.send(404, b"not found", "text/plain")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--once", action="store_true", help="scan once, print a summary and exit")
    ap.add_argument("--db", help="where to keep state.db (default: next to monitor.py)")
    ap.add_argument("--port", type=int, help="port to serve on (default: 8765)")
    args = ap.parse_args()
    cfg = load_config()
    if args.db:
        cfg["db_path"] = args.db
    if args.port:
        cfg["port"] = args.port
    store = Store(cfg["db_path"])
    t0 = time.time()
    n = scan_once(store, cfg)
    fill_missing_agent_meta(store)
    print(f"initial scan: {n} usage lines in {time.time() - t0:.1f}s", flush=True)
    if args.once:
        s = build_state(store, cfg)
        print(json.dumps({k: s[k] for k in ("tier", "weekly", "five_hour", "burn_last_hour", "today")}, indent=2))
        return

    def loop():
        while True:
            time.sleep(cfg["scan_seconds"])
            try:
                scan_once(store, cfg)
            except Exception as exc:  # keep the server alive on a bad file
                print(f"scan failed: {exc}", flush=True)

    threading.Thread(target=loop, daemon=True).start()
    Handler.store, Handler.cfg = store, cfg
    server = ThreadingHTTPServer(("127.0.0.1", cfg["port"]), Handler)
    print(f"serving http://127.0.0.1:{cfg['port']}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
