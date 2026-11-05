#!/usr/bin/env bash
# Harden a fresh Ubuntu 24.04 / 22.04 / Debian 12 server. Idempotent: safe to re-run.
set -euo pipefail

NEW_USER=${NEW_USER:-deploy}
SSH_KEY=${SSH_KEY:-}
SSH_PORT=${SSH_PORT:-22}
ALLOW_PORTS=${ALLOW_PORTS:-80,443}
ENABLE_IP_FORWARD=${ENABLE_IP_FORWARD:-0}
RUN_LYNIS=${RUN_LYNIS:-1}
DIR=$(cd "$(dirname "$0")" && pwd)

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }
[[ -n "$SSH_KEY" ]] || { echo "Set SSH_KEY=\"ssh-ed25519 ...\"" >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive

log "Installing packages"
apt-get update -q
apt-get install -yq ufw fail2ban unattended-upgrades apt-listchanges needrestart auditd audispd-plugins lynis

log "Creating sudo user $NEW_USER"
id "$NEW_USER" &>/dev/null || adduser --disabled-password --gecos "" "$NEW_USER"
usermod -aG sudo "$NEW_USER"
install -d -m 700 -o "$NEW_USER" -g "$NEW_USER" "/home/$NEW_USER/.ssh"
touch "/home/$NEW_USER/.ssh/authorized_keys"
grep -qxF "$SSH_KEY" "/home/$NEW_USER/.ssh/authorized_keys" || echo "$SSH_KEY" >> "/home/$NEW_USER/.ssh/authorized_keys"
chown "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh/authorized_keys"
chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"

log "Hardening SSH"
install -m 644 "$DIR/configs/sshd-hardening.conf" /etc/ssh/sshd_config.d/99-hardening.conf
grep -q "^AllowUsers" /etc/ssh/sshd_config.d/99-hardening.conf || echo "AllowUsers $NEW_USER" >> /etc/ssh/sshd_config.d/99-hardening.conf
sshd -t
systemctl restart ssh 2>/dev/null || systemctl restart sshd

log "Configuring UFW"
ufw default deny incoming
ufw default allow outgoing
ufw limit "${SSH_PORT}/tcp"
IFS=',' read -ra ports <<< "$ALLOW_PORTS"
for p in "${ports[@]}"; do [[ -n "$p" ]] && ufw allow "${p}/tcp"; done
ufw --force enable

log "Configuring fail2ban"
install -m 644 "$DIR/configs/jail.local" /etc/fail2ban/jail.local
sed -i "s/^\[sshd\]/[sshd]\nport = ${SSH_PORT}/" /etc/fail2ban/jail.local
fail2ban-client -t
systemctl enable --now fail2ban
systemctl restart fail2ban

log "Enabling unattended upgrades"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF

log "Applying sysctl hardening"
install -m 644 "$DIR/configs/99-hardening.conf" /etc/sysctl.d/99-hardening.conf
echo "net.ipv4.ip_forward = ${ENABLE_IP_FORWARD}" >> /etc/sysctl.d/99-hardening.conf
sort -u -o /etc/sysctl.d/99-hardening.conf /etc/sysctl.d/99-hardening.conf
sysctl --system >/dev/null

log "Loading audit rules"
install -m 640 "$DIR/configs/hardening.rules" /etc/audit/rules.d/hardening.rules
systemctl enable --now auditd
augenrules --load || true

if [[ "$RUN_LYNIS" == "1" ]]; then
  log "Running Lynis audit (summary at the end)"
  lynis audit system --quick --no-colors | tail -n 25 || true
fi

log "Done. Open a NEW terminal and test: ssh ${NEW_USER}@<server> -p ${SSH_PORT}"
