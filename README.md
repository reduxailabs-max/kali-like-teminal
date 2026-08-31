# kali-like-teminal

A production-ready installer for getting a **Kali-like Zsh terminal experience** on supported Ubuntu-family and Debian-family systems.

> This project configures your shell experience only.
> It does **not** install Kali Linux, replace your OS, or install Kali penetration-testing tools.

---

## What this project does

- Detects whether your system is in the Ubuntu-family or Debian-family
- Installs required Zsh packages using APT
- Downloads Kali Linux's current upstream `.zshrc` from `kali-defaults`
- Validates downloaded content before applying it
- Backs up your existing `~/.zshrc`
- Installs the upstream Kali config as a managed file in your home directory
- Installs a small marker-managed `~/.zshrc` wrapper that auto-loads `~/.profile` and `~/.bashrc` (best-effort), then sources Kali upstream and persistent user overrides
- Sets your default login shell to Zsh (if not already)
- Performs final consistency checks

## What this project does **not** do

- Does not install Kali Linux
- Does not install Kali metapackages or pentesting tools
- Does not replace your desktop environment
- Does not replace your terminal emulator
- Does not change unrelated system configuration
- Does not use Oh My Zsh, Powerlevel10k, Starship, or other unrelated frameworks

---

## Supported systems

This repository ships two installers:

- `ubuntu-setup.sh` → Ubuntu-family systems
- `debian-setup.sh` → Debian-family systems (non-Ubuntu)

Detection is based on `/etc/os-release` (`ID`, `ID_LIKE`) and explicit family checks.
Unsupported systems fail safely with a clear message.

### Typical Ubuntu-family examples

- Ubuntu
- Linux Mint (Ubuntu edition)
- Pop!_OS
- Zorin OS

### Typical Debian-family examples

- Debian
- Kali Linux
- LMDE
- MX Linux

---

## Requirements

- Linux system in supported family
- APT package manager
- Non-root user account
- `sudo` privileges
- Internet access to:
  - `gitlab.com` (Kali upstream source)
  - APT repositories configured on your system

---

## Installation

Clone the repository:

```bash
git clone https://github.com/reduxailabs-max/kali-like-teminal.git
cd kali-like-teminal
```

Make scripts executable:

```bash
chmod +x ubuntu-setup.sh debian-setup.sh
```

Run the correct installer:

### Ubuntu-family

```bash
./ubuntu-setup.sh
```

### Debian-family

```bash
./debian-setup.sh
```

> Run as your normal user. Do **not** run with `sudo`.

---

## Upstream Kali configuration source

This project uses Kali's official upstream `.zshrc` from `kali-defaults`:

- Project: <https://gitlab.com/kalilinux/packages/kali-defaults>
- File (browser): <https://gitlab.com/kalilinux/packages/kali-defaults/-/blob/kali/master/etc/skel/.zshrc>
- Raw download URL used by installers:  
  <https://gitlab.com/kalilinux/packages/kali-defaults/-/raw/kali/master/etc/skel/.zshrc>

The repository intentionally does **not** keep a forked copy of Kali's `.zshrc`.
Each run fetches the current upstream version.

---

## Installation flow

The installer follows a controlled sequence:

1. Environment checks and distribution-family validation
2. `sudo` authentication check
3. APT update and dependency installation
4. Runtime dependency verification
5. Secure HTTPS download of upstream `.zshrc`
6. Content and syntax validation (`zsh -n`)
7. Backup of existing `~/.zshrc`
8. Managed install of upstream file
9. Install of `~/.zshrc` wrapper
10. Set login shell to Zsh
11. Final verification

---

## What is installed

Required packages:

- `zsh`
- `zsh-syntax-highlighting`
- `zsh-autosuggestions`
- `curl`

Optional (if available in your repositories):

- `command-not-found`

Managed files created in your home directory:

- `~/.local/share/kali-like-terminal/kali-upstream.zshrc` (downloaded upstream config)
- `~/.zshrc` (generated marker-managed wrapper)
- `~/.config/kali-like-terminal/user-overrides.zsh` (persistent user customizations loaded after Kali upstream config)
- `~/.config/kali-like-terminal/migrations/` (archives for legacy unmanaged `~/.zshrc` when manual review is safer)
- `~/.local/state/kali-like-terminal/state` (migration state for idempotent re-runs)

Backups:

- `~/.local/state/kali-like-terminal/backups/zshrc.<timestamp>.<pid>.bak`

---

## Safety and rollback behavior

- Existing `~/.zshrc` is backed up before replacement
- Installer uses strict Bash mode (`set -Eeuo pipefail`)
- Temporary files are isolated in `mktemp` directories
- On failure during critical stages, installer attempts rollback:
  - Restore previous `~/.zshrc`
  - Restore previous login shell (if changed)
  - Restore previous managed upstream file (when applicable)

If rollback cannot complete automatically, the installer tells you exactly where your backup is.

---

## Idempotency and repeated runs

You can safely re-run the installer.

Each run converges to the same intended final state:

- packages present
- latest upstream Kali `.zshrc` downloaded
- wrapper + managed file + persistent overrides in place
- prior custom content migrated once per unique previous `~/.zshrc` hash
- login shell set to Zsh

A new backup is created whenever a pre-existing `~/.zshrc` is present.

---

## Verify installation

Check login shell from account database:

```bash
getent passwd "$USER" | cut -d: -f7
```

Check current shell process:

```bash
echo "$0"
```

Check default shell environment variable in new session:

```bash
echo "$SHELL"
```

Check Zsh version:

```bash
zsh --version
```

Start immediately without logout:

```bash
exec zsh
```

---

## Restore previous shell/configuration

### Restore previous `~/.zshrc`

List backups:

```bash
ls -lt ~/.local/state/kali-like-terminal/backups/
```

Restore one backup:

```bash
cp ~/.local/state/kali-like-terminal/backups/<backup-file> ~/.zshrc
```

### Return default shell to Bash

```bash
chsh -s /bin/bash
```

Then log out and log back in.

---

## Troubleshooting

### "Unsupported distribution"

Use the correct installer for your family. If your distro is unusual, inspect `/etc/os-release` and open an issue with details.

### `sudo` authentication failed

Ensure your user has sudo privileges and retry.

### APT install failed

Check network connectivity, repository configuration, and package availability. Re-run the installer after fixing APT.

### Upstream download/validation failed

This can happen with temporary network issues or upstream format changes. Retry first. If persistent, open an issue with installer output.

### `chsh` failed

Your environment may restrict shell changes (policy/SSO/container). The rest of the installation may still be present; you can run `zsh` manually.

### Legacy `.bashrc` / `.profile` warning appears

The generated `~/.zshrc` tries to load both files automatically so `source ~/.zshrc` is usually enough. If a file contains Bash-specific constructs that are not fully compatible with Zsh, the wrapper continues and prints a warning.

### I reinstalled and want to keep my custom `~/.zshrc` additions

The installer now migrates custom content into:

- `~/.config/kali-like-terminal/user-overrides.zsh`

Migration behavior:

- Marker-managed old wrappers: non-managed lines outside the managed block are imported automatically.
- Legacy wrappers from earlier project versions: custom lines are extracted and imported when safely parseable.
- Unmanaged legacy `~/.zshrc`: archived in `~/.config/kali-like-terminal/migrations/` for manual review (not auto-executed for safety).

This keeps reinstalls fresh while preserving user customizations safely.

---

## Limitations

- This project depends on Kali upstream `.zshrc` behavior at installation time
- Validation is defensive but not cryptographic signature verification
- Family detection is robust but cannot guarantee support for every derivative distro variant
- Some environments (enterprise policy, containers, restricted PAM/chsh) may block default shell changes

---

## Project structure

```text
kali-like-teminal/
├── ubuntu-setup.sh
├── debian-setup.sh
├── README.md
└── LICENSE
```

---

## Relationship to Kali Linux

This project is an independent installer utility.
It is **not** an official Kali Linux project.

It consumes Kali upstream shell configuration from the official `kali-defaults` repository to provide a Kali-like terminal experience on supported systems.

---

## License and third-party distinction

- Installer code in this repository is licensed under the MIT License (see `LICENSE`).
- Kali upstream `.zshrc` is not distributed as a vendored copy in this repo; it is downloaded at install time from Kali's official source and remains subject to Kali's own licensing/ownership terms.
