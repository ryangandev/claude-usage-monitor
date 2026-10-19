# Claude usage monitor

A localhost dashboard of Claude Code usage: `monitor.py` (scanner, estimates, HTTP server), `static/index.html` (the page), and `macos/` (the menu bar app that runs `monitor.py` and shows its state natively).

## Start here

1. Read [README.md](README.md) for what it does and how it runs.
2. Read [docs/README.md](docs/README.md) before changing how a number is computed.

## Commands

- Tests: `python3 -m unittest discover -s tests`.
- The state the app decodes: `tests/fixtures/state.json`, which `build_state` must reproduce and the app's `ContractTests` decode. After changing the state's shape, run `python3 tests/fixture.py` to write it again, then `swift test` in `macos/`.
- One scan with the estimates printed: `python3 monitor.py --once`.
- The running agent: `./install.sh` restarts it after a change; the log is `~/Library/Logs/claude-usage-monitor.log`.
- The app, from `macos/`: `swift test`, and `./build-app.sh --install` to rebuild and reopen it; its log is `~/Library/Application Support/Claude Usage/monitor.log`.
- To see the menu bar item and popover without a mouse: `open ~/Applications/Claude\ Usage.app --args --show-popover --snapshot <dir>` writes `item.png` and `popover.png` to `<dir>` (quit the app first).
- The dashboard window has a minimum width of 960; check the tables there too, since they drop columns to fit.

## Rules

- Standard library only, and the page loads nothing from the network.
- Bind to 127.0.0.1 only.
- Never read credentials: from `~/.claude.json` read only `oauthAccount.organizationRateLimitTier`.
- Never write to anything under `~/.claude` or the Claude app's folder; the only state is `state.db`, next to `monitor.py` or, for the app, in `~/Library/Application Support/Claude Usage/`.
- Bump `API_VERSION` in `monitor.py` when the state's shape changes, so the app stops reusing an older server.
- A field the app shows is shown on the page too, worked out the same way: the page's `derive` mirrors the app's `Usage`.
- The only write endpoint is `POST /api/reading`, and it requires the `X-Claude-Usage: 1` header so a web page cannot call it.
- Update docs/README.md in the same commit as a change to how a number is computed.
- The repository is public: screenshots in `docs/images/` must show made-up session, project and task names, never real ones.
- README.md and README.zh-CN.md say the same things; change both together. Each has its own screenshots, English ones and `-zh` ones, taken from the same made-up state.
