#!/bin/bash
# Taskflow AI lockdown installer — root required.
# Usage: sudo bash install.sh [window|budget]   (default: budget)
#
# MODES:
#   budget  (DEFAULT): no command exists to "enable" AI. A root systemd timer
#                     runs taskflow-ai-sink every 60s; it reads the governance
#                     verdict (practice done? under 120-min cap? single-session
#                     rule satisfied? not curfew?) and flips DNS accordingly.
#                     AI works while you have budget, dies when you run out —
#                     automatically; at 07:00 the day resets.
#   window  (legacy):  AI is DNS-sinkholed ALWAYS. The ONLY way to use AI is
#                     `sudo taskflow-ai-window open` — policy decides, and the
#                     window force-closes after 120 minutes.
#
# What BOTH modes do (with timestamped backups):
#   1. Disables systemd-resolved; freezes /etc/resolv.conf to 127.0.0.1 (local sinkhole)
#   2. NetworkManager rc-manager=unmanaged + dns=none  (can no longer rewrite resolv.conf)
#   3. Installs a SELF-CONTAINED dnsmasq (own systemd unit, own config in /etc/taskflow/)
#      on 127.0.0.1:53; upstream stays your ISP DNS (64.71.255.204 / .198)
#   4. Sinkholes ALL AI hosts when the budget is exhausted / window closed
#      (dnsmasq address=/<domain>/0.0.0.0 and ::)
#   5. nftables: every local process except uid 0 and 'nobody' is denied outbound 53/853
#      (the sinkhole itself forwards upstream as 'nobody'; uid 0 is the admin boundary)
#      -> nobody else can talk DNS, so the sinkhole cannot be bypassed.
#      If install-time verification shows general DNS is broken, the installer
#      automatically rolls EVERYTHING back (execs uninstall.sh) instead of leaving you offline.
#      Persisted via taskflow-aifirewall.service
#
set -euo pipefail

MODE="${1:-budget}"
case "$MODE" in
  window|budget) ;;
  *) echo "usage: sudo bash install.sh [window|budget]   (default: budget)" >&2; exit 2 ;;
esac

[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash install.sh [window|budget]"; exit 2; }

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TS=$(date +%Y%m%d-%H%M%S)
echo "== taskflow :: AI LOCKDOWN INSTALL ($TS)"

echo "== [1/9] backing up resolv.conf and NM conf"
cp -a /etc/resolv.conf "/etc/resolv.conf.taskflow-$TS.bak" 2>/dev/null || true
cp -a /etc/NetworkManager/conf.d "/etc/NetworkManager/conf.d.taskflow-$TS.bak" 2>/dev/null || true

echo "== [2/9] disabling systemd-resolved, freezing /etc/resolv.conf"
systemctl disable --now systemd-resolved || true
rm -f /etc/resolv.conf
printf 'nameserver 127.0.0.1\noptions edns0\n' > /etc/resolv.conf

echo "== [3/9] NetworkManager: rc-manager=unmanaged, dns=none"
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/90-taskflow-dns.conf <<'EOF'
[main]
dns=none
rc-manager=unmanaged
EOF

echo "== [4/9] self-contained dnsmasq in /etc/taskflow + AI sinkhole (mode: $MODE)"
mkdir -p /etc/taskflow
chown root:root /etc/taskflow
chmod 0755 /etc/taskflow
cp "$SCRIPT_DIR/ai-blocklist.txt" /etc/taskflow/ai-blocklist.txt
chown root:root /etc/taskflow/ai-blocklist.txt
chmod 0644 /etc/taskflow/ai-blocklist.txt

cat > /etc/taskflow/dnsmasq-main.conf <<'EOF'
port=53
listen-address=127.0.0.1
bind-interfaces
no-resolv
# MUST match the nftables exemption in /etc/nftables/taskflow.nft:
# dnsmasq setuids to 'nobody' after binding when started as root; its upstream
# queries (64.71.255.204:53) therefore come from uid nobody.
user=nobody
server=64.71.255.204
server=64.71.255.198
cache-size=1000
EOF
chmod 0644 /etc/taskflow/dnsmasq-main.conf

if [[ "$MODE" == "budget" ]]; then
  # Budget mode: start OPEN (comment-only sinkhole). The enforcer timer closes it
  # on its first tick if the budget is exhausted — deny by default within 60s of install.
  cat > /etc/taskflow/ai-sinkhole.conf <<EOF
# AI budget available — managed by taskflow-ai-sink (auto-flips with the daily allowance). Installed $TS.
EOF
else
  {
    echo "# AI network window CLOSED (installed $TS). Managed by taskflow-ai-window."
    while IFS= read -r domain; do
      [[ -z "$domain" || "$domain" == \#* ]] && continue
      echo "address=/$domain/0.0.0.0"
      echo "address=/$domain/::"
    done < /etc/taskflow/ai-blocklist.txt
  } > /etc/taskflow/ai-sinkhole.conf
fi
# Seed state file so the enforcer treats the current file as authoritative
mkdir -p /var/lib/taskflow
if [[ "$MODE" == "budget" ]]; then echo open > /var/lib/taskflow/sink-state; else echo closed > /var/lib/taskflow/sink-state; fi
chmod 0644 /var/lib/taskflow/sink-state
chmod 0644 /etc/taskflow/ai-sinkhole.conf

echo "== [5/9] nftables: drop non-privileged DNS egress (53/853) — only the sinkhole speaks DNS"
mkdir -p /etc/nftables
NOBODY_UID=$(id -u nobody)
cat > /etc/nftables/taskflow.nft <<EOF
table inet taskflow_ai {
  chain output {
    type filter hook output priority filter; policy accept;
    oifname "lo" accept
    # dnsmasq runs its upstream forwarding as 'nobody' (user=nobody in
    # dnsmasq-main.conf); uid 0 is the admin boundary (exempt).
    meta skuid != { 0, ${NOBODY_UID} } udp dport { 53, 853 } drop
    meta skuid != { 0, ${NOBODY_UID} } tcp dport { 53, 853 } drop
  }
}
EOF

cat > /etc/systemd/system/taskflow-aifirewall.service <<'EOF'
[Unit]
Description=Taskflow AI lockdown: force DNS through local sinkhole
Documentation=file:///home/yassine/code/taskflow/governance/network-lockdown/README.md
After=network.target
[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /etc/nftables/taskflow.nft
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
/usr/sbin/nft delete table inet taskflow_ai 2>/dev/null || true
cp "$SCRIPT_DIR/taskflow-dnsmasq.service" /etc/systemd/system/taskflow-dnsmasq.service
systemctl daemon-reload
systemctl enable --now taskflow-aifirewall.service
systemctl enable --now taskflow-dnsmasq.service

if [[ "$MODE" == "budget" ]]; then
  echo "== [6/9] budget enforcer: taskflow-ai-sink + 60s timer (no sudoers, no open command)"
  cp "$SCRIPT_DIR/taskflow-ai-sink" /usr/local/sbin/taskflow-ai-sink
  chown root:root /usr/local/sbin/taskflow-ai-sink
  chmod 0755 /usr/local/sbin/taskflow-ai-sink
  cp "$SCRIPT_DIR/taskflow-ai-sink.service" /etc/systemd/system/taskflow-ai-sink.service
  cp "$SCRIPT_DIR/taskflow-ai-sink.timer" /etc/systemd/system/taskflow-ai-sink.timer
  chmod 0644 /etc/systemd/system/taskflow-ai-sink.service /etc/systemd/system/taskflow-ai-sink.timer
  systemctl daemon-reload
  systemctl enable --now taskflow-ai-sink.timer
else
  echo "== [6/9] window helper: root taskflow-ai-window + sudoers NOPASSWD (helper only)"
  cp "$SCRIPT_DIR/taskflow-ai-window" /usr/local/sbin/taskflow-ai-window
  chown root:root /usr/local/sbin/taskflow-ai-window
  chmod 0755 /usr/local/sbin/taskflow-ai-window
  cat > /etc/sudoers.d/taskflow-ai-window <<'EOF'
yassine ALL=(root) NOPASSWD: /usr/local/sbin/taskflow-ai-window
EOF
  chmod 0440 /etc/sudoers.d/taskflow-ai-window
  visudo -cf /etc/sudoers.d/taskflow-ai-window || { rm -f /etc/sudoers.d/taskflow-ai-window; echo "sudoers validation failed, removed it."; exit 1; }
  systemctl daemon-reload
fi

echo "== [7/9] restarting NetworkManager"
systemctl restart NetworkManager
sleep 2

# Budget mode: apply the verdict synchronously so the install's end-state is consistent
if [[ "$MODE" == "budget" ]]; then
  /usr/local/sbin/taskflow-ai-sink enforce || true
fi

echo "== [8/9] verification"
ai_result=$(getent ahostsv4 chatgpt.com | awk '{print $1; exit}')
web_result=$(getent ahostsv4 google.com | awk '{print $1; exit}')
echo "  chatgpt.com -> ${ai_result:-<no answer>}"
echo "  google.com  -> ${web_result:-<no answer>}  (expect a real IP)"
rollback() {
  echo "!!! $1"
  echo "!!! Auto-rolling back NOW so DNS is never left broken."
  exec bash "$SCRIPT_DIR/uninstall.sh"
}
# An install that blocks the general web is a failed install — roll back automatically.
if [[ -z "$web_result" || "$web_result" == "0.0.0.0" ]]; then
  rollback "GENERAL DNS BROKEN (google.com -> ${web_result:-no answer})."
fi
if [[ "$MODE" == "window" && "$ai_result" != "0.0.0.0" ]]; then
  rollback "AI sinkhole did not take effect (chatgpt.com -> ${ai_result:-no answer})."
fi
if [[ "$MODE" == "budget" ]]; then
  /usr/local/sbin/taskflow-ai-sink status 2>/dev/null | head -1 || true
fi

echo "== [9/9] done."
if [[ "$MODE" == "budget" ]]; then
  echo "  AI hereafter flips automatically with your daily budget — NO command to enable it."
  echo "  Opens when:  practice done today AND under the 120-min cap AND today's single"
  echo "              session has not concluded AND not in curfew (23:00-07:00)."
  echo "  Close now:   sudo taskflow-ai-sink close   (emergency stop)"
  echo "  Status:      taskflow-ai-sink status"
else
  echo "  open AI window:  sudo taskflow-ai-window open     (refused unless policy allows; auto-closes in 120 min)"
  echo "  close now:       sudo taskflow-ai-window close"
  echo "  status:          sudo taskflow-ai-window status"
fi
echo "  D-plan (router): ~/code/server/ai-network-egress-lockdown.md"
echo "  uninstall:       sudo bash $SCRIPT_DIR/uninstall.sh"
