#!/usr/bin/env bash
# Applies baseline host hardening: sysctl, journald, auditd, fail2ban and unattended upgrades.
set -Eeuo pipefail
umask 022

[[ $EUID -eq 0 ]] || { echo "execute como root (sudo $0)" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y unattended-upgrades fail2ban python3-systemd auditd

cat >/etc/sysctl.d/99-ops-deploy.conf <<'EOF'
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
kernel.randomize_va_space = 2
fs.suid_dumpable = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
EOF
sysctl --system >/dev/null

install -d -m 0755 /etc/systemd/journald.conf.d
cat >/etc/systemd/journald.conf.d/99-ops-deploy.conf <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=500M
SystemKeepFree=1G
MaxRetentionSec=30day
Compress=yes
EOF
systemctl restart systemd-journald

cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
cat >/etc/apt/apt.conf.d/51ops-deploy <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

install -d -m 0755 /etc/fail2ban/jail.d
cat >/etc/fail2ban/jail.d/ops-deploy.local <<'EOF'
[sshd]
enabled = true
backend = systemd
mode = aggressive
maxretry = 5
findtime = 10m
bantime = 1h
EOF
systemctl enable --now fail2ban

install -d -m 0750 /etc/audit/rules.d
cat >/etc/audit/rules.d/ops-deploy.rules <<'EOF'
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d -p wa -k sudoers
-w /etc/ssh/sshd_config -p wa -k sshd
-w /var/run/docker.sock -p rwa -k docker_socket
EOF
augenrules --load
systemctl enable --now auditd

timedatectl set-ntp true
echo "Hardening de sistema aplicado. Reinicie para validar os sysctls e o auditd."
