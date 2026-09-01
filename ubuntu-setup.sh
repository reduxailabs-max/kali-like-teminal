#!/usr/bin/env bash

# kali-like-teminal
# Ubuntu-family installer

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

export PATH='/usr/sbin:/usr/bin:/sbin:/bin'

readonly SCRIPT_VERSION='v1.1.1'
readonly KALI_ZSHRC_URL='https://gitlab.com/kalilinux/packages/kali-defaults/-/raw/kali/master/etc/skel/.zshrc'
readonly MAX_ZSHRC_SIZE=262144
readonly MIN_ZSHRC_SIZE=1024
readonly MANAGED_ROOT_REL='.local/share/kali-like-terminal'
readonly BACKUP_ROOT_REL='.local/state/kali-like-terminal/backups'
readonly STATE_ROOT_REL='.local/state/kali-like-terminal'
readonly CONFIG_ROOT_REL='.config/kali-like-terminal'
readonly REQUIRED_PACKAGES=(
  zsh
  zsh-syntax-highlighting
  zsh-autosuggestions
  curl
)
readonly MANAGED_BLOCK_START='# >>> KLT MANAGED START'
readonly MANAGED_BLOCK_END='# <<< KLT MANAGED END'

CURRENT_USER=''
HOME_DIR=''
TMP_DIR=''
BACKUP_FILE=''
ORIGINAL_LOGIN_SHELL=''
ZSH_PATH=''
STATE_FILE=''
OVERRIDES_FILE=''
MIGRATIONS_DIR=''

ORIGINAL_ZSHRC_EXISTS='false'
ZSHRC_REPLACED='false'
LOGIN_SHELL_CHANGED='false'
MANAGED_ZSHRC_REPLACED='false'

ROLLBACK_MANAGED_PREV=''
ROLLBACK_IN_PROGRESS='false'
COMPLETED='false'

MIGRATION_RESULT='none'
MIGRATION_NOTE=''
SANITIZE_NOTE=''

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

ensure_user_directories() {
  mkdir -p "$HOME_DIR/$MANAGED_ROOT_REL"
  mkdir -p "$HOME_DIR/$BACKUP_ROOT_REL"
  mkdir -p "$HOME_DIR/$STATE_ROOT_REL"
  mkdir -p "$HOME_DIR/$CONFIG_ROOT_REL"
  mkdir -p "$MIGRATIONS_DIR"
}

sha256_of_file() {
  local file="$1"
  sha256sum "$file" | awk '{print $1}'
}

read_state_value() {
  local key="$1"
  if [[ ! -f "$STATE_FILE" ]]; then
    return 0
  fi
  awk -F'=' -v k="$key" '$1 == k {v=$0; sub(/^[^=]*=/, "", v); print v}' "$STATE_FILE" | tail -n1
}

write_state_value() {
  local key="$1"
  local value="$2"
  local tmp="$TMP_DIR/state.new"

  if [[ -f "$STATE_FILE" ]]; then
    awk -F'=' -v k="$key" -v v="$value" '
      BEGIN { updated=0 }
      $1 == k { print k "=" v; updated=1; next }
      { print }
      END { if (!updated) print k "=" v }
    ' "$STATE_FILE" > "$tmp"
  else
    printf '%s=%s\n' "$key" "$value" > "$tmp"
  fi

  install -m 0600 "$tmp" "$STATE_FILE"
}

create_overrides_file_if_missing() {
  if [[ -f "$OVERRIDES_FILE" ]]; then
    return
  fi

  cat > "$OVERRIDES_FILE" <<'EOF'
# User customizations loaded after Kali upstream zsh config.
# This file is preserved across reinstalls by kali-like-teminal.
# Add aliases/functions/exports below.
EOF

  chmod 0644 "$OVERRIDES_FILE"
}

is_marker_managed_zshrc() {
  local file="$1"
  grep -Fxq "$MANAGED_BLOCK_START" "$file" && grep -Fxq "$MANAGED_BLOCK_END" "$file"
}

is_legacy_generated_zshrc() {
  local file="$1"
  grep -q '^# Generated by kali-like-teminal' "$file"
}

extract_non_managed_content() {
  local source_file="$1"
  local output_file="$2"

  awk -v start="$MANAGED_BLOCK_START" -v end="$MANAGED_BLOCK_END" '
    /^# Generated by kali-like-teminal/ { next }
    /^# Previous file is backed up under:/ { next }
    /^# To stop using this setup,/ { next }
    /^#   chsh -s \/bin\/bash/ { next }
    /^$/ { next }
    $0 == start { inside=1; next }
    $0 == end { inside=0; next }
    !inside { print }
  ' "$source_file" > "$output_file"
}

extract_legacy_wrapper_custom_content() {
  local source_file="$1"
  local output_file="$2"

  awk '
    /^# Generated by kali-like-teminal/ { next }
    /^# Previous file is backed up under:/ { next }
    /^# To stop using this setup,/ { next }
    /^#   chsh -s \/bin\/bash/ { next }
    /^$/ { next }
    /^_klt_source_legacy_file\(\)/ { in_fn=1; next }
    in_fn && /^}/ { in_fn=0; next }
    in_fn { next }
    /^# Load existing profile\/bash customizations first/ { next }
    /^_klt_source_legacy_file "\$HOME\/.profile"/ { next }
    /^_klt_source_legacy_file "\$HOME\/.bashrc"/ { next }
    /^unset -f _klt_source_legacy_file/ { next }
    /^if \[ -r "\$HOME\/.*kali-upstream\.zshrc" \]; then$/ { in_managed_if=1; next }
    in_managed_if && /^fi$/ { in_managed_if=0; next }
    in_managed_if { next }
    { print }
  ' "$source_file" > "$output_file"
}

append_content_to_overrides() {
  local content_file="$1"
  local migration_label="$2"
  local source_hash="$3"

  local start_marker="# >>> KLT MIGRATED ${migration_label} ${source_hash}"
  local end_marker="# <<< KLT MIGRATED ${migration_label} ${source_hash}"

  if grep -Fq "$start_marker" "$OVERRIDES_FILE" 2>/dev/null; then
    MIGRATION_NOTE='Detected already-migrated custom block; skipped duplicate import.'
    return 0
  fi

  local candidate="$TMP_DIR/user-overrides.candidate.zsh"
  cp -- "$OVERRIDES_FILE" "$candidate"

  {
    printf '\n%s\n' "$start_marker"
    printf '# Imported from previous ~/.zshrc during reinstall on %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    cat "$content_file"
    printf '%s\n' "$end_marker"
  } >> "$candidate"

  if ! zsh -n "$candidate"; then
    return 1
  fi

  install -m 0644 "$candidate" "$OVERRIDES_FILE"
  return 0
}

archive_legacy_zshrc() {
  local source_file="$1"
  local source_hash="$2"
  local archive_file="$MIGRATIONS_DIR/legacy-zshrc.$(date '+%Y%m%d-%H%M%S').${source_hash:0:12}.zsh"

  cp -- "$source_file" "$archive_file"
  chmod 0644 "$archive_file"
  MIGRATION_NOTE="Archived previous unmanaged ~/.zshrc to $archive_file"

  if ! grep -Fq "$archive_file" "$OVERRIDES_FILE" 2>/dev/null; then
    {
      printf '\n# Previous unmanaged ~/.zshrc archived by kali-like-teminal:\n'
      printf '#   %s\n' "$archive_file"
      printf '# Review and copy compatible zsh lines manually if desired.\n'
    } >> "$OVERRIDES_FILE"
  fi
}

migrate_existing_zshrc_customizations() {
  section 'Preserving customizations from previous ~/.zshrc'

  local current="$HOME_DIR/.zshrc"
  local extracted="$TMP_DIR/extracted-customizations.zsh"

  ensure_user_directories
  create_overrides_file_if_missing

  if [[ ! -f "$current" ]]; then
    info 'No prior ~/.zshrc present; nothing to migrate.'
    MIGRATION_RESULT='none'
    return
  fi

  local current_hash
  current_hash="$(sha256_of_file "$current")"

  local last_hash
  last_hash="$(read_state_value 'LAST_MIGRATED_ZSHRC_SHA256')"

  if [[ -n "$last_hash" && "$last_hash" == "$current_hash" ]]; then
    info 'Previous ~/.zshrc hash already migrated; skipping duplicate migration.'
    MIGRATION_RESULT='already-migrated'
    return
  fi

  : > "$extracted"

  if is_marker_managed_zshrc "$current"; then
    extract_non_managed_content "$current" "$extracted"

    if grep -q '[^[:space:]]' "$extracted"; then
      if append_content_to_overrides "$extracted" 'MANAGED_WRAPPER' "$current_hash"; then
        MIGRATION_RESULT='migrated-from-managed-wrapper'
      else
        archive_legacy_zshrc "$current" "$current_hash"
        MIGRATION_RESULT='managed-custom-content-needs-manual-review'
        warn 'Detected custom content, but automatic merge failed zsh syntax checks. Archived for manual review.'
      fi
    else
      MIGRATION_RESULT='no-custom-content-in-managed-wrapper'
    fi
  elif is_legacy_generated_zshrc "$current"; then
    extract_legacy_wrapper_custom_content "$current" "$extracted"

    if grep -q '[^[:space:]]' "$extracted"; then
      if append_content_to_overrides "$extracted" 'LEGACY_KLT_WRAPPER' "$current_hash"; then
        MIGRATION_RESULT='migrated-from-legacy-wrapper'
      else
        archive_legacy_zshrc "$current" "$current_hash"
        MIGRATION_RESULT='legacy-custom-content-needs-manual-review'
        warn 'Detected custom content in legacy wrapper, but automatic merge failed zsh checks. Archived for manual review.'
      fi
    else
      MIGRATION_RESULT='no-custom-content-in-legacy-wrapper'
    fi
  else
    archive_legacy_zshrc "$current" "$current_hash"
    MIGRATION_RESULT='archived-unmanaged-zshrc'
    warn 'Previous ~/.zshrc was unmanaged. It was archived for manual review instead of auto-sourcing.'
  fi

  write_state_value 'LAST_MIGRATED_ZSHRC_SHA256' "$current_hash"
  write_state_value 'LAST_MIGRATION_RESULT' "$MIGRATION_RESULT"
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
  require_command sha256sum

  load_os_release

  if ! is_ubuntu_family; then
    die "This installer only supports Ubuntu-family systems. Detected: ${PRETTY_NAME:-unknown}"
  fi

  if ! is_debian_family; then
    die 'Unexpected os-release data: system is not Debian-based.'
  fi

  CURRENT_USER="$(id -un)"
  HOME_DIR="$(getent passwd "$CURRENT_USER" | awk -F: '{print $6}')"

  [[ -n "$HOME_DIR" && -d "$HOME_DIR" ]] || die "Could not determine home directory for $CURRENT_USER."

  if [[ "${HOME:-}" != "$HOME_DIR" ]]; then
    warn "HOME environment differs from passwd database. Using: $HOME_DIR"
  fi

  STATE_FILE="$HOME_DIR/$STATE_ROOT_REL/state"
  OVERRIDES_FILE="$HOME_DIR/$CONFIG_ROOT_REL/user-overrides.zsh"
  MIGRATIONS_DIR="$HOME_DIR/$CONFIG_ROOT_REL/migrations"

  ZSH_PATH="$(command -v zsh || true)"
  ORIGINAL_LOGIN_SHELL="$(getent passwd "$CURRENT_USER" | awk -F: '{print $7}')"

  sudo -v >/dev/null

  ok "Detected distribution: ${PRETTY_NAME:-unknown}"
  ok 'Installer target: Ubuntu-family'
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

  ensure_user_directories

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

sanitize_overrides_file() {
  section 'Sanitizing persistent user overrides'

  create_overrides_file_if_missing

  local src="$OVERRIDES_FILE"
  local dst="$TMP_DIR/user-overrides.sanitized.zsh"
  local changed='false'

  : > "$dst"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*shopt([[:space:]]|$) ]]; then
      printf '# klt-disabled bash-only: %s\n' "$line" >> "$dst"
      changed='true'
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*(setopt|unsetopt)[[:space:]].*CHECKWINSIZE([[:space:]]|$) ]]; then
      printf '# klt-disabled invalid-in-zsh: %s\n' "$line" >> "$dst"
      changed='true'
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(PROMPT|PS1|RPROMPT|RPS1)= ]]; then
      printf '# klt-disabled prompt-override (preserve Kali prompt): %s\n' "$line" >> "$dst"
      changed='true'
      continue
    fi

    printf '%s\n' "$line" >> "$dst"
  done < "$src"

  if [[ "$changed" == 'true' ]]; then
    zsh -n "$dst" || die 'Sanitized user-overrides file failed syntax validation.'
    install -m 0644 "$dst" "$OVERRIDES_FILE"
    SANITIZE_NOTE='Commented incompatible legacy lines and prompt overrides (shopt/CHECKWINSIZE/PROMPT/PS1) in user-overrides.'
    warn 'Commented incompatible override lines to prevent zsh warnings and preserve Kali prompt.'
  else
    info 'No known incompatible or prompt-override lines found in user overrides.'
  fi
}

write_managed_files() {
  section 'Installing managed Kali configuration'

  local managed_file="$HOME_DIR/$MANAGED_ROOT_REL/kali-upstream.zshrc"
  local managed_tmp="$TMP_DIR/kali-upstream.zshrc.new"
  local user_zshrc_tmp="$TMP_DIR/user.zshrc.new"
  local user_zshrc="$HOME_DIR/.zshrc"

  ensure_user_directories
  create_overrides_file_if_missing

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

${MANAGED_BLOCK_START}
_klt_source_legacy_file() {
  local file="\$1"
  if [ -r "\$file" ]; then
    if ! . "\$file" >/dev/null 2>&1; then
      printf '%s\n' "kali-like-teminal: warning: could not fully source \$file in zsh; continuing." >&2
    fi
  fi
}

# Load existing profile/bash customizations first (best-effort).
_klt_source_legacy_file "\$HOME/.profile"
_klt_source_legacy_file "\$HOME/.bashrc"
unset -f _klt_source_legacy_file

# Load current upstream Kali shell behavior.
if [ -r "\$HOME/${MANAGED_ROOT_REL}/kali-upstream.zshrc" ]; then
  . "\$HOME/${MANAGED_ROOT_REL}/kali-upstream.zshrc"
else
  printf '%s\n' 'kali-like-teminal: missing managed upstream file.' >&2
fi

# Load preserved user customizations after Kali config.
if [ -r "\$HOME/${CONFIG_ROOT_REL}/user-overrides.zsh" ]; then
  . "\$HOME/${CONFIG_ROOT_REL}/user-overrides.zsh"
fi
${MANAGED_BLOCK_END}
EOF

  zsh -n "$user_zshrc_tmp" || die 'Generated ~/.zshrc wrapper failed syntax validation.'

  install -m 0644 "$user_zshrc_tmp" "$user_zshrc"
  ZSHRC_REPLACED='true'

  ok "Installed managed upstream file: $managed_file"
  ok "Installed user wrapper: $user_zshrc"
  ok "Persistent user overrides file: $OVERRIDES_FILE"
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
  [[ -f "$OVERRIDES_FILE" ]] || die 'Persistent user overrides file missing after installation.'
  [[ "$login_shell" == "$ZSH_PATH" ]] || die 'Default shell verification failed.'

  zsh -n "$HOME_DIR/.zshrc" || die 'Installed ~/.zshrc is not valid zsh syntax.'
  zsh -n "$HOME_DIR/$MANAGED_ROOT_REL/kali-upstream.zshrc" || die 'Installed managed upstream file is not valid zsh syntax.'
  zsh -n "$OVERRIDES_FILE" || die 'Persistent user overrides file is not valid zsh syntax.'

  ok "Default shell: $login_shell"
  ok 'Installed shell configuration is internally consistent.'
}

print_summary() {
  printf '\n\033[1;32mInstallation completed successfully.\033[0m\n\n'
  printf 'What changed:\n'
  printf '  - Installed/verified required packages\n'
  printf '  - Downloaded current Kali upstream .zshrc\n'
  printf '  - Installed managed upstream file at ~/.local/share/kali-like-terminal/\n'
  printf '  - Installed ~/.zshrc managed wrapper with migration-safe markers\n'
  printf '  - Added persistent user overrides file at ~/.config/kali-like-terminal/user-overrides.zsh\n'
  printf '  - Set default login shell to zsh\n\n'

  if [[ -n "$BACKUP_FILE" ]]; then
    printf 'Backup created:\n  %s\n\n' "$BACKUP_FILE"
  fi

  printf 'Customization migration result:\n  %s\n' "$MIGRATION_RESULT"
  if [[ -n "$MIGRATION_NOTE" ]]; then
    printf '  %s\n' "$MIGRATION_NOTE"
  fi
  if [[ -n "$SANITIZE_NOTE" ]]; then
    printf '  %s\n' "$SANITIZE_NOTE"
  fi
  printf '\n'

  printf 'Next steps:\n'
  printf '  1) Log out and log back in, or run: exec zsh\n'
  printf '  2) Verify default shell: echo "$SHELL"\n'
  printf '  3) Put your own aliases/functions in ~/.config/kali-like-terminal/user-overrides.zsh\n\n'
}

main() {
  printf '\n\033[1;35m==============================================\033[0m\n'
  printf '\033[1;35m   kali-like-teminal | Ubuntu-family setup   \033[0m\n'
  printf '\033[1;35m==============================================\033[0m\n'

  check_environment
  apt_install_packages
  verify_runtime_dependencies
  download_upstream_zshrc
  validate_upstream_zshrc
  backup_existing_user_zshrc
  migrate_existing_zshrc_customizations
  sanitize_overrides_file
  write_managed_files
  configure_login_shell
  final_verification

  COMPLETED='true'
  trap - ERR INT TERM
  print_summary
}

main "$@"
