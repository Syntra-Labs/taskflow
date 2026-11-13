#!/usr/bin/env python3
"""
Minimal Activity & Focus Tracker
Captures presence (GNOME idle), active terminal/workspace, and Chrome activity.
Logs completed sustained focus blocks directly to Google Calendar via gws.
"""

import json
import os
import shutil
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timedelta

TRACKER_DIR = os.path.dirname(os.path.abspath(__file__))
RULES_FILE = os.path.join(TRACKER_DIR, "rules.json")
STATE_FILE = os.path.expanduser("~/.config/taskflow/active_session.json")
CHROME_HISTORY = os.path.expanduser("~/.config/google-chrome/Default/History")

CHROME_EPOCH_OFFSET = 11644473600  # seconds between 1601-01-01 (Chrome) and 1970-01-01 (Unix)
AI_USAGE_CACHE_FILE = os.path.expanduser("~/.config/taskflow/ai_usage_cache.json")
AI_USAGE_CACHE_TTL = 60  # seconds

def load_rules():
    if os.path.exists(RULES_FILE):
        try:
            with open(RULES_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {
        "categories": {
            "PRACTICE": {"domains": ["leetcode.com", "codeforces.com", "deep-ml.com"], "paths": ["/home/yassine/code/practice"]},
            "DEEP_WORK_CORE": {"domains": ["github.com", "docs.rs"], "paths": ["/home/yassine/code"]},
            "AI_USE": {"domains": ["chatgpt.com", "chat.openai.com", "claude.ai", "gemini.google.com", "deepseek.com", "grok.com", "copilot.microsoft.com", "copilot.github.com", "github.com/copilot", "perplexity.ai", "poe.com", "mistral.ai"]}
        },
        "min_block_minutes": 15,
        "idle_threshold_seconds": 600
    }

def get_idle_seconds():
    try:
        out = subprocess.check_output(
            ["gdbus", "call", "--session", "--dest", "org.gnome.Mutter.IdleMonitor",
             "--object-path", "/org/gnome/Mutter/IdleMonitor/Core",
             "--method", "org.gnome.Mutter.IdleMonitor.GetIdletime"],
            stderr=subprocess.DEVNULL,
            text=True
        ).strip()
        # Output format: (uint64 12345,) where 12345 is ms
        parts = out.split()
        if len(parts) >= 2:
            ms_str = parts[1].rstrip(",)")
            return int(ms_str) // 1000
    except Exception:
        pass
    return 0

def is_chrome_running():
    try:
        subprocess.check_output(["pgrep", "-x", "chrome"],
                                stderr=subprocess.DEVNULL)
        return True
    except Exception:
        return False

def load_ai_domains(rules=None):
    if rules is None:
        rules = load_rules()
    domains = rules.get("categories", {}).get("AI_USE", {}).get("domains", [])
    return [d.lower() for d in domains]

def is_ai_url(url, ai_domains):
    if not url:
        return False
    u = url.lower()
    return any(d in u for d in ai_domains)

def chrome_visits_since(since_unix_ts):
    """Return [(unix_ts, url, title), ...] of Chrome visits since since_unix_ts, sorted."""
    if not os.path.exists(CHROME_HISTORY):
        return []
    tmp_db = "/tmp/tf_chrome_visits.db"
    try:
        shutil.copy2(CHROME_HISTORY, tmp_db)
        conn = sqlite3.connect(tmp_db)
        c = conn.cursor()
        since = (since_unix_ts + CHROME_EPOCH_OFFSET) * 1_000_000
        c.execute("""
            SELECT v.visit_time, u.url, u.title
            FROM visits v JOIN urls u ON u.id = v.url
            WHERE v.visit_time >= ?
            ORDER BY v.visit_time ASC
        """, (since,))
        rows = c.fetchall()
        conn.close()
        return [((int(vt) // 1_000_000) - CHROME_EPOCH_OFFSET, url, title or "")
                for vt, url, title in rows]
    except Exception:
        return []
    finally:
        try:
            os.remove(tmp_db)
        except Exception:
            pass

def governance_day_start_ts():
    """Governance day starts at 7:00 AM, not calendar midnight."""
    now = datetime.now()
    if now.hour >= 7:
        gov_start = now.replace(hour=7, minute=0, second=0, microsecond=0)
    else:
        gov_start = (now - timedelta(days=1)).replace(hour=7, minute=0, second=0, microsecond=0)
    return int(gov_start.timestamp())


def get_ai_segments():
    """Return raw AI dwell segments [(start_ts, end_ts), ...] for the current governance day.

    Dwell time for each visit is attributed to the next navigation timestamp.
    The trailing segment (page currently open) is extended to now - idle_seconds,
    but only if Chrome is actually running. Each segment is capped at 30 minutes.
    """
    now_ts = int(time.time())
    rules = load_rules()
    ai_domains = load_ai_domains(rules)
    idle_sec = get_idle_seconds()
    chrome_running = is_chrome_running()

    gov_start_ts = governance_day_start_ts()
    visits = chrome_visits_since(gov_start_ts)

    MAX_SEGMENT_SECONDS = 30 * 60
    segments = []  # (start_ts, end_ts, url)
    for i, (ts, url, _title) in enumerate(visits):
        if i + 1 < len(visits):
            nxt = visits[i + 1][0]
        else:
            if chrome_running:
                nxt = now_ts - idle_sec
            else:
                nxt = ts  # browser closed: no dwell attribution for the tail
        dwell = min(MAX_SEGMENT_SECONDS, max(0, nxt - ts))
        if dwell > 0:
            segments.append((ts, ts + dwell, url))

    ai_segments = [(s, e) for s, e, u in segments if is_ai_url(u, ai_domains)]
    ai_segments.sort(key=lambda s: s[0])
    return ai_segments


def get_ai_usage_report():
    """Reconstruct AI usage dwell segments from Chrome visits for the current governance day.

    The trailing segment (page currently open) is extended to now - idle_seconds,
    but only if Chrome is actually running. Cached for AI_USAGE_CACHE_TTL seconds.
    """
    now_ts = int(time.time())
    now = datetime.now()
    if now.hour >= 7:
        day_str = now.strftime("%Y-%m-%d")
    else:
        day_str = (now - timedelta(days=1)).strftime("%Y-%m-%d")

    # Cache hit?
    try:
        if os.path.exists(AI_USAGE_CACHE_FILE):
            with open(AI_USAGE_CACHE_FILE, "r") as f:
                cdata = json.load(f)
            if cdata.get("date") == day_str and (now_ts - cdata.get("calced_at", 0)) <= AI_USAGE_CACHE_TTL:
                return cdata
    except Exception:
        pass

    rules = load_rules()
    idle_limit = rules.get("idle_threshold_seconds", 600)
    _ = idle_limit

    ai_segments = get_ai_segments()

    # AI segments; sessions clustered by a 30-minute gap (same as the rest of the system).
    GAP = 30 * 60
    sessions = []
    cur = None
    for s, e in ai_segments:
        if cur is None or (s - cur[1]) > GAP:
            if cur is not None:
                sessions.append(cur)
            cur = [s, e]
        else:
            cur[1] = max(cur[1], e)
    if cur is not None:
        sessions.append(cur)

    ai_daily_minutes = 0
    for sess in sessions:
        span = max(0, sess[1] - sess[0])
        ai_daily_minutes += span / 60.0
    ai_daily_minutes = int(ai_daily_minutes)

    ai_session_minutes = 0
    ai_last_session_end = None
    ai_sessions_completed = 0
    ai_in_active_session = False

    if sessions:
        last = sessions[-1]
        if (now_ts - last[1]) <= GAP:
            ai_in_active_session = True
            ai_session_minutes = max(1, (now_ts - last[0]) // 60)
            ai_sessions_completed = len(sessions) - 1
            ai_last_session_end = sessions[-2][1] if len(sessions) > 1 else None
        else:
            ai_in_active_session = False
            ai_sessions_completed = len(sessions)
            ai_last_session_end = last[1]

    report = {
        "date": day_str,
        "ai_daily_minutes": ai_daily_minutes,
        "ai_session_minutes": ai_session_minutes,
        "ai_last_session_end": ai_last_session_end,
        "ai_sessions_completed": ai_sessions_completed,
        "ai_in_active_session": ai_in_active_session,
        "ai_segment_count": len(ai_segments),
        "calced_at": now_ts
    }

    try:
        with open(AI_USAGE_CACHE_FILE, "w") as f:
            json.dump(report, f)
    except Exception:
        pass

    return report

def get_latest_browser_activity():
    if not os.path.exists(CHROME_HISTORY):
        return None, None
    tmp_db = "/tmp/tf_chrome_history.db"
    try:
        shutil.copy2(CHROME_HISTORY, tmp_db)
        conn = sqlite3.connect(tmp_db)
        c = conn.cursor()
        c.execute("SELECT url, title, last_visit_time FROM urls ORDER BY last_visit_time DESC LIMIT 1")
        row = c.fetchone()
        conn.close()
        if os.path.exists(tmp_db):
            os.remove(tmp_db)
        if row:
            url, title, _ = row
            return url, title
    except Exception:
        if os.path.exists(tmp_db):
            try:
                os.remove(tmp_db)
            except Exception:
                pass
    return None, None

def classify_activity(url, title, cwd, rules):
    categories = rules.get("categories", {})
    url_lower = (url or "").lower()
    title_lower = (title or "").lower()
    cwd_lower = (cwd or "").lower()

    # Check AI_USE (browser AI chat & assistants) — counts against AI usage budget
    ai = categories.get("AI_USE", {})
    for d in ai.get("domains", []):
        if d in url_lower:
            return "AI_USE", f"AI Usage: {title or d}"

    # Check PRACTICE
    prac = categories.get("PRACTICE", {})
    for d in prac.get("domains", []):
        if d in url_lower:
            return "PRACTICE", f"Practice: {title or d}"
    for p in prac.get("paths", []):
        if p in cwd_lower:
            return "PRACTICE", f"Practice in {os.path.basename(p)}"

    # Check DEEP_WORK_CORE
    deep_core = categories.get("DEEP_WORK_CORE", {})
    for d in deep_core.get("domains", []):
        if d in url_lower:
            proj = "Syntra-Labs" if "syntra-labs" in url_lower else "Core Eng"
            return "DEEP_WORK_CORE", f"Deep Work (Core): {title or proj}"
    for p in deep_core.get("paths", []):
        if p in cwd_lower:
            proj = os.path.basename(cwd)
            return "DEEP_WORK_CORE", f"Deep Work (Core): {proj}"

    # Check DEEP_WORK_ACADEMIC (Schoolwork / College)
    academic = categories.get("DEEP_WORK_ACADEMIC", {})
    for d in academic.get("domains", []):
        if d in url_lower:
            return "DEEP_WORK_ACADEMIC", f"Academic Study: {title or 'Schoolwork'}"
    for p in academic.get("paths", []):
        if p in cwd_lower:
            return "DEEP_WORK_ACADEMIC", f"Academic Study: {os.path.basename(cwd)}"

    # Check REST
    rest = categories.get("REST", {})
    for d in rest.get("domains", []):
        if d in url_lower:
            return "REST", f"Rest / Leisure: {title or d}"

    return "OTHER", title or "Working"

def get_current_cwd():
    # Check active shells or fallback to HOME
    try:
        out = subprocess.check_output(
            ["pgrep", "-u", os.environ.get("USER", "yassine"), "-x", "bash"],
            text=True
        ).strip().splitlines()
        if out:
            latest_pid = out[-1]
            return os.path.realpath(f"/proc/{latest_pid}/cwd")
    except Exception:
        pass
    return os.path.expanduser("~")

def load_state():
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return None

def save_state(state):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

def log_to_calendar(session):
    start_ts = session["start_ts"]
    end_ts = session["last_active_ts"]
    duration_min = (end_ts - start_ts) // 60
    if duration_min < 15:
        # Ignore micro-sessions
        return

    start_dt = datetime.fromtimestamp(start_ts)
    end_dt = datetime.fromtimestamp(end_ts)
    start_str = start_dt.strftime("%Y-%m-%dT%H:%M:00-05:00")
    end_str = end_dt.strftime("%Y-%m-%dT%H:%M:00-05:00")

    summary = session.get("summary", "Focus Session")
    category = session.get("category", "DEEP_WORK")
    desc = f"Logged automatically by taskflow activity tracker.\nCategory: {category}\nDuration: {duration_min} minutes."

    event_data = {
        "summary": summary,
        "description": desc,
        "start": {"dateTime": start_str, "timeZone": "America/Toronto"},
        "end": {"dateTime": end_str, "timeZone": "America/Toronto"}
    }

    try:
        subprocess.run(
            ["gws", "calendar", "events", "insert",
             "--params", json.dumps({"calendarId": "primary"}),
             "--body", json.dumps(event_data)],
            capture_output=True,
            text=True,
            timeout=10
        )
        print(f"📅 Logged to Google Calendar: {summary} ({duration_min} min)")
    except Exception as e:
        print(f"Failed to log to calendar: {e}", file=sys.stderr)

def pulse():
    rules = load_rules()
    idle_sec = get_idle_seconds()
    now_ts = int(time.time())
    idle_limit = rules.get("idle_threshold_seconds", 600)

    url, title = get_latest_browser_activity()
    cwd = get_current_cwd()
    category, summary = classify_activity(url, title, cwd, rules)

    state = load_state()

    # Case 1: User is currently idle (taking a break)
    if idle_sec > idle_limit:
        if state and state.get("active"):
            # Session just concluded
            state["active"] = False
            save_state(state)
            log_to_calendar(state)
        return

    # Case 2: User is active
    if not state or not state.get("active"):
        # Start new session
        new_state = {
            "active": True,
            "category": category,
            "summary": summary,
            "start_ts": now_ts,
            "last_active_ts": now_ts
        }
        save_state(new_state)
    else:
        # Update existing session
        state["last_active_ts"] = now_ts
        # If category transitioned into a productive/AI category, upgrade summary
        prod_prefixes = ("PRACTICE", "DEEP_WORK", "AI_USE")
        if state.get("category") != category and category.startswith(prod_prefixes):
            state["category"] = category
            state["summary"] = summary
        save_state(state)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--status":
        st = load_state()
        print("Tracker State:", json.dumps(st, indent=2) if st else "No active session")
        print("AI Usage (governance day):", json.dumps(get_ai_usage_report(), indent=2))
    elif len(sys.argv) > 1 and sys.argv[1] == "--ai-usage-json":
        print(json.dumps(get_ai_usage_report()))
    else:
        pulse()
