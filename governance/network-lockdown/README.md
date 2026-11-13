# Taskflow AI Network Lockdown (local component)

**Default state: every AI host on this machine resolves to `0.0.0.0` / `::`.**
Resolution still works for everything else: general browsing, Gmail, Docs, Search,
GitHub, package registries — resolved via your normal ISP DNS (`64.71.255.204` / `.198`),
proxied by a local sinkhole.

This is the local half of the lockdown (option **B** + the time gate of option **C**).
The network-side half — so this can't be bypassed from outside the OS — is the
**D plan**: [`~/code/server/ai-network-egress-lockdown.md`](../../../server/ai-network-egress-lockdown.md).

Do **not** install with a running root session open to anything else: this configures
system DNS. Read `install.sh` first (it is the whole of the change).

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
- **`/etc/taskflow/ai-sinkhole.conf`** — *the toggle*. Rewritten by the helper
  (or installer) from [`ai-blocklist.txt`](ai-blocklist.txt). CLOSED = every line is
  `address=/<domain>/0.0.0.0` (+`::`); OPEN = comment-only. Reload via SIGHUP.
- **`taskflow-dnsmasq.service`** — self-contained unit running
  `/usr/sbin/dnsmasq --keep-in-foreground` with the two configs. Does NOT touch the
  distro `dnsmasq` package (only `dnsmasq-base` is installed on this machine).
- **`/usr/local/sbin/taskflow-ai-window`** — root-owned helper (0755, root:root).
  `open` refuses unless `verify-governance --check-ai-window` reports eligible
  (not curfew, practice done, no session concluded today, daily cap not reached).
  `open` then schedules a transient systemd timer (`systemd-run --on-active=7200`)
  that force-closes after 120 minutes. Manual `close` is immediate.
- **`/etc/sudoers.d/taskflow-ai-window`** — NOPASSWD for exactly that binary.
  Nothing else gets NOPASSWD; everything else still needs your sudo password.
- **systemd-resolved disabled**, `/etc/resolv.conf` frozen to `nameserver 127.0.0.1`,
  NetworkManager `rc-manager=unmanaged` + `dns=none`.

## Commands

```bash
sudo bash install.sh                # install + verify (idempotent, timestamped backups)
sudo taskflow-ai-window status      # window state + sinkhole size
sudo taskflow-ai-window open        # refused unless policy agrees; auto-closes in 120 min
sudo taskflow-ai-window close       # force-close now
sudo bash uninstall.sh              # full rollback (removes everything, restores resolved)
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
getent hosts chatgpt.com        # expect 0.0.0.0
getent hosts www.claude.ai      # expect 0.0.0.0
getent hosts google.com         # expect a real IP
sudo taskflow-ai-window status
```

## Testing performed

- `bash -n` on `install.sh` / `uninstall.sh` / `taskflow-ai-window`
- `dnsmasq --test` on the generated sinkhole config
- Unprivileged dnsmasq on `127.0.0.1:5354` built from the blocklist:
  sinkholed names return `0.0.0.0`; other names forward upstream.
- `python3 verify-governance --check-ai-window` prints eligibility JSON (exit 0).
- **Postmortem (2026-11-12):** first real install on the target machine killed ALL
  DNS — the nft rule exempted only uid 0, but dnsmasq forwards upstream as `nobody`.
  The failure mode was total (browse → nothing resolved) rather than partial, and my
  install-time check only verified the sinkhole side (0.0.0.0), never that general
  DNS still worked. Fixed both; verification now **auto-rolls back** via
  `uninstall.sh` if google.com can't be resolved after install.
