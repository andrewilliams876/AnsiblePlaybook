#!/usr/bin/env bash
set -euo pipefail

# =========================
# Settings
# =========================
USER_HOME="${HOME}"
FASTFETCH_DIR="${USER_HOME}/.config/fastfetch"
FASTFETCH_CONFIG="${FASTFETCH_DIR}/config.jsonc"
BASHRC="${USER_HOME}/.bashrc"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# =========================
# Helpers
# =========================
info() { printf "\033[1;32m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*"; }

backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cp "$file" "${file}.bak-${TIMESTAMP}"
    info "Backed up $file -> ${file}.bak-${TIMESTAMP}"
  fi
}

# =========================
# Install fastfetch if missing
# =========================
install_fastfetch() {
  if command -v fastfetch >/dev/null 2>&1; then
    info "fastfetch already installed"
    return
  fi

  info "Trying to install fastfetch via apt..."
  if apt update && apt install -y fastfetch; then
    info "fastfetch installed via apt"
    return
  fi

  warn "apt install failed. Falling back to manual .deb install..."

  TMP_DEB="/tmp/fastfetch.deb"

  wget -q https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb -O "$TMP_DEB"

  apt install -y "$TMP_DEB"

  rm -f "$TMP_DEB"

  if command -v fastfetch >/dev/null 2>&1; then
    info "fastfetch installed via .deb"
  else
    err "fastfetch installation failed"
    exit 1
  fi
}

# =========================
# Write fastfetch config
# =========================
write_fastfetch_config() {
  info "Writing fastfetch config"
  mkdir -p "$FASTFETCH_DIR"

  cat > "$FASTFETCH_CONFIG" <<'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json",

  "logo": {
    "type": "builtin",
    "source": "proxmox",
    "color": {
      "1": "#FFFFFF",
      "2": "#E95420",
      "3": "#FFD166"
    }
  },

  "display": {
    "separator": "  "
  },

  "modules": [
    "title",
    "separator",

    {
      "type": "host",
      "key": "Host"
    },
    {
      "type": "os",
      "key": "OS"
    },
    {
      "type": "kernel",
      "key": "Kernel"
    },
    {
      "type": "uptime",
      "key": "Uptime"
    },

    "separator",

    {
      "type": "cpu",
      "key": "CPU"
    },
    {
      "type": "gpu",
      "key": "GPU"
    },
    {
      "type": "memory",
      "key": "Memory"
    },
    {
      "type": "disk",
      "key": "Disk"
    },

    "separator",

    {
      "type": "localip",
      "key": "IP"
    },
    {
      "type": "packages",
      "key": "Packages"
    },
    {
      "type": "shell",
      "key": "Shell"
    },

    "break",
    "colors"
  ]
}
EOF
}

# =========================
# Disable MOTD noise
# =========================
disable_motd_noise() {
  info "Disabling Ubuntu MOTD noise"

  chmod -x /etc/update-motd.d/* 2>/dev/null || true
  rm -f /etc/update-motd.d/50-landscape-sysinfo || true
  truncate -s 0 /etc/motd || true
}

# =========================
# Disable default SSH Last login
# =========================
configure_sshd() {
  info "Disabling default SSH Last login line"

  echo 'PrintLastLog no' > /etc/ssh/sshd_config.d/99-no-lastlog.conf

  info "Validating sshd config"
  sshd -t

  info "Restarting SSH service"
  systemctl restart ssh || systemctl restart sshd || true
}

# =========================
# Update .bashrc
# =========================
update_bashrc() {
  backup_file "$BASHRC"

  info "Updating .bashrc"

  if grep -q '### FASTFETCH_SSH_BLOCK_START ###' "$BASHRC"; then
    sed -i '/### FASTFETCH_SSH_BLOCK_START ###/,/### FASTFETCH_SSH_BLOCK_END ###/d' "$BASHRC"
  fi

  cat >> "$BASHRC" <<'EOF'

### FASTFETCH_SSH_BLOCK_START ###
# Custom coloured prompt
PS1='\[\033[90m\]\t \[\033[1;32m\]\u@\[\033[1;36m\]\h \[\033[1;34m\]\w\[\033[0m\]\$ '

# Show custom Last login + fastfetch for interactive SSH sessions
if [ -n "$SSH_CONNECTION" ] && [ -t 1 ]; then
  LAST_LOGIN_LINE="$(last -i "$USER" | grep -v 'still logged in' | grep -v '^wtmp begins' | sed -n '2p')"

  if [ -n "$LAST_LOGIN_LINE" ]; then
    LAST_IP="$(echo "$LAST_LOGIN_LINE" | awk '{print $3}')"
    LAST_DATE="$(echo "$LAST_LOGIN_LINE" | awk '{print $4, $5, $6, $7}')"
    printf "\033[1;38;5;250mLast login:\033[0m \033[38;5;255m%s\033[0m \033[1;38;5;250mfrom\033[0m \033[38;5;204m%s\033[0m\n\n" "$LAST_DATE" "$LAST_IP"
  fi

  fastfetch
fi
### FASTFETCH_SSH_BLOCK_END ###
EOF
}

# =========================
# Main
# =========================
main() {
  install_fastfetch
  write_fastfetch_config
  disable_motd_noise
  configure_sshd
  update_bashrc

  info "Done."
  echo
  echo "Next steps:"
  echo "1. Start a new SSH session to test it"
  echo "2. Or run: source ~/.bashrc"
  echo
  echo "Backups were created for files that were modified."
}

main "$@"