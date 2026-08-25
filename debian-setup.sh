#!/usr/bin/env bash

# kali-like-teminal
# Debian-family installer

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

export PATH='/usr/sbin:/usr/bin:/sbin:/bin'

readonly SCRIPT_VERSION='1.0.0'
readonly KALI_ZSHRC_URL='https://gitlab.com/kalilinux/packages/kali-defaults/-/raw/kali/master/etc/skel/.zshrc'
readonly MAX_ZSHRC_SIZE=262144
readonly MIN_ZSHRC_SIZE=1024
readonly MANAGED_ROOT_REL='.local/share/kali-like-terminal'
readonly BACKUP_ROOT_REL='.local/state/kali-like-terminal/backups'
readonly REQUIRED_PACKAGES=(
  zsh
  zsh-syntax-highlighting
  zsh-autosuggestions
  curl
)

CURRENT_USER=''
HOME_DIR=''
TMP_DIR=''
BACKUP_FILE=''
ORIGINAL_LOGIN_SHELL=''
ZSH_PATH=''

ORIGINAL_ZSHRC_EXISTS='false'
ZSHRC_REPLACED='false'
LOGIN_SHELL_CHANGED='false'
MANAGED_ZSHRC_REPLACED='false'

ROLLBACK_MANAGED_PREV=''
ROLLBACK_IN_PROGRESS='false'
COMPLETED='false'

info() {
  printf '\033[1;34m[INFO]\033[0m %s\n' "$*"
}

ok() {
  printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2
}

err() {
  printf '\033[1;31m[ERR ]\033[0m %s\n' "$*" >&2
}

section() {
  printf '\n\033[1;36m==> %s\033[0m\n' "$*"
}

die() {
  err "$*"
  perform_rollback 1
}

cleanup_tmp() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
}

perform_rollback() {
  local exit_code="$1"

  if [[ "$COMPLETED" == 'true' || "$ROLLBACK_IN_PROGRESS" == 'true' ]]; then
    exit "$exit_code"
  fi
  ROLLBACK_IN_PROGRESS='true'

  local rollback_needed='false'
  if [[ "$ZSHRC_REPLACED" == 'true' || "$MANAGED_ZSHRC_REPLACED" == 'true' || "$LOGIN_SHELL_CHANGED" == 'true' ]]; then
    rollback_needed='true'
  fi

  if [[ "$rollback_needed" != 'true' ]]; then
    err 'Installation aborted before shell changes were applied.'
    if [[ -n "$BACKUP_FILE" ]]; then
      warn "A backup was created and kept at: $BACKUP_FILE"
    fi
    exit "$exit_code"
  fi

  warn 'Installation did not complete. Attempting rollback.'

  if [[ "$ZSHRC_REPLACED" == 'true' ]]; then
    if [[ "$ORIGINAL_ZSHRC_EXISTS" == 'true' && -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]]; then
      if cp -- "$BACKUP_FILE" "$HOME_DIR/.zshrc"; then
        ok 'Restored previous ~/.zshrc from backup.'
      else
        warn "Could not restore ~/.zshrc automatically. Backup remains at: $BACKUP_FILE"
      fi
    else
      rm -f -- "$HOME_DIR/.zshrc" || true
    fi
  fi

  if [[ "$MANAGED_ZSHRC_REPLACED" == 'true' ]]; then
    if [[ -n "$ROLLBACK_MANAGED_PREV" && -f "$ROLLBACK_MANAGED_PREV" ]]; then
      cp -- "$ROLLBACK_MANAGED_PREV" "$HOME_DIR/$MANAGED_ROOT_REL/kali-upstream.zshrc" || true
    else
      rm -f -- "$HOME_DIR/$MANAGED_ROOT_REL/kali-upstream.zshrc" || true
    fi
  fi

  if [[ "$LOGIN_SHELL_CHANGED" == 'true' && -n "$ORIGINAL_LOGIN_SHELL" ]]; then
    if chsh -s "$ORIGINAL_LOGIN_SHELL" "$CURRENT_USER" >/dev/null 2>&1; then
      ok 'Restored previous login shell.'
    else
      warn "Could not restore login shell automatically. Previous shell: $ORIGINAL_LOGIN_SHELL"
    fi
  fi

  err 'Installer aborted before completion.'
  exit "$exit_code"
}

rollback_trap() {
  perform_rollback "$?"
}

trap cleanup_tmp EXIT
trap rollback_trap ERR INT TERM

require_command() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || die "Required command not found: $name"
}

retry() {
  local attempts="$1"
  shift

  local i=1
  until "$@"; do
    if (( i >= attempts )); then
      return 1
    fi
    warn "Command failed (attempt $i/$attempts). Retrying..."
    sleep $((i * 2))
    i=$((i + 1))
  done
}

is_ubuntu_family() {
  [[ "${ID:-}" == 'ubuntu' ]] && return 0
  [[ " ${ID_LIKE:-} " == *' ubuntu '* ]] && return 0
  return 1
}

is_debian_family() {
  [[ "${ID:-}" == 'debian' ]] && return 0
  [[ "${ID:-}" == 'kali' ]] && return 0
  [[ " ${ID_LIKE:-} " == *' debian '* ]] && return 0
  return 1
}

load_os_release() {
  [[ -r /etc/os-release ]] || die 'Cannot read /etc/os-release.'
  # shellcheck disable=SC1091
  source /etc/os-release
}

check_environment() {
  section 'Checking environment'

  [[ "$EUID" -ne 0 ]] || die 'Run this script as your normal user, not as root.'

  require_command id
  require_command getent
  require_command awk
  require_command grep
  require_command sudo
  require_command apt-get
  require_command dpkg-query
  require_command chsh
  require_command mktemp
  require_command install

  load_os_release

  if ! is_debian_family; then
    die "This installer only supports Debian-family systems. Detected: ${PRETTY_NAME:-unknown}"
  fi

  if is_ubuntu_family; then
    die 'Ubuntu-family detected. Use ubuntu-setup.sh instead.'
  fi

  CURRENT_USER="$(id -un)"
  HOME_DIR="$(getent passwd "$CURRENT_USER" | awk -F: '{print $6}')"

  [[ -n "$HOME_DIR" && -d "$HOME_DIR" ]] || die "Could not determine home directory for $CURRENT_USER."

  if [[ "${HOME:-}" != "$HOME_DIR" ]]; then
    warn "HOME environment differs from passwd database. Using: $HOME_DIR"
  fi

  ZSH_PATH="$(command -v zsh || true)"
  ORIGINAL_LOGIN_SHELL="$(getent passwd "$CURRENT_USER" | awk -F: '{print $7}')"

  sudo -v >/dev/null

  ok "Detected distribution: ${PRETTY_NAME:-unknown}"
  ok "Installer target: Debian-family"
  ok "User: $CURRENT_USER"
  ok "Home: $HOME_DIR"
}

apt_install_packages() {
  section 'Installing dependencies'

  info 'Updating APT metadata...'
  retry 3 sudo apt-get -q update

  info 'Installing required packages...'
  retry 2 sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install --no-install-recommends "${REQUIRED_PACKAGES[@]}"

  if apt-cache show command-not-found >/dev/null 2>&1; then
    if ! dpkg-query -W -f='${Status}' command-not-found 2>/dev/null | grep -q 'install ok installed'; then
      info 'Installing optional command-not-found integration...'
      sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install --no-install-recommends command-not-found
    fi
  else
    warn 'Optional package command-not-found not available in current repositories.'
  fi

  ZSH_PATH="$(command -v zsh)"
  ok 'Dependency installation completed.'
}

verify_runtime_dependencies() {
  section 'Verifying installed runtime components'

  require_command zsh
  require_command curl

  [[ -x "$ZSH_PATH" ]] || die "Zsh binary is not executable: $ZSH_PATH"

  [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] ||
    die 'zsh-syntax-highlighting package content not found.'

  [[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] ||
    die 'zsh-autosuggestions package content not found.'

  ok "Zsh binary: $ZSH_PATH"
  ok 'zsh-syntax-highlighting: present'
  ok 'zsh-autosuggestions: present'
}

prepare_tempdir() {
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kali-like-terminal.XXXXXXXX")"
}

download_upstream_zshrc() {
  section 'Downloading upstream Kali .zshrc'

  prepare_tempdir
  local out_file="$TMP_DIR/upstream.zshrc"

  info "Source: $KALI_ZSHRC_URL"

  retry 3 curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --proto '=https' \
    --tlsv1.2 \
    --connect-timeout 10 \
    --max-time 60 \
    --max-filesize "$MAX_ZSHRC_SIZE" \
    --output "$out_file" \
    "$KALI_ZSHRC_URL"

  [[ -s "$out_file" ]] || die 'Downloaded Kali .zshrc is empty.'

  local size
  size="$(wc -c < "$out_file")"
  if (( size < MIN_ZSHRC_SIZE || size > MAX_ZSHRC_SIZE )); then
    die "Downloaded .zshrc has unexpected size: $size bytes"
  fi

  if ! grep -Iq . "$out_file"; then
    die 'Downloaded .zshrc does not look like a text file.'
  fi

  ok "Downloaded upstream .zshrc (${size} bytes)."
}

validate_upstream_zshrc() {
  section 'Validating upstream Kali .zshrc'

  local file="$TMP_DIR/upstream.zshrc"

  zsh -n "$file" || die 'Downloaded .zshrc failed syntax validation (zsh -n).'

  grep -q 'configure_prompt' "$file" ||
    die 'Downloaded .zshrc does not include expected prompt configuration.'

  grep -q 'PROMPT_ALTERNATIVE=' "$file" ||
    die 'Downloaded .zshrc does not include expected Kali prompt variable.'

  grep -q 'zsh-syntax-highlighting' "$file" ||
    die 'Downloaded .zshrc does not include expected syntax-highlighting integration.'

  grep -q 'zsh-autosuggestions' "$file" ||
    die 'Downloaded .zshrc does not include expected autosuggestions integration.'

  ok 'Upstream .zshrc passed validation checks.'
}

backup_existing_user_zshrc() {
  section 'Backing up existing ~/.zshrc'

  local current="$HOME_DIR/.zshrc"

  mkdir -p "$HOME_DIR/$BACKUP_ROOT_REL"

  if [[ ! -e "$current" ]]; then
    info 'No existing ~/.zshrc was found.'
    return
  fi

  [[ -f "$current" ]] || die '~/.zshrc exists but is not a regular file.'

  ORIGINAL_ZSHRC_EXISTS='true'
  BACKUP_FILE="$HOME_DIR/$BACKUP_ROOT_REL/zshrc.$(date '+%Y%m%d-%H%M%S').$$.bak"

  cp --preserve=mode,timestamps -- "$current" "$BACKUP_FILE"

  ok "Backup created: $BACKUP_FILE"
}

write_managed_files() {
  section 'Installing managed Kali configuration'

  local managed_dir="$HOME_DIR/$MANAGED_ROOT_REL"
  local managed_file="$managed_dir/kali-upstream.zshrc"
  local managed_tmp="$TMP_DIR/kali-upstream.zshrc.new"
  local user_zshrc_tmp="$TMP_DIR/user.zshrc.new"
  local user_zshrc="$HOME_DIR/.zshrc"

  mkdir -p "$managed_dir"

  if [[ -f "$managed_file" ]]; then
    ROLLBACK_MANAGED_PREV="$TMP_DIR/kali-upstream.zshrc.prev"
    cp -- "$managed_file" "$ROLLBACK_MANAGED_PREV"
  fi

  install -m 0644 "$TMP_DIR/upstream.zshrc" "$managed_tmp"
  mv -f -- "$managed_tmp" "$managed_file"
  MANAGED_ZSHRC_REPLACED='true'

  cat > "$user_zshrc_tmp" <<EOF
# Generated by kali-like-teminal (${SCRIPT_VERSION}) on $(date -u '+%Y-%m-%dT%H:%M:%SZ')
# Previous file is backed up under: ~/${BACKUP_ROOT_REL}
# To stop using this setup, restore a backup and change your shell with:
#   chsh -s /bin/bash

if [ -r "\$HOME/${MANAGED_ROOT_REL}/kali-upstream.zshrc" ]; then
  . "\$HOME/${MANAGED_ROOT_REL}/kali-upstream.zshrc"
else
  printf '%s\n' 'kali-like-teminal: missing managed upstream file.' >&2
fi
EOF

  zsh -n "$user_zshrc_tmp" || die 'Generated ~/.zshrc wrapper failed syntax validation.'

  install -m 0644 "$user_zshrc_tmp" "$user_zshrc"
  ZSHRC_REPLACED='true'

  ok "Installed managed upstream file: $managed_file"
  ok "Installed user wrapper: $user_zshrc"
}

configure_login_shell() {
  section 'Configuring default login shell'

  local current_shell
  current_shell="$(getent passwd "$CURRENT_USER" | awk -F: '{print $7}')"

  if ! grep -Fxq "$ZSH_PATH" /etc/shells; then
    info "Adding $ZSH_PATH to /etc/shells"
    printf '%s\n' "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
  fi

  if [[ "$current_shell" == "$ZSH_PATH" ]]; then
    ok 'Default login shell is already zsh.'
    return
  fi

  info "Changing login shell from $current_shell to $ZSH_PATH"
  chsh -s "$ZSH_PATH" "$CURRENT_USER"
  LOGIN_SHELL_CHANGED='true'

  local resulting_shell
  resulting_shell="$(getent passwd "$CURRENT_USER" | awk -F: '{print $7}')"
  [[ "$resulting_shell" == "$ZSH_PATH" ]] || die 'Could not verify updated login shell.'

  ok 'Default login shell updated to zsh.'
}

final_verification() {
  section 'Final verification'

  local login_shell
  login_shell="$(getent passwd "$CURRENT_USER" | awk -F: '{print $7}')"

  [[ -f "$HOME_DIR/.zshrc" ]] || die '~/.zshrc was not installed.'
  [[ -f "$HOME_DIR/$MANAGED_ROOT_REL/kali-upstream.zshrc" ]] || die 'Managed upstream file missing after installation.'
  [[ "$login_shell" == "$ZSH_PATH" ]] || die 'Default shell verification failed.'

  zsh -n "$HOME_DIR/.zshrc" || die 'Installed ~/.zshrc is not valid zsh syntax.'
  zsh -n "$HOME_DIR/$MANAGED_ROOT_REL/kali-upstream.zshrc" || die 'Installed managed upstream file is not valid zsh syntax.'

  ok "Default shell: $login_shell"
  ok 'Installed shell configuration is internally consistent.'
}

print_summary() {
  printf '\n\033[1;32mInstallation completed successfully.\033[0m\n\n'
  printf 'What changed:\n'
  printf '  - Installed/verified required packages\n'
  printf '  - Downloaded current Kali upstream .zshrc\n'
  printf '  - Installed managed upstream file at ~/.local/share/kali-like-terminal/\n'
  printf '  - Replaced ~/.zshrc with a safe wrapper\n'
  printf '  - Set default login shell to zsh\n\n'

  if [[ -n "$BACKUP_FILE" ]]; then
    printf 'Backup created:\n  %s\n\n' "$BACKUP_FILE"
  fi

  printf 'Next steps:\n'
  printf '  1) Log out and log back in, or run: exec zsh\n'
  printf '  2) Verify default shell: echo "$SHELL"\n'
  printf '  3) Restore previous config if needed: cp <backup> ~/.zshrc\n\n'
}

main() {
  printf '\n\033[1;35m==============================================\033[0m\n'
  printf '\033[1;35m   kali-like-teminal | Debian-family setup   \033[0m\n'
  printf '\033[1;35m==============================================\033[0m\n'

  check_environment
  apt_install_packages
  verify_runtime_dependencies
  download_upstream_zshrc
  validate_upstream_zshrc
  backup_existing_user_zshrc
  write_managed_files
  configure_login_shell
  final_verification

  COMPLETED='true'
  trap - ERR INT TERM
  print_summary
}

main "$@"
