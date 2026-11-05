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
            "DEEP_WORK": {"domains": ["github.com", "docs.rs", "arxiv.org"], "paths": ["/home/yassine/code"]}
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
        # If category transitioned from REST to DEEP_WORK, upgrade summary
        if state.get("category") != category and category in ["PRACTICE", "DEEP_WORK"]:
            state["category"] = category
            state["summary"] = summary
        save_state(state)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--status":
        st = load_state()
        print("Tracker State:", json.dumps(st, indent=2) if st else "No active session")
    else:
        pulse()
