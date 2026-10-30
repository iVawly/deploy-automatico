#!/usr/bin/env bash
# Hardens SSH: key-only authentication and no password login.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "execute como root (sudo $0)" >&2; exit 1; }

if ! find /home /root -maxdepth 3 -type f -name authorized_keys -size +0c 2>/dev/null | grep -q .; then
  echo "ERRO: nenhuma chave pública encontrada em /home/*/.ssh/authorized_keys ou /root/.ssh/authorized_keys." >&2
  echo "Adicione sua chave antes de desabilitar a autenticação por senha para evitar lockout." >&2
  exit 1
fi

groupadd -f ops
install -d -m 0755 /etc/ssh/sshd_config.d

cat >/etc/ssh/sshd_config.d/99-ops-deploy.conf <<'EOF'
# Managed by deploy-platform. Keep this file last in sshd_config Include order.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
AuthenticationMethods publickey
PubkeyAuthentication yes
PermitRootLogin prohibit-password
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
MaxAuthTries 4
MaxSessions 4
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
LogLevel VERBOSE
EOF

sshd -t
systemctl reload ssh

echo "SSH endurecido. Adicione os responsáveis ao grupo ops:"
echo "  usermod -aG ops <usuario>"
echo "Mantenha a sessão atual aberta e teste o acesso por chave em outra janela."
