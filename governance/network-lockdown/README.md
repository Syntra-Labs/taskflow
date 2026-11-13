# Taskflow AI Network Lockdown (local component)

**Default mode: `budget` — you never run a command to "enable" AI. It just works while
your daily allowance lasts, then stops working.** AI hosts resolve to `0.0.0.0` / `::`
automatically when the budget is spent (or practice isn't done yet today, or it's curfew,
or today's single AI session has concluded), and resolve again when the day resets.

This is the local half of the lockdown (option **B** + the time gate of option **C**).
The network-side half — so this can't be bypassed from outside the OS — is the
**D plan**: [`~/code/server/ai-network-egress-lockdown.md`](../../../server/ai-network-egress-lockdown.md).

Do **not** install with a running root session open to anything else: this configures
system DNS. Read `install.sh` first (it is the whole of the change).

## The two modes

|                | **budget** (default)                        | **window** (legacy, explicit)        |
|----------------|---------------------------------------------|--------------------------------------|
| Enabling AI    | nothing to run — opens automatically        | `sudo taskflow-ai-window open`       |
| Closing AI     | automatic, every 60 s, from policy verdict  | automatic after 120 min or manual `close` |
| Gate logic     | practice done ∧ under 120 min/day ∧ single-session rule ∧ not curfew | same, checked at `open` time only |
| Best fit      | "AI whenever allowed, automatically"          | "explicit, deliberate opt-in only"  |

Budget mode install: `sudo bash install.sh` (or `sudo bash install.sh budget`).
Window mode install: `sudo bash install.sh window`.

## Architecture

```
browser / CLI / editor agents / anything ──DNS──► dnsmasq @ 127.0.0.1:53
  (any non-root uid)                                 │
                          ┌──────────────────────────┴───────────────┐
                          │ window CLOSED (default)                  │
                          │  /etc/taskflow/ai-sinkhole.conf:         │
                          │  address=/<ai-domain>/0.0.0.0  (+ ::)    │
                          │                                          │
                          │ window OPEN (max 120 min, policy-gated)  │
                          │  ai-sinkhole.conf reduced to a comment   │
                          └──────────────────────────────────────────┘
                                                       │
                                                upstream ISP DNS

nftables `taskflow_ai` (loaded by taskflow-aifirewall.service at boot):
  `oifname != "lo"` AND `meta skuid != { 0, <nobody-uid> }` AND dport { 53, 853 } → drop
  (nobody's uid is resolved at install time and baked into the ruleset)
  ⇒ only uid 0 (admin) and 'nobody' (the sinkhole's upstream-forwarding uid, set via
    user=nobody in dnsmasq-main.conf) may talk DNS. Anyone else is dropped,
    so hardcoding 8.8.8.8/1.1.1.1 does nothing.
  Note: an earlier version exempted only uid 0, assuming the sinkhole forwarded
    upstream as root — dnsmasq setuids to nobody by default, which killed ALL DNS.
    Fixed (explicit user=nobody + matching nft exemption), and the installer now
    auto-rolls-back if post-install verification can't resolve google.com.
```

- **`/etc/taskflow/dnsmasq-main.conf`** — static config (port 53, loopback-only,
  upstream ISP DNS, cache).
- **`/etc/taskflow/ai-sinkhole.conf`** — *the toggle*. Rewritten by the enforcer
  (budget mode), the helper (window mode), or the installer.
  CLOSED = every line is `address=/<domain>/0.0.0.0` (+`::`); OPEN = comment-only. Reload via SIGHUP.
- **`taskflow-dnsmasq.service`** — self-contained unit running
  `/usr/sbin/dnsmasq --keep-in-foreground` with the two configs. Does NOT touch the
  distro `dnsmasq` package (only `dnsmasq-base` is installed on this machine).
- **`/usr/local/sbin/taskflow-ai-sink` + `taskflow-ai-sink.timer`** (budget mode) — the
  root decision engine. Every 60 s the timer runs `taskflow-ai-sink enforce`, which
  reads `verify-governance --check-ai-budget` (practice done? daily <120 min? today's
  single session rules? not curfew?) and flips the sinkhole to match. No command can
  open AI — it is policy-driven and fails closed. Emergency stop: `sudo taskflow-ai-sink close`.
  Root reads yassine's repos and caches by injecting `HOME=/home/yassine` and
  `GIT_CONFIG_*` safe.directory (git's dubious-ownership check would otherwise lock it out).
- **`/usr/local/sbin/taskflow-ai-window`** (window mode only) — root-owned helper (0755).
  `open` refuses unless `verify-governance --check-ai-window` reports eligible
  (not curfew, practice done, no session concluded today, daily cap not reached).
  `open` then schedules a transient systemd timer (`systemd-run --on-active=7200`)
  that force-closes after 120 minutes. Manual `close` is immediate.
- **`/etc/sudoers.d/taskflow-ai-window`** (window mode only) — NOPASSWD for exactly that binary.
- **systemd-resolved disabled**, `/etc/resolv.conf` frozen to `nameserver 127.0.0.1`,
  NetworkManager `rc-manager=unmanaged` + `dns=none`.

## Commands

```bash
# budget mode (default)
sudo bash install.sh                # install budget mode (idempotent, backups, auto-rollback)
sudo bash install.sh window         # install window mode instead
taskflow-ai-sink status             # current state + live policy verdict
sudo taskflow-ai-sink close         # emergency stop (nothing can re-open it but policy)

# window mode only
sudo taskflow-ai-window status
sudo taskflow-ai-window open        # refused unless policy agrees; auto-closes in 120 min
sudo taskflow-ai-window close

sudo bash uninstall.sh              # full rollback (either mode; restores resolved)
```

## What it covers

Every AI chat / assistant / inference API listed in `ai-blocklist.txt`, **from any
non-root process** — Firefox, curl, python, node, editors, agents. Subdomains of
sinkholed domains are sinkholed too (dnsmasq matches suffix).

## Known limitations (closed by D, not by local rules)

1. **Direct-IP DoH/DoT**: HTTPS to a DoH resolver bypasses DNS filtering entirely.
   Mitigation (D): block DoH/DoT at the router/VPN edge.
2. **uids 0 and `nobody` are exempt** from the 53/853 drop (the sinkhole itself
   forwards upstream as `nobody`; uid 0 is the admin boundary). Local policy cannot
   police root — D moves the boundary off-box. Also note `nobody` being exempt means
   any process that can run as `nobody` could talk DNS — nobody is the system daemon
   user, not your regular account, so this is the intended minimum exemption.
3. **GitHub Copilot**: path-specific web traffic (`github.com/.../copilot`) can't be
   DNS-filtered; the independent Copilot API hosts (`copilot.github.com`,
   `githubcopilot.com`) are blocked.
4. **Shared-CDN AI features** on non-sinkholed apex domains (e.g. Gemini inside
   products hosted on generic Google endpoints) may leak.
5. Local rules are removable by root. By design this is enforcement for the
   *machine acting for you*, not a trust anchor — see the D plan.
6. **Fail-safe direction**: if `taskflow-dnsmasq` dies, all DNS fails — you notice
   immediately instead of silently bypassing policy.

## Verification after install

```bash
getent hosts chatgpt.com        # budget mode: 0.0.0.0 once budget is spent mid-day;
                                # window mode: always 0.0.0.0
getent hosts www.claude.ai      # same rule
getent hosts openrouter.ai      # same rule
getent hosts google.com         # expect a real IP
taskflow-ai-sink status         # budget mode: current state + live verdict
```

## Testing performed

- `bash -n` on `install.sh` / `uninstall.sh` / `taskflow-ai-sink` / `taskflow-ai-window`
- `dnsmasq --test` on generated configs (open and closed sinkhole)
- Unprivileged dnsmasq sinkhole test; plus a sandboxed enforcer rehearsal:
  flip open → closed on a closed verdict, no flip when policy stays open,
  corrupted state converges to the verdict on the next minute.
- `python3 verify-governance --check-ai-budget` prints verdict JSON (exit 0),
  including under root-equivalent env injection (`HOME=/home/yassine` +
  `GIT_CONFIG_SAFE_DIRECTORY`).
- **The root path has not been executed end-to-end on a live machine.** The very first
  `sudo bash install.sh` is its own test: if verification finds google.com broken,
  it execs `uninstall.sh` and you are back online. Budget-mode failure direction is
  "AI stays blocked", never "AI opens silently".
- **Postmortem (2026-11-12):** first real install on the target machine killed ALL
  DNS — the nft rule exempted only uid 0, but dnsmasq forwards upstream as `nobody`.
  The failure mode was total (browse → nothing resolved) rather than partial, and my
  install-time check only verified the sinkhole side (0.0.0.0), never that general
  DNS still worked. Fixed both; verification now **auto-rolls back** via
  `uninstall.sh` if google.com can't be resolved after install.
