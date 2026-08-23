# Ubuntu → Kali Terminal Zsh

Make an Ubuntu terminal look and behave like the **Kali Linux terminal** by using Kali Linux's own Zsh configuration.

This project does **not** install Kali Linux or replace Ubuntu. It installs Zsh and the required Zsh components, downloads Kali's official `.zshrc`, and configures Zsh as the default login shell.

## What it does

The `setup.sh` script automatically:

* Installs `zsh`
* Installs `zsh-syntax-highlighting`
* Installs `zsh-autosuggestions`
* Installs `command-not-found`
* Installs `curl`
* Backs up an existing `~/.zshrc`
* Downloads Kali Linux's current `.zshrc`
* Verifies that the downloaded configuration is Kali's `.zshrc`
* Configures Zsh as the user's default login shell
* Verifies the required Zsh components

The script uses Kali's actual configuration instead of recreating the Kali prompt with Oh My Zsh or Powerlevel10k.

## Requirements

* Ubuntu or an Ubuntu-based distribution
* A normal user account with `sudo` privileges
* Internet connection
* `sudo` access

Do **not** run the setup script with `sudo`.

## Installation

Clone the repository:

```bash
git clone https://github.com/reduxailabs-max/ubuntu-to-kali-teminal-zsh.git
cd ubuntu-to-kali-teminal-zsh
```

Make the script executable:

```bash
chmod +x setup.sh
```

Run it:

```bash
./setup.sh
```

The script will ask for your `sudo` password when necessary.

## After installation

The script changes your login shell to Zsh.

Log out and log back in, then open a new terminal.

You can verify your default shell with:

```bash
echo $SHELL
```

You should see:

```text
/usr/bin/zsh
```

You can also verify the shell currently running:

```bash
echo $0
```

Expected:

```text
zsh
```

### Test without logging out

You can immediately start Zsh in the current terminal:

```bash
exec zsh
```

## What gets installed

The setup uses Ubuntu's packages for the components required by Kali's Zsh configuration:

| Package                   | Purpose                                         |
| ------------------------- | ----------------------------------------------- |
| `zsh`                     | Z shell                                         |
| `zsh-syntax-highlighting` | Command syntax highlighting                     |
| `zsh-autosuggestions`     | History-based command suggestions               |
| `command-not-found`       | Suggests packages when a command is unavailable |
| `curl`                    | Downloads Kali's `.zshrc`                       |

## Kali configuration

The script downloads Kali Linux's `.zshrc` directly from the Kali Linux `kali-defaults` repository:

```text
https://gitlab.com/kalilinux/packages/kali-defaults/-/raw/kali/master/etc/skel/.zshrc
```

This means the project does not maintain a copied version of Kali's configuration.

When the Kali configuration changes, running the setup script again downloads the current version.

## Existing `.zshrc` protection

If you already have a `~/.zshrc`, the script creates a timestamped backup before replacing it.

Example:

```text
~/.zshrc.backup.20260824-235000
```

Your existing configuration is therefore not silently discarded.

## No Oh My Zsh

This project intentionally does **not** install:

* Oh My Zsh
* Powerlevel10k
* Other third-party Zsh themes

The goal is to use **Kali Linux's own Zsh configuration**, rather than imitate it with another framework.

## Architecture

The resulting environment is essentially:

```text
Ubuntu
│
├── Zsh
│   │
│   ├── Kali's .zshrc
│   │
│   ├── zsh-syntax-highlighting
│   │
│   └── zsh-autosuggestions
│
└── Ubuntu terminal emulator
```

The terminal emulator itself remains Ubuntu's existing terminal application. The shell running inside it becomes Zsh.

## Re-running the script

The script can safely be run again.

When rerun, it will:

1. Install/update the required packages.
2. Back up the current `~/.zshrc`.
3. Download the current Kali `.zshrc`.
4. Verify the configuration.
5. Ensure Zsh is the default login shell.

For future installations, simply clone the repository and run:

```bash
git clone https://github.com/reduxailabs-max/ubuntu-to-kali-teminal-zsh.git
cd ubuntu-to-kali-teminal-zsh
chmod +x setup.sh
./setup.sh
```

## Restore your previous `.zshrc`

If you want to restore your previous configuration, find the backup:

```bash
ls -lt ~/.zshrc.backup.*
```

Then restore the desired backup:

```bash
cp ~/.zshrc.backup.YYYYMMDD-HHMMSS ~/.zshrc
```

## Restore Bash as the default shell

If you want to return to Bash:

```bash
chsh -s /bin/bash
```

Then log out and log back in.

Verify:

```bash
echo $SHELL
```

Expected:

```text
/bin/bash
```

## Source

Kali Linux's Zsh configuration:

https://gitlab.com/kalilinux/packages/kali-defaults/-/blob/kali/master/etc/skel/.zshrc

## License

This project contains an installation script and downloads Kali Linux's configuration from the official Kali Linux repository at installation time.

Kali Linux and its associated configuration are maintained by the Kali Linux project.
