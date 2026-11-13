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
# 2. SINGLE SESSION LIMIT (Max 1 session of 120 minutes / 2 hours per day)
# Only agentic usage, tool calling, and vibe-coding count.
# Normal AI usage (chat, advice, explanations) does not count against this.
# =========================================================================
deny contains msg if {
    session_minutes := input.session_minutes
    session_minutes > 120
    msg := sprintf("HEALTH-002: Daily session limit reached (%d min / 120 min max). You have completed your 2-hour agentic session for today. Step away and rest.", [session_minutes])
}

deny contains msg if {
    input.sessions_completed >= 1
    not input.in_active_session
    msg := "HEALTH-002B: Single daily session limit reached. Policy allows only a single agentic / vibe-coding session (max 2 hours) per day. Today's session has already concluded."
}

# =========================================================================
# 3. DAILY AGENTIC & VIBE-CODING CAP (Max 120 min / 2 hours per day)
# =========================================================================
deny contains msg if {
    daily_minutes := input.daily_project_minutes
    daily_minutes > 120
    msg := sprintf("HEALTH-003: Daily agentic & vibe-coding cap exceeded (%d min / 120 min max). Agentic tools blocked until 7:00 AM reset.", [daily_minutes])
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
