````markdown
# Kali-like Terminal Zsh

Make an Ubuntu-family or Debian-family Linux terminal **look and behave like a Kali Linux terminal** by using Kali Linux's own Zsh configuration.

This project does **not** install Kali Linux, replace your operating system, or install the Kali penetration-testing toolset.

Instead, it installs Zsh and the components expected by Kali's official `.zshrc`, downloads the current Kali configuration, validates it, safely backs up your existing configuration, and makes Zsh your default login shell.

## Features

- Uses Kali Linux's official `.zshrc`
- Kali-style two-line prompt
- Kali prompt symbol (`㉿`)
- Zsh native completion
- Zsh history configuration
- `zsh-syntax-highlighting`
- `zsh-autosuggestions`
- Kali-style aliases and terminal colors
- Terminal title integration
- Optional `command-not-found` integration
- Existing `~/.zshrc` is backed up before replacement
- Downloaded `.zshrc` is validated before installation
- Downloaded `.zshrc` is checked with `zsh -n`
- Temporary-file based installation
- Failure rollback for user configuration and login shell
- Automatically configures Zsh as the default login shell
- Safe to run again
- No Oh My Zsh
- No Powerlevel10k
- No Starship

## Supported systems

This project provides two installers.

### Ubuntu-family distributions

Use:

```bash
./ubuntu-setup.sh
````

The installer detects Ubuntu-family systems through `/etc/os-release` and supports APT-based Ubuntu derivatives.

Examples include:

* Ubuntu
* Linux Mint
* Pop!_OS
* Zorin OS
* Other Ubuntu-family APT distributions

### Debian-family distributions

Use:

```bash
./debian-setup.sh
```

The installer detects Debian-family systems through `/etc/os-release`.

Examples include:

* Debian
* Kali Linux
* Linux Mint Debian Edition
* MX Linux
* Other Debian-family APT distributions

Ubuntu-family systems are intentionally rejected by `debian-setup.sh`.

## Requirements

* Ubuntu-family or Debian-family Linux distribution
* APT package manager
* Normal user account
* `sudo` privileges
* Internet connection
* HTTPS access to GitLab

Do **not** run the installers with `sudo`.

Run them as your normal user. Administrative operations are performed through `sudo` when required.

## Installation

Clone the repository:

```bash
git clone https://github.com/reduxailabs-max/kali-like-teminal.git
cd kali-like-teminal
```

### Ubuntu or Ubuntu-based distribution

```bash
chmod +x ubuntu-setup.sh
./ubuntu-setup.sh
```

### Debian or Debian-based distribution

```bash
chmod +x debian-setup.sh
./debian-setup.sh
```

The installer will request your `sudo` password when necessary.

## What the installer does

The installation process is deliberately ordered so that the user's existing shell configuration is protected before it is replaced.

```text
Detect distribution
        │
        ▼
Verify environment
        │
        ▼
Install required packages
        │
        ▼
Verify Zsh dependencies
        │
        ▼
Download Kali's .zshrc
        │
        ▼
Validate downloaded file
        │
        ▼
Validate Zsh syntax
        │
        ▼
Back up existing ~/.zshrc
        │
        ▼
Install Kali's .zshrc
        │
        ▼
Ensure Zsh is in /etc/shells
        │
        ▼
Set Zsh as login shell
        │
        ▼
Final verification
```

If an important installation step fails, the installer attempts to restore the previous `~/.zshrc` and login shell.

## What gets installed

| Package                   | Purpose                                |
| ------------------------- | -------------------------------------- |
| `zsh`                     | Z shell                                |
| `zsh-syntax-highlighting` | Command syntax highlighting            |
| `zsh-autosuggestions`     | History-based command suggestions      |
| `curl`                    | Downloads Kali's `.zshrc`              |
| `command-not-found`       | Optional command-not-found integration |

The Kali `.zshrc` itself uses Zsh's built-in completion system (`compinit`) rather than Oh My Zsh or another completion framework.

## Kali `.zshrc`

The installer downloads Kali's configuration directly from the official Kali Linux `kali-defaults` repository:

https://gitlab.com/kalilinux/packages/kali-defaults/-/blob/kali/master/etc/skel/.zshrc

Raw source:

https://gitlab.com/kalilinux/packages/kali-defaults/-/raw/kali/master/etc/skel/.zshrc

The repository intentionally does not maintain its own copy of Kali's `.zshrc`.

As a result, running the installer again retrieves the current version from Kali.

## Why no Oh My Zsh?

The goal of this project is to use **Kali Linux's actual Zsh configuration**.

Kali's configuration already provides its own:

* Prompt
* Completion configuration
* History settings
* Key bindings
* Syntax-highlighting configuration
* Autosuggestion integration
* Aliases
* Terminal title handling
* Color configuration

Therefore this project does not add:

* Oh My Zsh
* Powerlevel10k
* Starship
* Other third-party prompt frameworks

## Existing `~/.zshrc`

If you already have a `~/.zshrc`, it is backed up before the Kali configuration is installed.

Example:

```text
~/.zshrc.backup.20260824-235000.12345
```

List your backups:

```bash
ls -lt ~/.zshrc.backup.*
```

Restore one:

```bash
cp ~/.zshrc.backup.YYYYMMDD-HHMMSS.PID ~/.zshrc
```

## After installation

The current terminal process does not automatically change shells.

The recommended procedure is:

1. Log out.
2. Log back in.
3. Open a new terminal.

Or test immediately:

```bash
exec zsh
```

## Verify the default shell

Check the configured login shell:

```bash
echo "$SHELL"
```

Expected:

```text
/usr/bin/zsh
```

Check the shell currently running:

```bash
echo "$0"
```

Expected:

```text
zsh
```

Check the installed version:

```bash
zsh --version
```

## Restore Bash

To return to Bash:

```bash
chsh -s /bin/bash
```

Then log out and log back in.

Verify:

```bash
echo "$SHELL"
```

Expected:

```text
/bin/bash
```

## Re-running the installer

The installers are designed to be safely rerunnable.

A subsequent run will:

1. Detect the operating-system family.
2. Verify the environment.
3. Update package metadata.
4. Install or verify dependencies.
5. Download the current Kali `.zshrc`.
6. Validate the configuration.
7. Back up the current `~/.zshrc`.
8. Install the new Kali configuration.
9. Ensure Zsh is the login shell.
10. Verify the final state.

A new backup is created on each run.

## Validation and safety

Before installing Kali's `.zshrc`, the installer performs several checks.

### HTTPS download

The configuration is downloaded over HTTPS.

### Download limits

The installer enforces a maximum download size to prevent an unexpected response from being written indefinitely.

### Structural validation

The downloaded file must contain expected Kali configuration markers and integrations.

### Zsh syntax validation

The file is checked using:

```bash
zsh -n
```

This validates the shell syntax without executing the configuration.

### Existing configuration backup

An existing `~/.zshrc` is preserved before replacement.

### Rollback

If a later installation step fails, the installer attempts to restore:

* The previous `~/.zshrc`
* The previous login shell

## Security considerations

This project intentionally downloads an executable shell configuration from the Kali Linux GitLab repository.

A `.zshrc` is shell code and is executed when Zsh starts.

Therefore, installing this project means trusting the upstream Kali Linux `kali-defaults` repository at installation time.

The installer performs validation, but validation is **not a cryptographic authenticity guarantee**.

For a stronger supply-chain model, a future version could support a pinned Kali Git commit and verify a known SHA-256 checksum.

## Project structure

```text
kali-like-teminal/
├── ubuntu-setup.sh
├── debian-setup.sh
└── README.md
```

### `ubuntu-setup.sh`

Installer for Ubuntu-family APT distributions.

### `debian-setup.sh`

Installer for Debian-family APT distributions.

## Example result

After installation, the Zsh prompt follows Kali's own prompt configuration, for example:

```text
┌──(user㉿hostname)-[~/directory]
└─$
```

The exact appearance can vary depending on the terminal, username, hostname, working directory, terminal color support, and environment.

## Important distinction

This project creates a **Kali-like terminal environment**.

It does not turn the operating system into Kali Linux.

For example:

```text
Ubuntu
  └── GNOME Terminal
       └── Zsh
            └── Kali .zshrc
```

The underlying operating system and terminal emulator remain unchanged.

## Source

Kali Linux `kali-defaults`:

https://gitlab.com/kalilinux/packages/kali-defaults

Kali Linux `.zshrc`:

https://gitlab.com/kalilinux/packages/kali-defaults/-/blob/kali/master/etc/skel/.zshrc

## License

This repository contains installation scripts that retrieve Kali Linux's Zsh configuration from the official Kali Linux repository.

Kali Linux and its associated components are maintained by the Kali Linux project.

```
```
