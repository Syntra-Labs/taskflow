# Done

Previously open item, now completed:

- [x] Added ALL AI usage to the daily AI governance policy as code limits — including any AI used throughout the browser, not just the CLI or a desktop application.
  - `tracker/rules.json`: new `AI_USE` category (ChatGPT, Claude, Gemini, DeepSeek, Copilot Web, Perplexity, Mistral, You.com, Phind, devv.ai, Arena, OverflowAI, HF chat, ...).
  - `tracker/tracker.py`: Chrome `visits`-level dwell reconstruction, AI session clustering, `--ai-usage-json` machine-readable report, AI classification ahead of other categories, AI blocks logged to calendar.
  - `governance/verify-governance`: now merges Antigravity agent tool calls + git commits + browser AI dwell into ONE session stream (30-min gap).
  - `governance/governance.rego`: HEALTH-002 / HEALTH-003 now cap combined AI usage (agentic + vibe-coding + browser AI).
  - Verified: `opa check` passes, `tracker --ai-usage-json` works, `verify-governance` exit-1 path confirmed with combined 24 min today.
