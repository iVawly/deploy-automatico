#!/usr/bin/env bash
# Hardens SSH: key-only authentication restricted to the ops group, with sudo.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "execute como root (sudo $0)" >&2; exit 1; }

SSHD_CONFIG_DIR=/etc/ssh/sshd_config.d
SSHD_DROPIN="$SSHD_CONFIG_DIR/00-ops-deploy.conf"
LEGACY_DROPIN="$SSHD_CONFIG_DIR/99-ops-deploy.conf"
SUDOERS_DIR=/etc/sudoers.d
# The "10-" prefix sorts before cloud-init's 90-cloud-init-users so that a
# specific NOPASSWD grant for a passwordless operator keeps working. sudo uses
# the last matching rule, so a later filename would override that grant.
SUDOERS_FILE="$SUDOERS_DIR/10-ops-deploy"

die() { echo "ERRO: $*" >&2; exit 1; }

for cmd in groupadd usermod install mktemp sshd systemctl visudo getent id; do
  command -v "$cmd" >/dev/null 2>&1 || die "comando obrigatório não encontrado: $cmd"
done

user_in_ops() {
  local groups
  groups="$(id -nG "$1" 2>/dev/null || true)"
  [[ " $groups " == *" ops "* ]]
}

ops_member_names() {
  local user
  while IFS=: read -r user _; do
    [[ -n "$user" ]] || continue
    if user_in_ops "$user"; then
      printf '%s\n' "$user"
    fi
  done < <(getent passwd)
}

# The human who invoked the script, even when it ran from a root shell via su.
operator_from_session() {
  local candidate="${SUDO_USER:-}"
  if [[ -z "$candidate" || "$candidate" == root ]] && command -v logname >/dev/null 2>&1; then
    candidate="$(logname 2>/dev/null || true)"
  fi
  [[ -n "$candidate" ]] || candidate=root
  printf '%s' "$candidate"
}

# Safety gate before AllowGroups: the operator or root must keep a usable key,
# so enabling key-only access cannot lock the host out. Service accounts with a
# non-interactive shell do not count as SSH access.
has_breakglass_key() {
  local user home shell
  for user in "$operator" root; do
    if [[ "$user" != root ]] && ! user_in_ops "$user"; then
      continue
    fi
    home="$(getent passwd "$user" | cut -d: -f6 || true)"
    shell="$(getent passwd "$user" | cut -d: -f7 || true)"
    [[ -n "$shell" && "$shell" != */nologin && "$shell" != */false ]] || continue
    if [[ -n "$home" && -s "$home/.ssh/authorized_keys" ]]; then
      return 0
    fi
  done
  return 1
}

check_sshd_effective() {
  local effective expected
  effective="$(sshd -T)" || die "sshd -T falhou; corrija a configuração antes de recarregar o serviço."

  for expected in \
    "passwordauthentication no" \
    "kbdinteractiveauthentication no" \
    "permitemptypasswords no" \
    "authenticationmethods publickey" \
    "pubkeyauthentication yes" \
    "allowgroups ops"; do
    if ! grep -qxF "$expected" <<<"$effective"; then
      echo "ERRO: configuração efetiva do sshd não contém: $expected" >&2
      echo "Um drop-in anterior em $SSHD_CONFIG_DIR pode estar prevalecendo." >&2
      exit 1
    fi
  done

  if ! grep -Eqx 'permitrootlogin (prohibit-password|without-password)' <<<"$effective"; then
    echo "ERRO: PermitRootLogin efetivo não é prohibit-password/without-password." >&2
    exit 1
  fi
}

groupadd -f ops
install -d -m 0755 "$SSHD_CONFIG_DIR"
install -d -m 0750 "$SUDOERS_DIR"

operator="$(operator_from_session)"
if [[ "$operator" != root ]]; then
  operator_shell="$(getent passwd "$operator" | cut -d: -f7 || true)"
  if [[ -z "$operator_shell" ]]; then
    echo "AVISO: usuário operador $operator não encontrado; tratando root como operador." >&2
    operator=root
  elif [[ "$operator_shell" == */nologin || "$operator_shell" == */false ]]; then
    echo "AVISO: $operator tem shell não interativo; não será adicionado ao grupo ops." >&2
  else
    usermod -aG ops "$operator"
  fi
fi
usermod -aG ops root

if ! has_breakglass_key; then
  die "nenhuma chave usável para o operador ($operator) ou root; adicione authorized_keys antes de aplicar AllowGroups ops."
fi

sudoers_tmp="$(mktemp)"
trap 'rm -f "$sudoers_tmp"' EXIT
cat >"$sudoers_tmp" <<'EOF'
# Managed by deploy-platform. Members of ops may run any command after password authentication.
%ops ALL=(ALL:ALL) ALL
EOF
chmod 0440 "$sudoers_tmp"
visudo -cf "$sudoers_tmp" >/dev/null
install -m 0440 -o root -g root "$sudoers_tmp" "$SUDOERS_FILE"
rm -f "$sudoers_tmp"
trap - EXIT

cat >"$SSHD_DROPIN" <<'EOF'
# Managed by deploy-platform. This file must sort first in sshd_config.d:
# sshd uses the first obtained value for each keyword.
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
AllowGroups ops
EOF
chmod 0644 "$SSHD_DROPIN"

install -d -m 0755 /run/sshd
sshd -t
check_sshd_effective
rm -f "$LEGACY_DROPIN"
systemctl reload ssh

members="$(ops_member_names | sort -u | tr '\n' ' ')"
members="${members% }"
echo "SSH endurecido: somente o grupo ops autentica, por chave pública."
echo "Sudo do grupo ops configurado em $SUDOERS_FILE (senha local, salvo regra específica existente)."
echo "Membros do grupo ops: ${members:-<nenhum>}"
echo "Adicione outros operadores: usermod -aG ops <usuario>"
echo "Mantenha a sessão atual aberta e teste o acesso por chave em outra janela."
