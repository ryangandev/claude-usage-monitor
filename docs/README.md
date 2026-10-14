# How the numbers are worked out

## Sources

- Transcripts: `~/.claude/projects/<project>/<session>.jsonl`, and subagents in `<session>/subagents/agent-<id>.jsonl` with `agent-<id>.meta.json` (description, type, effort).
  Each assistant line carries one model call's token usage.
- The plan meter: `~/Library/Application Support/Claude/plan-usage-history.json`, samples the app records now and then, `sd` the weekly limit and `fh` the 5-hour limit, in percent.
- The plan tier: `oauthAccount.organizationRateLimitTier` in `~/.claude.json`.
- Session titles: the app's `claude-code-sessions/.../local_*.json` (`cliSessionId` to `title`) and `custom-title.json` in a session folder.

## Calls

A call is keyed by message id and request id; the same call appears on several lines while it streams, and the last line wins.
Each file is read from the byte offset the last scan reached, and a line without its newline waits for the next scan.
Calls stay in `state.db` after their transcript is deleted, so deleting a session no longer loses its usage.

## API-equivalent dollars

Each call's tokens are priced at the API list price of its model (input, output, 5-minute and 1-hour cache writes, cache reads), set in `DEFAULT_CONFIG["prices"]`.
The subscription is not billed this way; it is a yardstick that weights models roughly as the limits do.

## The meter estimate

- Weekly window: a known reset (`week_anchor`) plus whole weeks.
- 5-hour window: opens at the first call after the previous window closed, and lasts five hours.
- Estimate = the last official reading inside the window (0 at the window's start if none) + spend since that reading / dollars per 1%.
- Dollars per 1% is calibrated from consecutive official readings inside the current weekly window that rose and are at most 6 hours apart (2 hours for the 5-hour meter), once they add up to `min_calibration_pct`; until then it uses the per-tier fallback in the config.
- Time to 100% assumes the last hour's spend continues.

Override any config value in an untracked `config.json` next to `monitor.py`.
