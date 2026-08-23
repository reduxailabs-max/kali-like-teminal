#!/usr/bin/env bash

set -e

echo "========================================="
echo " Ubuntu → Kali-style Terminal Setup"
echo "========================================="

# Must not run as root
if [ "$EUID" -eq 0 ]; then
    echo "ERROR: Do not run this script with sudo."
    echo "Run it as your normal user."
    exit 1
fi

echo
echo "[1/6] Installing required packages..."

sudo apt update
sudo apt install -y \
    zsh \
    zsh-syntax-highlighting \
    zsh-autosuggestions \
    command-not-found \
    curl

echo
echo "[2/6] Backing up existing ~/.zshrc..."

if [ -f "$HOME/.zshrc" ]; then
    BACKUP="$HOME/.zshrc.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$HOME/.zshrc" "$BACKUP"
    echo "Backup created: $BACKUP"
fi

echo
echo "[3/6] Downloading Kali's official .zshrc..."

KALI_ZSHRC_URL="https://gitlab.com/kalilinux/packages/kali-defaults/-/raw/kali/master/etc/skel/.zshrc"

curl -fL "$KALI_ZSHRC_URL" -o "$HOME/.zshrc"

chmod 644 "$HOME/.zshrc"

echo
echo "[4/6] Verifying Kali .zshrc..."

if ! grep -q "PROMPT_ALTERNATIVE" "$HOME/.zshrc"; then
    echo "ERROR: Downloaded file does not appear to be Kali's .zshrc."
    exit 1
fi

echo "Kali .zshrc verified."

echo
echo "[5/6] Setting Zsh as the default login shell..."

ZSH_PATH="$(command -v zsh)"

if ! grep -qx "$ZSH_PATH" /etc/shells; then
    echo "$ZSH_PATH is not listed in /etc/shells."
    echo "Adding it..."
    echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
fi

CURRENT_LOGIN_SHELL="$(getent passwd "$USER" | cut -d: -f7)"

if [ "$CURRENT_LOGIN_SHELL" != "$ZSH_PATH" ]; then
    chsh -s "$ZSH_PATH"
    echo "Default shell changed to: $ZSH_PATH"
else
    echo "Zsh is already your default shell."
fi

echo
echo "[6/6] Verifying installation..."

echo
echo "Zsh:"
zsh --version

echo
echo "Syntax highlighting:"
if [ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
    echo "OK"
else
    echo "WARNING: zsh-syntax-highlighting not found."
fi

echo
echo "Autosuggestions:"
if [ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
    echo "OK"
else
    echo "WARNING: zsh-autosuggestions not found."
fi

echo
echo "Kali .zshrc:"
echo "OK"

echo
echo "========================================="
echo " Installation complete!"
echo "========================================="
echo
echo "Your default login shell is now:"
getent passwd "$USER" | cut -d: -f7

echo
echo "IMPORTANT:"
echo "Log out and log back in, then open a new terminal."
echo
echo "Or test immediately with:"
echo "    exec zsh"
echo
