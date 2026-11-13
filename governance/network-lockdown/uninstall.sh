#!/bin/bash
# Taskflow AI lockdown uninstaller — root required. Restores pre-install state.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash uninstall.sh"; exit 2; }

echo "== taskflow :: AI LOCKDOWN UNINSTALL"

echo "== removing firewall unit + nft table"
systemctl disable --now taskflow-aifirewall.service 2>/dev/null || true
rm -f /etc/systemd/system/taskflow-aifirewall.service
nft delete table inet taskflow_ai 2>/dev/null || true
rm -f /etc/nftables/taskflow.nft

echo "== removing sinkhole dnsmasq unit + config"
systemctl disable --now taskflow-dnsmasq.service 2>/dev/null || true
systemctl disable --now taskflow-ai-window-close.service 2>/dev/null || true
rm -f /etc/systemd/system/taskflow-dnsmasq.service
rm -rf /etc/taskflow

echo "== removing helper + sudoers entry"
rm -f /usr/local/sbin/taskflow-ai-window
rm -f /usr/local/sbin/taskflow-ai-sink
rm -f /etc/sudoers.d/taskflow-ai-window

echo "== removing budget-enforcer units + state"
systemctl disable --now taskflow-ai-sink.timer 2>/dev/null || true
systemctl disable --now taskflow-ai-sink.service 2>/dev/null || true
rm -f /etc/systemd/system/taskflow-ai-sink.service /etc/systemd/system/taskflow-ai-sink.timer

echo "== removing logs + state dir"
rm -rf /var/lib/taskflow /var/log/taskflow

echo "== restoring /etc/resolv.conf handling + NetworkManager"
rm -f /etc/NetworkManager/conf.d/90-taskflow-dns.conf
rm -f /etc/resolv.conf
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

echo "== re-enabling systemd-resolved"
systemctl enable --now systemd-resolved
systemctl daemon-reload
systemctl restart systemd-resolved
systemctl restart NetworkManager

echo "== done. Verify: resolvectl status; getent hosts chatgpt.com (should resolve again)"
echo "   (check old backups at /etc/resolv.conf.taskflow-*.bak if anything looks off)"
