#!/bin/bash
# Taskflow AI lockdown installer — root required.
#
# What it does (idempotent, with timestamped backups):
#   1. Disables systemd-resolved; freezes /etc/resolv.conf to 127.0.0.1 (local sinkhole)
#   2. NetworkManager rc-manager=unmanaged + dns=none  (can no longer rewrite resolv.conf)
#   3. Installs a SELF-CONTAINED dnsmasq (own systemd unit, own config in /etc/taskflow/)
#      on 127.0.0.1:53; upstream stays your ISP DNS (64.71.255.204 / .198)
#   4. Sinkholes ALL AI hosts by default (dnsmasq address=/<domain>/0.0.0.0 and ::)
#   5. nftables: every local process except uid 0 and 'nobody' is denied outbound 53/853
#      (the sinkhole itself forwards upstream as 'nobody'; uid 0 is the admin boundary)
#      -> nobody else can talk DNS, so the sinkhole cannot be bypassed.
#      If install-time verification shows general DNS is broken, the installer
#      automatically rolls EVERYTHING back (execs uninstall.sh) instead of leaving you offline.
#      Persisted via taskflow-aifirewall.service
#   6. Installs root-owned helper `taskflow-ai-window` + sudoers NOPASSWD entry for it ONLY
#   7. Enables taskflow-dnsmasq + firewall unit + restarts NetworkManager
#   8. Verifies one AI host (expect 0.0.0.0) and one normal host (expect a real IP)
#
# The ONLY way to lift the AI block is `sudo taskflow-ai-window open`, which
# refuses unless verify-governance reports you eligible (curfew/practice/session/cap)
# and force-closes after 120 minutes.
#
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash install.sh"; exit 2; }

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

echo "== [4/9] self-contained dnsmasq in /etc/taskflow + AI sinkhole (default closed)"
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

{
  echo "# AI network window CLOSED (installed $TS). Managed by taskflow-ai-window."
  while IFS= read -r domain; do
    [[ -z "$domain" || "$domain" == \#* ]] && continue
    echo "address=/$domain/0.0.0.0"
    echo "address=/$domain/::"
  done < /etc/taskflow/ai-blocklist.txt
} > /etc/taskflow/ai-sinkhole.conf
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

echo "== [6/9] root helper + sudoers NOPASSWD (helper only)"
cp "$SCRIPT_DIR/taskflow-ai-window" /usr/local/sbin/taskflow-ai-window
chown root:root /usr/local/sbin/taskflow-ai-window
chmod 0755 /usr/local/sbin/taskflow-ai-window
cat > /etc/sudoers.d/taskflow-ai-window <<'EOF'
yassine ALL=(root) NOPASSWD: /usr/local/sbin/taskflow-ai-window
EOF
chmod 0440 /etc/sudoers.d/taskflow-ai-window
visudo -cf /etc/sudoers.d/taskflow-ai-window || { rm -f /etc/sudoers.d/taskflow-ai-window; echo "sudoers validation failed, removed it."; exit 1; }

echo "== [7/9] restarting NetworkManager"
systemctl restart NetworkManager
sleep 2

echo "== [8/9] verification"
ai_result=$(getent ahostsv4 chatgpt.com | awk '{print $1; exit}')
web_result=$(getent ahostsv4 google.com | awk '{print $1; exit}')
echo "  chatgpt.com -> ${ai_result:-<no answer>}   (expect 0.0.0.0)"
echo "  google.com  -> ${web_result:-<no answer>}  (expect a real IP)"
rollback() {
  echo "!!! $1"
  echo "!!! Auto-rolling back NOW so DNS is never left broken."
  exec bash "$SCRIPT_DIR/uninstall.sh"
}
# An install that blocks the general web is a failed install — roll back automatically.
if [[ "$ai_result" != "0.0.0.0" ]]; then
  rollback "AI sinkhole did not take effect (chatgpt.com -> ${ai_result:-no answer})."
fi
if [[ -z "$web_result" || "$web_result" == "0.0.0.0" ]]; then
  rollback "GENERAL DNS BROKEN (google.com -> ${web_result:-no answer})."
fi

echo "== [9/9] done."
echo "  open AI window:  sudo taskflow-ai-window open     (refused unless policy allows; auto-closes in 120 min)"
echo "  close now:       sudo taskflow-ai-window close"
echo "  status:          sudo taskflow-ai-window status"
echo "  D-plan (router): ~/code/server/ai-network-egress-lockdown.md"
echo "  uninstall:       sudo bash $SCRIPT_DIR/uninstall.sh"
