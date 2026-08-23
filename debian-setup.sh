```bash
#!/usr/bin/env bash

# Kali-like Terminal Zsh
# Debian-family installer
#
# Installs Zsh and the components required by Kali Linux's official
# .zshrc, downloads Kali's current .zshrc, validates it, safely
# replaces ~/.zshrc, and makes Zsh the user's default login shell.
#
# Supported:
#   Debian and Debian-family distributions using APT.
#
# Repository:
#   https://github.com/reduxailabs-max/kali-like-teminal
#
# Kali .zshrc source:
#   https://gitlab.com/kalilinux/packages/kali-defaults/-/blob/kali/master/etc/skel/.zshrc
#
# IMPORTANT:
#   Run this script as your normal user.
#   Do NOT run it with sudo.

set -Eeuo pipefail
IFS=$'\n\t'

readonly KALI_ZSHRC_URL="https://gitlab.com/kalilinux/packages/kali-defaults/-/raw/kali/master/etc/skel/.zshrc"

readonly REQUIRED_PACKAGES=(
    zsh
    zsh-syntax-highlighting
    zsh-autosuggestions
    curl
)

readonly MAX_ZSHRC_SIZE=1048576

CURRENT_USER=""
HOME_DIR=""
TMP_DIR=""
BACKUP_FILE=""
ORIGINAL_LOGIN_SHELL=""

ORIGINAL_ZSHRC_EXISTS=false
ZSHRC_INSTALLED=false
LOGIN_SHELL_CHANGED=false
SHELL_ENTRY_ADDED=false


# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------

info() {
    printf '\033[1;34m[INFO]\033[0m %s\n' "$*"
}

success() {
    printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"
}

warn() {
    printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2
}

error() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
}

die() {
    error "$*"
    exit 1
}

section() {
    printf '\n\033[1;36m==> %s\033[0m\n' "$*"
}


# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------

cleanup() {
    if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
        rm -rf -- "$TMP_DIR"
    fi
}

trap cleanup EXIT


# -----------------------------------------------------------------------------
# Rollback
# -----------------------------------------------------------------------------

rollback() {
    local exit_code=$?

    warn "Installation failed. Attempting rollback."

    if [[ "$ZSHRC_INSTALLED" == true ]]; then
        if [[ "$ORIGINAL_ZSHRC_EXISTS" == true &&
              -n "${BACKUP_FILE:-}" &&
              -f "$BACKUP_FILE" ]]; then

            if cp -- "$BACKUP_FILE" "$HOME_DIR/.zshrc"; then
                success "Previous ~/.zshrc restored."
            else
                error "Could not restore the previous ~/.zshrc."
                error "Your backup is still available at:"
                error "  $BACKUP_FILE"
            fi
        else
            rm -f -- "$HOME_DIR/.zshrc" || true
        fi
    fi

    if [[ "$LOGIN_SHELL_CHANGED" == true &&
          -n "${ORIGINAL_LOGIN_SHELL:-}" ]]; then

        if chsh -s "$ORIGINAL_LOGIN_SHELL" "$CURRENT_USER" >/dev/null 2>&1; then
            success "Previous login shell restored."
        else
            warn "Could not automatically restore the previous login shell."
            warn "Previous login shell: $ORIGINAL_LOGIN_SHELL"
        fi
    fi

    if [[ "$SHELL_ENTRY_ADDED" == true ]]; then
        warn "Zsh was added to /etc/shells during installation."
        warn "The entry was intentionally left in place."
    fi

    exit "$exit_code"
}

trap rollback ERR


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

require_command() {
    local command_name="$1"

    command -v "$command_name" >/dev/null 2>&1 ||
        die "Required command not found: $command_name"
}

is_debian_family() {
    local id="${ID:-}"
    local id_like="${ID_LIKE:-}"

    [[ "$id" == "debian" ]] && return 0
    [[ "$id" == "kali" ]] && return 0
    [[ " $id_like " == *" debian "* ]] && return 0

    return 1
}

is_ubuntu_family() {
    local id="${ID:-}"
    local id_like="${ID_LIKE:-}"

    [[ "$id" == "ubuntu" ]] && return 0
    [[ " $id_like " == *" ubuntu "* ]] && return 0

    return 1
}

get_home_directory() {
    getent passwd "$CURRENT_USER" | cut -d: -f6
}


# -----------------------------------------------------------------------------
# Environment checks
# -----------------------------------------------------------------------------

check_environment() {
    section "Checking environment"

    if [[ "${EUID}" -eq 0 ]]; then
        die "Do not run this script as root or with sudo."
    fi

    require_command id
    require_command awk
    require_command getent
    require_command grep
    require_command sudo

    if [[ ! -f /etc/os-release ]]; then
        die "/etc/os-release was not found."
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    if ! is_debian_family; then
        die "This installer is for Debian-family distributions."
        die "Detected: ${PRETTY_NAME:-unknown}"
    fi

    if is_ubuntu_family; then
        die "Ubuntu-family detected. Use ubuntu-setup.sh instead."
    fi

    CURRENT_USER="$(id -un)"
    HOME_DIR="$(get_home_directory)"

    if [[ -z "$HOME_DIR" || ! -d "$HOME_DIR" ]]; then
        die "Could not determine a valid home directory for $CURRENT_USER."
    fi

    if [[ "${HOME:-}" != "$HOME_DIR" ]]; then
        warn "HOME differs from the account database."
        warn "Using account home directory: $HOME_DIR"
    fi

    sudo -v ||
        die "sudo authentication failed."

    success "Distribution: ${PRETTY_NAME:-unknown}"
    success "User:         $CURRENT_USER"
    success "Home:         $HOME_DIR"
}


# -----------------------------------------------------------------------------
# Package installation
# -----------------------------------------------------------------------------

install_packages() {
    section "Installing required packages"

    require_command apt-get

    info "Updating APT package indexes..."

    sudo apt-get update

    info "Installing Zsh and required components..."

    sudo DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --no-install-recommends \
        "${REQUIRED_PACKAGES[@]}"

    # command-not-found is optional because availability differs between
    # Debian-family distributions and repository configurations.
    if apt-cache show command-not-found >/dev/null 2>&1; then
        if ! dpkg-query -W -f='${Status}' command-not-found 2>/dev/null |
            grep -q 'install ok installed'; then

            info "Installing optional command-not-found integration..."

            sudo DEBIAN_FRONTEND=noninteractive \
                apt-get install -y --no-install-recommends command-not-found
        fi
    else
        warn "command-not-found is unavailable in the configured repositories."
        warn "Continuing without it."
    fi

    success "Package installation completed."
}


# -----------------------------------------------------------------------------
# Dependency verification
# -----------------------------------------------------------------------------

verify_dependencies() {
    section "Verifying installed components"

    require_command zsh
    require_command curl
    require_command chsh
    require_command getent
    require_command mktemp
    require_command install

    local zsh_path
    zsh_path="$(command -v zsh)"

    [[ -x "$zsh_path" ]] ||
        die "Zsh is not executable: $zsh_path"

    [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] ||
        die "zsh-syntax-highlighting is missing."

    [[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] ||
        die "zsh-autosuggestions is missing."

    success "Zsh:                       $zsh_path"
    success "zsh-syntax-highlighting:   available"
    success "zsh-autosuggestions:       available"
}


# -----------------------------------------------------------------------------
# Download Kali configuration
# -----------------------------------------------------------------------------

download_kali_zshrc() {
    section "Downloading Kali's official .zshrc"

    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kali-like-zsh.XXXXXXXXXX")"

    local downloaded_file="$TMP_DIR/.zshrc"

    info "Source:"
    printf '       %s\n' "$KALI_ZSHRC_URL"

    if ! curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --proto '=https' \
        --tlsv1.2 \
        --retry 5 \
        --retry-delay 2 \
        --connect-timeout 10 \
        --max-time 60 \
        --max-filesize "$MAX_ZSHRC_SIZE" \
        --output "$downloaded_file" \
        "$KALI_ZSHRC_URL"; then

        die "Failed to download Kali's .zshrc."
    fi

    [[ -s "$downloaded_file" ]] ||
        die "Downloaded .zshrc is empty."

    local file_size
    file_size="$(wc -c < "$downloaded_file")"

    if (( file_size < 500 || file_size > MAX_ZSHRC_SIZE )); then
        die "Downloaded .zshrc has an unexpected size: ${file_size} bytes."
    fi

    success "Kali .zshrc downloaded."
}


# -----------------------------------------------------------------------------
# Kali configuration validation
# -----------------------------------------------------------------------------

validate_kali_zshrc() {
    section "Validating Kali's .zshrc"

    local file="$TMP_DIR/.zshrc"

    grep -q '^# START KALI CONFIG VARIABLES$' "$file" ||
        die "Kali configuration marker was not found."

    grep -q '^PROMPT_ALTERNATIVE=' "$file" ||
        die "Kali prompt configuration was not found."

    grep -q '/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' "$file" ||
        die "Kali syntax-highlighting integration was not found."

    grep -q '/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh' "$file" ||
        die "Kali autosuggestions integration was not found."

    if ! zsh -n "$file"; then
        die "Downloaded Kali .zshrc failed Zsh syntax validation."
    fi

    success "Kali .zshrc passed structural validation."
    success "Kali .zshrc passed Zsh syntax validation."
}


# -----------------------------------------------------------------------------
# Existing configuration backup
# -----------------------------------------------------------------------------

backup_existing_zshrc() {
    section "Protecting existing ~/.zshrc"

    local target="$HOME_DIR/.zshrc"

    if [[ ! -e "$target" ]]; then
        info "No existing ~/.zshrc found."
        return
    fi

    [[ -f "$target" ]] ||
        die "$target exists but is not a regular file."

    ORIGINAL_ZSHRC_EXISTS=true

    BACKUP_FILE="$HOME_DIR/.zshrc.backup.$(date '+%Y%m%d-%H%M%S').$$"

    cp --preserve=mode,ownership,timestamps \
        "$target" "$BACKUP_FILE" ||
        die "Failed to back up the existing ~/.zshrc."

    success "Backup created:"
    printf '       %s\n' "$BACKUP_FILE"
}


# -----------------------------------------------------------------------------
# Install Kali configuration
# -----------------------------------------------------------------------------

install_kali_zshrc() {
    section "Installing Kali's .zshrc"

    local source="$TMP_DIR/.zshrc"
    local staged="$TMP_DIR/.zshrc.staged"
    local target="$HOME_DIR/.zshrc"

    install -m 0644 "$source" "$staged" ||
        die "Failed to stage Kali's .zshrc."

    mv -f -- "$staged" "$target" ||
        die "Failed to install Kali's .zshrc."

    ZSHRC_INSTALLED=true

    success "Kali's .zshrc installed."
}


# -----------------------------------------------------------------------------
# Login shell configuration
# -----------------------------------------------------------------------------

configure_login_shell() {
    section "Configuring Zsh as the default login shell"

    local zsh_path
    zsh_path="$(command -v zsh)"

    if ! grep -Fxq "$zsh_path" /etc/shells; then
        info "Adding $zsh_path to /etc/shells..."

        printf '%s\n' "$zsh_path" |
            sudo tee -a /etc/shells >/dev/null

        grep -Fxq "$zsh_path" /etc/shells ||
            die "Failed to add Zsh to /etc/shells."

        SHELL_ENTRY_ADDED=true
    fi

    ORIGINAL_LOGIN_SHELL="$(
        getent passwd "$CURRENT_USER" | cut -d: -f7
    )"

    [[ -n "$ORIGINAL_LOGIN_SHELL" ]] ||
        die "Could not determine the current login shell."

    if [[ "$ORIGINAL_LOGIN_SHELL" == "$zsh_path" ]]; then
        success "Zsh is already the default login shell."
        return
    fi

    info "Current login shell: $ORIGINAL_LOGIN_SHELL"
    info "New login shell:     $zsh_path"

    chsh -s "$zsh_path" "$CURRENT_USER" ||
        die "Failed to change the default login shell."

    LOGIN_SHELL_CHANGED=true

    local resulting_shell
    resulting_shell="$(
        getent passwd "$CURRENT_USER" | cut -d: -f7
    )"

    [[ "$resulting_shell" == "$zsh_path" ]] ||
        die "Could not verify the new login shell."

    success "Zsh is now the default login shell."
}


# -----------------------------------------------------------------------------
# Final verification
# -----------------------------------------------------------------------------

final_verification() {
    section "Final verification"

    local zsh_path
    local login_shell

    zsh_path="$(command -v zsh)"
    login_shell="$(
        getent passwd "$CURRENT_USER" | cut -d: -f7
    )"

    [[ "$login_shell" == "$zsh_path" ]] ||
        die "Final login-shell verification failed."

    [[ -f "$HOME_DIR/.zshrc" ]] ||
        die "$HOME_DIR/.zshrc does not exist."

    zsh -n "$HOME_DIR/.zshrc" ||
        die "Installed ~/.zshrc failed final Zsh syntax validation."

    [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] ||
        die "Syntax-highlighting verification failed."

    [[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] ||
        die "Autosuggestions verification failed."

    success "Login shell:             $login_shell"
    success "Kali ~/.zshrc:           valid"
    success "Syntax highlighting:     installed"
    success "Autosuggestions:         installed"
}


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    printf '\n'
    printf '\033[1;35m============================================\033[0m\n'
    printf '\033[1;35m       Kali-like Terminal Zsh Setup        \033[0m\n'
    printf '\033[1;35m          Debian-family installer           \033[0m\n'
    printf '\033[1;35m============================================\033[0m\n'

    check_environment
    install_packages
    verify_dependencies
    download_kali_zshrc
    validate_kali_zshrc
    backup_existing_zshrc
    install_kali_zshrc
    configure_login_shell
    final_verification

    printf '\n'
    printf '\033[1;32mInstallation completed successfully.\033[0m\n\n'

    printf 'Log out and log back in to start using Zsh automatically.\n'
    printf 'Or test immediately with:\n\n'
    printf '  \033[1;36mexec zsh\033[0m\n\n'

    if [[ -n "${BACKUP_FILE:-}" ]]; then
        printf 'Previous ~/.zshrc backup:\n'
        printf '  \033[1;36m%s\033[0m\n\n' "$BACKUP_FILE"
    fi
}

main "$@"
```
