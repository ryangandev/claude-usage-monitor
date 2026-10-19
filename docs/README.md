# How the numbers are worked out

## Sources

- Transcripts: `~/.claude/projects/<project>/<session>.jsonl`, and subagents in `<session>/subagents/agent-<id>.jsonl` with `agent-<id>.meta.json` (description, type, effort).
  Each assistant line carries one model call's token usage.
  A project folder that is a symlink, left behind by a renamed repository, is skipped, so its calls are read once and keep the real folder's name.
- The plan meter: `~/Library/Application Support/Claude/plan-usage-history.json`, samples the app records now and then, `sd` the weekly limit and `fh` the 5-hour limit, in percent.
  Weekly readings entered by hand go into the `readings` table and join these samples as weekly-only readings.
- The plan tier: `oauthAccount.organizationRateLimitTier` in `~/.claude.json`.
- Session titles: the app's `claude-code-sessions/.../local_*.json` (`cliSessionId` to `title`) and `custom-title.json` in a session folder.
- Processes: `ps` for every process's parent, memory and CPU time, `lsof` for the working folders of Claude's processes, and `vm_stat` and `sysctl` for the Mac's memory and cores, sampled after each scan.
  Command lines are only matched, never stored or served.

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
- Time to 100% assumes the last hour's spend continues; the week "runs out early" when that time is before the reset.
- The forecast at the reset is the estimate divided by the share of the week gone, so it assumes the week's average pace continues.
- The burn rate is the last hour's spend in percent per hour.

## Shares of the limit

Sessions, projects, subagents and the week's curve are shown as percent of the weekly limit.
They use an effective dollars per 1%: this week's spend divided by the weekly estimate, so the parts add up to the estimate even before the rate is calibrated.
The week's curve is the cumulative spend at the end of each hour since the reset, at that rate.

## Sessions and subagents

A session is active when it made a call in the last 10 minutes; active sessions sort first, the rest by spend this week.
For each model and effort, the typical cost of one subagent is the median spend of finished ones, since running ones have not spent everything yet.

## This Mac

Each Claude Code session is one `claude` process; the desktop app starts it with `--resume=<session id>`, and one started in a terminal without an id is listed by its folder.
A session's processes are its own and every process below it, except another session nested inside it, which gets its own row.
A process whose working folder is a subagent's worktree, `.claude/worktrees/agent-<id>`, counts for that subagent, and so does everything below it; the rest of the commands count as the session's commands.
A subagent that works in the session's own folder cannot be told apart from its session, since subagents run inside the session's process, so it counts under the session.
The Claude app is every process below the app except the sessions.

CPU is CPU time used since the previous sample divided by the time between samples, in percent of one core, so 100% is one full core and a busy Mac can show more than 100% for one session.
A process seen for the first time uses `ps`'s own average instead.
The Mac's CPU is the sum over every process divided by the number of cores.
Memory is resident memory summed over a session's processes, so memory shared between processes counts more than once; the Mac's memory in use is active, wired and compressed pages.

## Past weeks

Each past week shows its spend and the highest official reading inside it.
That peak is trusted only when its spend per 1% is within a factor of three of the current rate, so a week whose readings do not match its spend shows "-".

Override any config value in an untracked `config.json` next to `monitor.py`.
