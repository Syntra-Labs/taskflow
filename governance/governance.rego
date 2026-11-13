package policy.governance

import rego.v1

default allow := false

# =========================================================================
# 1. HEALTH & SLEEP CURFEW (23:00 to 07:00)
# Sleep is non-negotiable. Pushing through the night leads to physical collapse.
# =========================================================================
deny contains msg if {
    hour := input.current_hour
    hour >= 23
    msg := sprintf("HEALTH-001: Curfew active (%d:00 >= 23:00). Commits and agentic tools blocked. Sleep and rest are non-negotiable. Step away from the computer.", [hour])
}

deny contains msg if {
    hour := input.current_hour
    hour < 7
    msg := sprintf("HEALTH-001: Curfew active (%d:00 < 07:00). Commits and agentic tools blocked. Sleep and rest are non-negotiable. Step away from the computer.", [hour])
}

# =========================================================================
# 2. TWO-BLOCK DAILY BUDGET (60 min, 2-hour silence, 60 min — 120 min/day)
# Counts ALL AI usage: agentic tool execution, vibe coding, AND browser AI.
# The first block is 60 minutes. Block two opens only after >= 120 minutes
# with NO AI events of any kind. Default deny when the cooldown has not elapsed.
# =========================================================================
deny contains msg if {
    session_minutes := input.session_minutes
    session_minutes > 120
    msg := sprintf("HEALTH-002: Daily AI session limit reached (%d min / 120 min max) — agentic + browser AI combined. You have used your 2-hour AI session for today. Step away and rest.", [session_minutes])
}

deny contains msg if {
    daily := input.daily_project_minutes
    daily >= 60
    daily < 120
    not input.minutes_since_last_ai_event >= 120
    msg := sprintf("HEALTH-002C: First 60-minute AI block spent (%d min used). The second block opens only after 120 minutes with zero AI usage — not one tool call, message, or page view. Log off. Session 2 begins at least 2 hours after your last AI event.", [daily])
}

# =========================================================================
# 3. DAILY AI CAP (Max 120 min / 2 hours per day)
# Counts ALL AI usage: agentic + vibe-coding + browser AI.
# =========================================================================
deny contains msg if {
    daily_minutes := input.daily_project_minutes
    daily_minutes > 120
    msg := sprintf("HEALTH-003: Daily AI cap exceeded (%d min / 120 min max) — agentic + browser AI combined. All AI tools blocked until 7:00 AM reset.", [daily_minutes])
}

# =========================================================================
# 4. DAILY PRACTICE REQUIREMENT (LeetCode or ~/code/practice)
# Practice comes before hacking on complex projects.
# =========================================================================
deny contains msg if {
    input.project != "practice"
    input.daily_exercises_done == 0
    msg := "PRACTICE-001: Daily coding exercise incomplete! Solve an exercise on LeetCode (wwwportal), Codeforces (YassineAmraoui), Deep-ML, or in ~/code/practice before committing to other projects today."
}

format_timestamp(ts) := time.format(ts)

allow if {
    count(deny) == 0
}
