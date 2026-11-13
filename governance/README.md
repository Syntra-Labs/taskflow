# Taskflow Governance & Health Policy Engine

Deterministic, executable Policy-as-Code subsystem governing AI-agent usage limits, developer health, and deliberate practice enforcement.

## Architecture

* **[governance.rego](governance.rego)**: Declarative CNCF Open Policy Agent (OPA) policy defining:
  * `HEALTH-001`: Curfew active from 23:00 to 07:00 (commits and agentic tool use blocked).
  * `HEALTH-002`: Single session limit (maximum 1 session of up to 120 minutes per day for ALL AI usage — agentic + vibe-coding + browser AI).
  * `HEALTH-003`: Daily cap of 120 minutes across ALL AI usage, enforced across the 7:00 AM daily boundary.
  * `PRACTICE-001`: Mandatory daily deliberate practice (LeetCode, Codeforces, Deep-ML, or `~/code/practice`) before committing to other projects.
* **[verify-governance](verify-governance)**: Telemetry aggregator and OPA runner. Analyzes local Git commits, Antigravity tool transcripts, and browser AI usage (Chrome history dwell reconstruction) to evaluate compliance.

  **AI usage accounting** — three sources are merged into a single session stream, clustered by a 30-minute gap:
  1. Antigravity conversation transcripts (actual tool calls / tool executions only),
  2. `git log --since=<governance day>` commits when the cwd looks like a vibe-coding repo,
  3. Browser AI dwell time from `~/.config/google-chrome/Default/History` (visits to AI chat & assistant domains listed under `AI_USE` in `tracker/rules.json`).

  Governance day starts at 7:00 AM, not calendar midnight. Any AI activity (CLI, desktop agent, or browser) consumes the same single daily session and the same 120-minute daily cap. `tracker/tracker.py --ai-usage-json` prints the browser-AI report standalone.
* **[agent-governance-hook](agent-governance-hook)**: Pre-tool execution hook for Antigravity (`~/.gemini/config/hooks.json`).
* **[universal-governance-wrapper](universal-governance-wrapper)**: Intercept wrapper for other coding agents (`claude`, `opencode`, `omp`).
* **[sync-calendar-policy](sync-calendar-policy)**: Syncs daily schedule blocks from Google Calendar via `gws`.
* **[log-practice-event](log-practice-event)**: Auto-logs deliberate practice completions to Google Calendar.
* **[log-session-event](log-session-event)**: Auto-logs deep work sessions to Google Calendar.

## Global Installation & Wiring

Executables are symlinked to `~/.local/bin/`:
```bash
ln -sf ~/code/taskflow/governance/verify-governance ~/.local/bin/verify-governance
ln -sf ~/code/taskflow/governance/agent-governance-hook ~/.local/bin/agent-governance-hook
ln -sf ~/code/taskflow/governance/universal-governance-wrapper ~/.local/bin/universal-governance-wrapper
ln -sf ~/code/taskflow/governance/sync-calendar-policy ~/.local/bin/sync-calendar-policy
ln -sf ~/code/taskflow/governance/log-practice-event ~/.local/bin/log-practice-event
ln -sf ~/code/taskflow/governance/log-session-event ~/.local/bin/log-session-event
```

Global git pre-commit gate:
* Handled via `~/.config/git/hooks/pre-commit` -> executes `~/.local/bin/verify-governance`.

Antigravity pre-tool gate:
* Handled via `~/.gemini/config/hooks.json` -> executes `~/.local/bin/agent-governance-hook`.
