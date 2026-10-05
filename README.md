<p align="center">
  <img src="https://img.shields.io/github/v/release/RuthvikUpputuri/dam?style=for-the-badge&color=blue&label=version" alt="Latest Version">
  <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" alt="MIT License">
  <img src="https://img.shields.io/badge/bash-4.4%2B-orange?style=for-the-badge&logo=gnubash&logoColor=white" alt="Bash 4.4+">
  <img src="https://img.shields.io/badge/docker-compose-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker Compose">
  <img src="https://img.shields.io/badge/platform-linux-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Linux">
</p>

<h1 align="center">DAM - Docker App Manager</h1>

<p align="center">
  <strong>A powerful, centralized lifecycle manager for Docker Compose applications.</strong>
</p>

<p align="center">
  <em>Start, stop, update, and clean multiple Docker Compose stacks safely, efficiently and intelligently from anywhere - by name, in bulk, with one command.</em>
</p>

<p align="center">
  Built for sysadmins, hobbyists, and self-hosters who love the CLI but hate <code>cd</code>-ing into every stack folder just to manage apps.
</p>

<p align="center">
  <a href="#getting-started">Getting Started</a> ·
  <a href="#usage">Usage</a> ·
  <a href="#commands-reference">Commands</a> ·
  <a href="#configuration">Configuration</a> ·
  <a href="#how-it-works">How It Works</a> ·
  <a href="#advanced-topics">Advanced</a> ·
  <a href="docs/">Full Documentation</a>
</p>

---

<details>
<summary><strong>Table of Contents</strong></summary>

- [What is DAM?](#what-is-dam)
- [Why DAM?](#why-dam)
- [Features](#features)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Quick Install](#quick-install)
  - [Manual / One-off Use](#manual--one-off-use)
  - [Verify Installation](#verify-installation)
- [Usage](#usage)
  - [App Selection Syntax](#app-selection-syntax)
  - [Everyday Examples](#everyday-examples)
- [Commands Reference](#commands-reference)
  - [Lifecycle Actions](#lifecycle-actions)
  - [Update](#update)
  - [Cleanup](#cleanup)
  - [Status, List & Get](#status-list--get)
  - [Logs](#logs)
  - [System Commands](#system-commands)
- [Configuration](#configuration)
  - [Search Directories](#search-directories)
  - [Exclude Folders](#exclude-folders)
  - [Custom Command Name](#custom-command-name)
  - [Config File](#config-file)
  - [Environment / Script Options](#environment--script-options)
- [How It Works](#how-it-works)
  - [App Discovery](#app-discovery)
  - [Compose Detection](#compose-detection)
  - [Custom Update Scripts](#custom-update-scripts)
  - [Safety Guards](#safety-guards)
- [Advanced Topics](#advanced-topics)
  - [Self-Update](#self-update)
  - [Reconfigure](#reconfigure)
  - [Uninstall](#uninstall)
  - [Running Without Installation](#running-without-installation)
  - [Non-Interactive / Automation](#non-interactive--automation)
  - [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)
- [Credits](#credits)

</details>

---

## What is DAM?

**DAM** (Docker App Manager) is a single Bash script that acts as a centralized lifecycle manager for multiple Docker Compose applications.

Instead of:

```bash
cd ~/stacks/<app2> && docker compose up -d
cd ~/stacks/<app-name> && docker compose pull && docker compose up -d
cd ~/stacks/<app3> && docker compose restart
# …and so on for every app
```

you can do:

```bash
start all except <app3>
update <app-name> <app-name-2>
restart <app2>
cleanup vol
```

from **any directory**.

DAM discovers your app folders, finds the correct `compose.yaml` / `docker-compose.yml`, runs the right `docker compose` (or `docker-compose`) commands, supports bulk operations with exclusions, includes limited cleanup conveniences, and offers a safe install with short global commands.

> **NOTE:** DAM focuses on lifecycle management for Docker Compose application stacks; it is not a second Docker CLI or a replacement for Docker. It finds apps by directory name and runs common app-scoped operations without requiring you to navigate to each project directory. The existing `cleanup` command is a limited convenience for common host-wide prune operations, not a general Docker resource-management interface. Use Docker's native CLI for operations like `exec`, `inspect`, `cp`, or specialized maintenance.

---

## Why DAM?

| Problem | DAM solution |
| :------ | :----------- |
| Constantly `cd` into stack directories | Run commands from anywhere by app name |
| Updating 10+ apps one by one | `update all` or `update all except <app3>` |
| Forgetting which apps exist | Built-in listing + real-time status |
| Accidental volume/network deletes | Explicit confirmations + opt-in cleanup modes |
| Different compose file names | Auto-detects `compose.yaml`, `compose.yml`, `docker-compose.yaml`, `docker-compose.yml` |
| Custom update logic per app | Supports `update*.sh` scripts in the app folder |
| Want short commands | Install once → use `start`, `stop`, `update`, … (or with a custom prefix like `dkr`) |

It is intentionally focused on **one compose project per folder** which is the pattern used by most self-hosters and hobby setups.

---

## Features

- **Bulk lifecycle control** - start, stop, kill, restart, recreate, force-recreate, pause, unpause, delete
- **Smart app selection**
  - `all`
  - `all except app1 app2`
  - one or more specific apps
- **Smart updates** - pull images, build with fresh base images, recreate - or run a custom `update*.sh` if present. Stopped apps are left stopped.
- **Basic optional cleanup** - an existing convenience for common host-wide prune operations, with confirmations for destructive modes
- **Global install** - system-wide commands + config under `/etc`
- **Configurable search paths** - default locations or your own directories
- **Exclude folders** - ignore directories named e.g. `recovered`, `unused`
- **Colored, structured output** - clear per-app sections and a final summary
- **Confirmation prompts** on destructive bulk actions (bypass with `-y` / `--yes`)
- **Self-update** - pull the latest script from the repository with optional SHA-256 verification
- **Works with both** `docker compose` (v2 plugin) and legacy `docker-compose`
- **Scriptable** - `get` command for extracting raw container data for automation

---

## Getting Started

### Prerequisites

| Requirement | Notes |
| :---------- | :---- |
| **Bash 4.4+** | Required (empty-array expansion under `set -u`) |
| **Docker** | Daemon must be running and accessible by your user |
| **Docker Compose** | Either the v2 plugin (`docker compose`) or standalone `docker-compose` |
| **column** | Part of `util-linux`; used by `list`, `get`, and `status` for table formatting |
| **Linux** (primary) | Tested on common Linux distributions; other Unix-like systems may work |

Check versions:

```bash
bash --version
docker --version
docker compose version   # or: docker-compose --version
```

### Quick Install

Run the one-line installation script. This will automatically download the latest version, make it executable, and trigger the interactive setup:

```bash
sudo curl -fsSL https://gh.upputuri.in/dam.sh -o /tmp/dam.sh && sudo chmod +x /tmp/dam.sh && sudo /tmp/dam.sh install && rm /tmp/dam.sh
```

The installer will:

- Ask which directories contain your Docker Compose apps (defaults suggested)
- Let you set folder names to always exclude
- Let you choose a global command name (default: `dkr`, or `none` for raw commands like `start` / `stop`)
- Configure whether custom `update*.sh` scripts run automatically or require confirmation
- Copy the temporary quick-install download to `/usr/local/bin/docker-app-manager` and create command symlinks
- Write configuration to `/etc/docker-app-manager.conf`

After installation you can use the commands from anywhere.

### Manual / One-off Use

You can run the script without installing:

```bash
./dam.sh start <app2>
./dam.sh update all except <app3>
./dam.sh cleanup
```

When not installed, DAM looks for apps in these default locations (if they exist):

- `/opt/stacks`
- `/opt/projects`
- `~/apps`
- `~/stacks`

### Verify Installation

```bash
# If you chose a custom name (e.g. dkr):
dkr list
dkr status all

# If you chose "none" (raw commands):
list
status all
```

You should see an inventory of discovered apps and their running state.

---

## Usage

### App Selection Syntax

The same selection syntax works for almost every action:

| Pattern | Meaning |
| :------ | :------ |
| `<action> all [using files...]` | Every discovered app |
| `<action> all except app1 app2 [using files...]` | Every app except the listed ones |
| `<action> app1 [using files...]` | Single app |
| `<action> app1 app2 app3 [using files...]` | Multiple specific apps |

Optional modifiers:

- Append `using <file1> <file2>...` to explicitly specify which Compose files to use (e.g. `using compose.yaml compose.override.yaml`). It automatically resolves shorthand names (e.g., `dev` to `dev.yaml` or `compose.dev.yaml`).
  - If none of the requested files resolve, `stop`, `recreate`, `force-recreate`, and `delete` fail rather than using the default Compose file. Other Compose actions fall back to their default Compose file. If at least one file resolves, DAM runs with only the matched files and warns about the missing ones.
- Append `with vol`, `with net`, `with buildx`, `with img`, or `with all` on **delete** to trigger extended cleanup.
- Use `-y` or `--yes` to skip confirmation prompts (especially important for `delete all` and volume/image prunes).

**Note:** App names and paths must **not** contain spaces. App names are derived from the directory name. So if you have a folder named `<app-name>`, the app name will be `<app-name>`. If you have a folder named `<app-name>-old`, the app name will be `<app-name>-old`.

### Everyday Examples

```bash
# Start everything except specific apps
start all except <app3>

# Restart a couple of apps
restart <app2> <app-name>

# Pull latest images and recreate
update <app-name> <app-name-2> <app3>

# Start an app using specific compose files (resolves 'dev' to 'dev.yaml' or 'compose.dev.yaml', etc.)
start <app-name> using compose dev prod

# Full recreate of one stack
recreate <app4>

# Force recreate (immediate kill + --force-recreate)
force-recreate <app3>
# or the short alias:
frec <app3>

# Remove an app stack (containers + networks); volumes kept by default
delete <app4>

# Remove an app and also prune its volumes
delete <app4> with vol

# View logs for an app (last 100 lines)
dkr logs <app-name> last 100

# Stream logs live with timestamps
dkr logs <app-name> live time

# View the first 50 lines of logs
dkr logs <app-name> first 50

# Get raw container IDs for scripting
dkr get <app-name> cid

# Get container info for a specific service
dkr get <app-name>:postgres vol

# Clean only dangling images
cleanup

# Clean dangling images + unused volumes (asks for confirmation)
cleanup vol

# Aggressive cleanup (images, networks, volumes, build cache)
cleanup all -y

# See what is running
status all
status <app-name> <app3>
```

---

## Commands Reference

> 📖 **Full reference:** [docs/commands.md](docs/commands.md) - includes exact underlying Docker commands for every DAM action.

### Lifecycle Actions

| Command | What It Actually Runs |
| :------ | :-------------------- |
| `start` | `docker compose up -d` (creates + starts containers) |
| `stop` | `docker compose stop` |
| `kill` | `docker compose kill` |
| `restart` | `docker compose restart` |
| `recreate` | `docker compose down --remove-orphans` → `docker compose up -d` |
| `force-recreate` / `frec` | `docker compose down --remove-orphans -t 0` → `docker compose up -d --force-recreate` |
| `pause` | `docker compose pause` |
| `unpause` | `docker compose unpause` |
| `delete` | `docker compose down --remove-orphans` (optionally with `-v` / `--rmi all`) → dangling cleanup |

> ⚠️ **Important:** DAM's `start` uses `docker compose up -d`, **not** `docker compose start`. This means it will create containers if they don't exist and apply configuration changes. See [DAM vs Docker](docs/docker-vs-dam.md) for details.

### Update

```bash
update <selection>
```

Behavior per app:

1. If an `update*.sh` script exists in the app directory **and** custom update scripts are allowed → run that script.
2. Otherwise:
   - `docker compose pull --ignore-buildable` (pulls remote images, skips buildable services)
   - `docker compose build --pull` (rebuilds with fresh base images)
   - `docker compose up -d` (recreates containers - **only if app was running**; stopped apps stay stopped)
3. After all apps: dangling image cleanup.

> 📖 **Full details:** [docs/updates.md](docs/updates.md)

### Cleanup

```bash
cleanup [net|buildx|vol|img|all] [-y]
```

| Argument | What it does |
| :------- | :----------- |
| *(none)* | Prune **dangling** (untagged) images only |
| `img` | Prune **all unused** images (more aggressive, confirmation required) |
| `net` | Prune dangling/unused networks (confirmation required) |
| `vol` | Prune unused volumes (**data loss risk** - confirmation required) |
| `buildx` | Prune build cache |
| `all` | Everything above |

Multiple arguments can be combined: `cleanup vol net`, `cleanup img vol buildx`.

> ⚠️ **Important:** The standalone `cleanup` command is always **global** - it operates on your entire Docker host. This is entirely different from `delete <app> with vol`, which only removes volumes for that specific app's Compose project. See [docs/safety.md](docs/safety.md) for details.

### Status, List & Get

| Command | Description |
| :------ | :---------- |
| `status <selection>` | Container table + real-time resource usage (`docker ps` + `docker stats`) |
| `list` | Inventory of all discovered apps with status |
| `list <selection>` | Detailed info for specific apps |
| `get <app> <resource>` | Raw container data for scripting (`cid`, `iid`, `vol`, `mnt`, `net`, `port`, `state`, `health`, `info`) |

The `get` command supports service targeting: `get <app>:<service> <resource>`.

### Logs

```bash
logs <selection> [keywords...]
```

Human-friendly keyword syntax:

| Keyword | Effect |
| :------ | :----- |
| `last <N>` | Show the last N lines |
| `first <N>` | Show the first N lines |
| `since <time>` | Show logs since a timestamp/duration (e.g. `since 30m`) |
| `until <time>` | Show logs until a timestamp |
| `live` / `follow` | Stream logs in real-time |
| `time` / `timestamps` | Prefix every line with a timestamp |

Keywords can be chained: `logs <app-name> live last 10 time`

> **Note:** `live` cannot be used with `all` apps (safety restriction).

### System Commands

These require root (`sudo`):

| Command | Description |
| :------ | :---------- |
| `sudo ./dam.sh install` | Interactive system-wide install |
| `sudo ./dam.sh install refresh` | Refresh command symlinks non-interactively |
| `sudo <cmd> config` | Re-run the setup wizard (change search dirs / command name) |
| `sudo <cmd> self-update` | Download the latest `dam.sh` from the configured `UPDATE_URL` and reinstall |
| `sudo <cmd> uninstall` | Remove the script, symlinks, and config |

`<cmd>` is whatever you chose during install (`dkr`, `dam`, raw names, etc.).

---

## Configuration

### Search Directories

DAM looks for app folders under the directories listed in `SEARCH_DIRS`. **Defaults** (used when no config file exists and the directories are present): `/opt/stacks`, `/opt/projects`, `$HOME/apps`, `$HOME/stacks`. Change these during `install` or later with `config`.

### Exclude Folders

Folder **names** (not full paths) listed in `EXCLUDE_DIRS` are pruned during discovery. Default excludes: `recovered`, `recovered-configs`, `unused`.

### Custom Command Name

| Choice | Result |
| :----- | :----- |
| `dkr` (default) | Commands become `dkr start …`, `dkr update …`, etc. |
| Any other name | e.g. `dam start …` |
| `none` (Raw mode) | Raw multicall commands: `start`, `stop`, `update`, … are installed directly |

Raw mode is convenient but can conflict with other tools. The installer checks for conflicts.

### Config File

Installed configuration lives at `/etc/docker-app-manager.conf` - a Bash-sourceable file that sets `SEARCH_DIRS`, `EXCLUDE_DIRS`, `CUSTOM_CMD_NAME`, and other options.

### Environment / Script Options

| Variable | Type | Purpose | Default |
| :------- | :--- | :------ | :------ |
| `UPDATE_URL` | String (URL) | Raw URL used by `self-update`. **Do not change** unless using a custom mirror. | Hard-coded in script |
| `UPDATE_SHA256` | String (Hash) | Optional 64-character SHA-256 integrity check. *Only for strict security environments where every update is manually approved.* | *(empty)* |
| `ALLOW_CUSTOM_UPDATE_SCRIPTS` | Boolean | Whether `update*.sh` scripts are permitted (`true` or `false`) | `false` |
| `CUSTOM_CMD_NAME` | String | Prefix / multicall name | `"dkr"` |

> 📖 **Full reference:** [docs/configuration.md](docs/configuration.md)

---

## How It Works

### App Discovery

1. Walk each directory in `SEARCH_DIRS` (depth 1–5 levels).
2. Prune any directory whose basename is in `EXCLUDE_DIRS`.
3. Treat a directory as an "app" if it contains at least one of:
   - `compose.yaml` / `compose.yml` / `docker-compose.yaml` / `docker-compose.yml`
   - or (for update mode) an `update*.sh` script

🚨 **App name** = basename of the directory. If multiple directories share the same name, DAM reports an error and refuses to guess.

*(Note: If you explicitly override the project name via `COMPOSE_PROJECT_NAME` in a `.env` file or `name:` in your compose file, DAM seamlessly supports it. The folder name is the primary app name; a custom project name is also accepted as an alias when it does not collide with another folder name. `list` shows the folder name in APP and the custom name in PROJECT; `status`, `get` and the container state use the effective project name to find containers.)*

> 📖 **Full details:** [docs/application-discovery.md](docs/application-discovery.md)

### Compose Detection

For compose actions DAM prefers the first file it finds in this order:

1. `compose.yaml`
2. `compose.yml`
3. `docker-compose.yaml`
4. `docker-compose.yml`

It then runs `docker compose` or falls back to `docker-compose`.

### Custom Update Scripts

If an app directory contains a file matching `update*.sh` and custom scripts are allowed, `update` will execute the first script alphabetically instead of the default pull + build + recreate flow. This lets you keep complex migration or multi-step update logic next to the compose file.

> 📖 **Full details:** [docs/updates.md](docs/updates.md)

### Safety Guards

- Destructive bulk actions (`delete all`, volume prune, aggressive image prune) require explicit confirmation unless `-y` / `--yes` is passed.
- Non-interactive terminals (no TTY) refuse destructive prompts and ask you to use `-y`.
- Volumes are **preserved by default** on `delete`. You must explicitly request `with vol`.
- `cleanup vol`/`cleanup all` operates **globally** on the Docker host - separate from app-level cleanup.
- App names containing spaces are rejected.

> 📖 **Full details:** [docs/safety.md](docs/safety.md)

---

## Advanced Topics

### Self-Update

```bash
sudo <cmd> self-update  # e.g., 'sudo dkr self-update'. If using raw mode, use 'docker-app-manager self-update'
```

Fetches the script from `UPDATE_URL`, validates it (shebang check, syntax check, optional SHA-256 verification), and reinstalls it.

### Reconfigure

```bash
sudo <cmd> config  # e.g., 'sudo dkr config'. If using raw mode, use 'docker-app-manager config'
```

Re-runs the interactive wizard so you can change search directories, excludes, or the command name without a full reinstall.

### Uninstall

```bash
sudo <cmd> uninstall  # e.g., 'sudo dkr uninstall'. If using raw mode, use 'docker-app-manager uninstall'
```

Removes the installed script (`/usr/local/bin/docker-app-manager`), all command symlinks, and the config file (`/etc/docker-app-manager.conf`).

### Running Without Installation

```bash
./dam.sh <action> <selection>
```
Not recommended for production or daily use. It's more useful for testing or portable usage. You must be in the same directory as the `dam.sh` script to run the commands.

Uses the built-in default search paths, so you must specify your stacks path directly in the `dam.sh` file.

### Non-Interactive / Automation

- Always pass `-y` / `--yes` for any command that might prompt.
- Prefer explicit app lists over `all` when scripting.
- Ensure the user that runs the script can talk to the Docker daemon (group `docker` or root).
- Use `get` for extracting raw data for pipelines.

```bash
#!/usr/bin/env bash
set -euo pipefail
dkr update all except <app3>
dkr cleanup -y
```

### Limitations

- **One compose project per folder.** Does not manage multi-file compose selections, profiles, or Swarm/Kubernetes.
- **No spaces** in app names or paths.
- Discovery depth is capped at 5 levels under each search root.
- Designed primarily for Linux self-hosted environments.
- Custom update scripts: only the first alphabetically is executed.
- `debug` command is a placeholder (not yet implemented).

> 📖 **Full details:** [docs/limitations.md](docs/limitations.md)

---

## Troubleshooting

| Symptom | Things to check |
| :------ | :-------------- |
| `bash 4.4+ required` | Upgrade Bash or run under a newer shell |
| `docker` command not found / daemon not running | Install Docker, start the service, check permissions (`docker` group) |
| Neither `docker compose` nor `docker-compose` available | Install the Compose plugin or the standalone binary |
| App not found | Confirm the folder name, that a compose file exists, and that the parent is in `SEARCH_DIRS`. Run `list` to see discovered apps. |
| Multiple matches for the same name | Rename one of the folders or narrow `SEARCH_DIRS` |
| Permission denied on install/config | Use `sudo` |
| Volume/network prune refused in scripts | Pass `-y` and ensure you really want the data removed |
| `start` recreated my containers | DAM uses `docker compose up -d`, which applies config changes. See [DAM vs Docker](docs/docker-vs-dam.md). |

> 📖 **Full troubleshooting guide:** [docs/troubleshooting.md](docs/troubleshooting.md)

---

## Contributing

Contributions, bug reports, and ideas are welcome.

1. Fork the repository
2. Create a feature branch
3. Make your changes (keep the script self-contained and well-commented)
4. Run `bash -n dam.sh` and `shellcheck dam.sh` before submitting
5. Test against real compose stacks if possible
6. Open a pull request with a clear description

Please keep the spirit of the tool: simple, safe defaults, and friendly to people who live in the terminal.

See [CONTRIBUTING.md](CONTRIBUTING.md) for full guidelines.

---

## License

This project is licensed under the **MIT License**.
See the [LICENSE](LICENSE) file in the repository for the full text.

---

## Credits

- Author: [Ruthvik Upputuri](https://github.com/RuthvikUpputuri)
- Repository: [https://gh.upputuri.in/dam](https://gh.upputuri.in/dam)

Inspired by the daily friction of managing 100's of my Docker Compose stacks.

---

<p align="center">
  <sub>Happy stacking.</sub>
</p>
