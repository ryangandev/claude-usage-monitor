# Claude usage monitor

A localhost dashboard of Claude Code usage: `monitor.py` (scanner, estimates, HTTP server) and `static/index.html` (the page).

## Start here

1. Read [README.md](README.md) for what it does and how it runs.
2. Read [docs/README.md](docs/README.md) before changing how a number is computed.

## Commands

- Tests: `python3 -m unittest discover -s tests`.
- One scan with the estimates printed: `python3 monitor.py --once`.
- The running agent: `./install.sh` restarts it after a change; the log is `~/Library/Logs/claude-usage-monitor.log`.

## Rules

- Standard library only, and the page loads nothing from the network.
- Bind to 127.0.0.1 only.
- Never read credentials: from `~/.claude.json` read only `oauthAccount.organizationRateLimitTier`.
- Never write to anything under `~/.claude` or the Claude app's folder; the only state is `state.db` here.
- Update docs/README.md in the same commit as a change to how a number is computed.
