# Claude usage monitor

A local, live dashboard of Claude Code usage on this Mac.
It tails Claude Code's transcripts into a SQLite store, reads the Claude app's sampled plan-usage meter, and serves a page at http://127.0.0.1:8765 that refreshes every 5 seconds.

## Run

```sh
./install.sh      # start now and at every login (launchd agent)
./uninstall.sh    # stop and remove the agent; state.db stays
python3 monitor.py          # run in the foreground instead
python3 monitor.py --once   # scan once and print the meter estimates
```

Standard library only; Python 3.10 or later.

## What it shows

- Weekly and 5-hour limits: the app's last official reading, plus an estimate for spend since then, and when the current pace would reach 100%.
- Spend in the last hour, today and this limit window, and the share spent by subagents.
- Hourly spend for 48 hours by model family, and this window's spend by model and by effort.
- Every subagent this window, active ones first, with model, effort, calls, current context size and spend.

How the numbers are worked out is in [docs/README.md](docs/README.md).
