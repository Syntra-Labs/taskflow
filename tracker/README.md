# Taskflow Activity & AI Usage Tracker

Minimal, dependency-free tracker (stdlib only) that closes the gap between "what you typed" and "how long you were on a page".

## What it does

* **Pulses every 60s** (via `~/.config/systemd/user/taskflow-tracker.timer`) to classify your current context:
  * `PRACTICE` — deliberate problem solving (LeetCode / Codeforces / Deep-ML / `~/code/practice`)
  * `DEEP_WORK_CORE` — coding in your repos (`/home/yassine/code/*`) and practical reference only (`docs.rs`, MDN, cppreference, Stack Overflow). Research reading (e.g. arXiv) is NOT deep work.
  * `DEEP_WORK_ACADEMIC` — Algonquin College CET-CS coursework
  * `AI_USE` — browser AI chat & assistants (ChatGPT, Claude, Gemini, DeepSeek, Copilot Web, Perplexity, ...) — see `AI_USE` in `rules.json`
  * `COMMUNICATION`, `REST`
* **Idle detection** via GNOME Mutter IdleMonitor — an active session ends when you go idle past `idle_threshold_seconds` (default 600s), and completed blocks ≥ `min_block_minutes` (default 15) are logged to Google Calendar through `gws`.
* **Chrome-only** browser signal (`~/.config/google-chrome/Default/History`).
* Exposes dwell-time reconstruction used by the governance system: every Chrome visit's dwell time (to the next navigation, or to now−idle when Chrome is open) is attributed to its page's category. `AI_USE` segments feed the shared AI budget.

## CLI

```bash
python3 tracker.py                 # run one pulse (what the timer does)
python3 tracker.py --status        # current session + today's AI usage report
python3 tracker.py --ai-usage-json # machine-readable AI report for the governance day
```

## AI usage accounting

Every Chrome visit to an `AI_USE` domain contributes dwell time (capped at 30 minutes per segment). Segments separated by >30 minutes away form distinct sessions. The report covers the **governance day, starting 7:00 AM** (not calendar midnight), and is cached for 60 seconds in `~/.config/taskflow/ai_usage_cache.json`.

This report is consumed by `governance/verify-governance`, which merges it with Antigravity agent transcripts and git commits into a single session stream for the OPA policy (`governance/governance.rego`). Browser AI usage therefore counts toward the same 120-minute daily cap and single-session budget.

## Files

* `tracker.py` — everything (pulse loop, Chrome history parsing, AI dwell reconstruction, classification, calendar logging)
* `rules.json` — categories, domains, paths, and limits (edit this to extend/reclassify)
