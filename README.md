<p align="center">
  <strong>DAM</strong> - Docker App Manager
</p>

<p align="center">
  <em>A robust CLI for bulk-managing, updating, and safely cleaning multiple Docker Compose applications from anywhere.</em>
</p>

<p align="center">
  Built for hobbyists, self-hosters, and people who love CLI but hate <code>cd</code>-ing into every stack folder to manage docker apps.
</p>

<p align="center">
  <a href="#getting-started">Getting Started</a> ·
  <a href="#usage">Usage</a> ·
  <a href="#commands-reference">Commands</a> ·
  <a href="#configuration">Configuration</a> ·
  <a href="#how-it-works">How It Works</a> ·
  <a href="#advanced">Advanced</a> ·
  <a href="#license">License</a>
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
  - [Status](#status)
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
cd ~/stacks/homarr && docker compose up -d
cd ~/stacks/n8n && docker compose pull && docker compose up -d
cd ~/stacks/traefik && docker compose restart
# …and so on for every app
```

you can do:

```bash
start all except traefik
update n8n langflow
restart homarr
cleanup vol
```

from **any directory**.

DAM discovers your app folders, finds the correct `compose.yaml` / `docker-compose.yml`, runs the right `docker compose` (or `docker-compose`) commands, supports bulk operations with exclusions, optional extended cleanup, and a safe install that gives you short global commands.

**NOTE:** DAM is not a replacement for Docker CLI. It is a global CLI for managing Docker Compose applications by application/directory name instead of requiring the user to know the project directory, Compose file, service names, container names or IDs.

---

## Why DAM?

| Problem | DAM solution |
| :------ | :----------- |
| Constantly `cd` into stack directories | Run commands from anywhere |
| Updating 10+ apps one by one | `update all` or `update all except traefik` |
| Forgetting which apps exist | Built-in listing + status |
| Accidental volume/network deletes | Explicit confirmations + opt-in cleanup modes |
| Different compose file names | Auto-detects `compose.yaml`, `compose.yml`, `docker-compose.yaml`, `docker-compose.yml` |
| Custom update logic per app | Supports `update*.sh` scripts in the app folder |
| Want short commands | Install once → use `start`, `stop`, `update`, … (or with a custom prefix like `dkr`) |

It is intentionally focused on **one compose project per folder** which is the pattern used by most self-hosters and hobby setups.

---

## Features

- **Bulk lifecycle control** - start, stop, restart, recreate, force-recreate, pause, unpause, delete
- **Smart app selection**
  - `all`
  - `all except app1 app2`
  - one or more specific apps
- **Update flow** - pull images + recreate, or run a custom `update*.sh` if present
- **Safe cleanup** - dangling images by default; opt-in for networks, volumes, build cache, or everything
- **Global install** - system-wide commands + config under `/etc`
- **Configurable search paths** - default locations or your own directories
- **Exclude folders** - ignore directories named e.g. `recovered`, `unused`
- **Colored, structured output** - clear per-app sections and a final summary
- **Confirmation prompts** on destructive bulk actions (bypass with `-y` / `--yes`)
- **Self-update** - pull the latest script from the repository
- **Works with both** `docker compose` (v2 plugin) and legacy `docker-compose`

---

## Getting Started

### Prerequisites

| Requirement | Notes |
| :---------- | :---- |
| **Bash 4.4+** | Required (empty-array expansion under `set -u`) |
| **Docker** | Daemon must be running and accessible by your user |
| **Docker Compose** | Either the v2 plugin (`docker compose`) or standalone `docker-compose` |
| **Linux** (primary) | Tested on common Linux distributions; other Unix-like systems may work |

Check versions:

```bash
bash --version
docker --version
docker compose version   # or: docker-compose --version
```

### Quick Install

1. Run the one-line installation script. This will automatically download the latest version, make it executable, and trigger the interactive setup:
```bash
sudo curl -fsSL https://raw.githubusercontent.com/RuthvikUpputuri/dam/main/dam.sh -o /tmp/dam.sh && sudo chmod +x /tmp/dam.sh && sudo /tmp/dam.sh install && rm /tmp/dam.sh
```

The installer will:

- Ask which directories contain your Docker Compose apps (defaults suggested)
- Let you set folder names to always exclude
- Let you choose a global command name (default: `dkr`, or `none` for raw commands like `start` / `stop`)
- Install the script and create the necessary command links
- Write configuration to `/etc/docker-app-manager.conf`

After installation you can use the commands from anywhere.

### Manual / One-off Use

You can run the script without installing:

```bash
./dam.sh start homarr
./dam.sh update all except traefik
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
dkr status all

# If you chose "none" (raw commands):
start --help          # or just: start
status all
```

You should see a usage summary and a list of discovered apps.

---

## Usage

### App Selection Syntax

The same selection syntax works for almost every action:

| Pattern | Meaning |
| :------ | :------ |
| `<action> all` | Every discovered app |
| `<action> all except app1 app2` | Every app except the listed ones |
| `<action> app1` | Single app |
| `<action> app1 app2 app3` | Multiple specific apps |

Optional modifiers:

- Append `with vol`, `with net`, `with buildx`, `with img`, or `with all` on **delete** / **update** to trigger extended cleanup.
- Use `-y` or `--yes` to skip confirmation prompts (especially important for `delete all` and volume/image prunes).

**Note:** App names and paths must **not** contain spaces.

### Everyday Examples

```bash
# Start everything except the reverse proxy
start all except traefik

# Restart a couple of apps
restart homarr n8n

# Pull latest images and recreate
update n8n langflow traefik

# Full recreate of one stack
recreate affine

# Force recreate (immediate kill + --force-recreate)
force-recreate portainer
# or the short alias:
frec portainer

# Remove an app stack (containers + networks); volumes kept by default
delete affine

# Remove an app and also prune its volumes
delete affine with vol

# View logs for an app (last 100 lines)
dkr logs n8n last 100

# Stream logs live with timestamps
dkr logs n8n live time

# View the first 50 lines of logs
dkr logs n8n first 50

# Clean only dangling images
cleanup

# Clean dangling images + unused volumes (asks for confirmation)
cleanup vol

# Aggressive cleanup (images, networks, volumes, build cache)
cleanup all -y

# See what is running
status all
status n8n traefik
```

---

## Commands Reference

### Lifecycle Actions

| Command | Description |
| :------ | :---------- |
| `start` | `docker compose up -d` (create if needed) |
| `stop` | `docker compose stop` |
| `restart` | `docker compose restart` |
| `recreate` | `down --remove-orphans` then `up -d` |
| `force-recreate` / `frec` | `down -t 0 --remove-orphans` then `up -d --force-recreate` |
| `pause` | `docker compose pause` |
| `unpause` | `docker compose unpause` |
| `delete` | Remove the stack (`down --remove-orphans`). Optionally remove volumes/images with `with [vol \| img \| all]`. Then runs dangling cleanup. |

### Update

```bash
update <selection> [with vol|net|buildx|img|all] [-y]
```

Behavior per app:

1. If an `update*.sh` script exists in the app directory **and** custom update scripts are allowed → run that script. If more than one update script exists, DAM will run those update scripts in alphabetical order.
2. Otherwise:
   - `docker compose pull`
   - rebuild if needed
   - recreate containers (`up -d`)

You can append cleanup modifiers the same way as with `delete`.

### Cleanup

```bash
cleanup [net|buildx|vol|img|all] [-y]
```

| Argument | What it does |
| :------- | :----------- |
| *(none)* | Prune **dangling** (untagged) images only |
| `img` | Prune **all unused** images (more aggressive) |
| `net` | Prune dangling/unused networks |
| `vol` | Prune unused volumes (**data loss risk** - confirmation required) |
| `buildx` | Prune build cache |
| `all` | Everything above |

**Combining Arguments:**
You can pass multiple cleanup arguments at once! For example:
- `dkr cleanup vol net`
- `dkr cleanup img vol buildx`
*(Note: If you use `all`, you only need that 1 argument, there is no need to type the rest).*

> **IMPORTANT:** The standalone `cleanup` command is always **Global**. It scans your entire server and blindly deletes unused resources. This is entirely different from chaining cleanups (like `dkr delete myapp with vol net`), which are strictly **App-Specific** and only safely delete resources tied to that specific app.

Confirmations are required for volume and full-image prunes unless you pass `-y` / `--yes`.

### Status

```bash
status <selection>
```

Shows `docker compose ps` for the selected apps.

### Logs

```bash
logs <selection> [args...]
```

View the logs for your apps. You can use native "spoken English" keywords to format the log output!

**Supported Keywords (can be chained in any order):**
- `last <N>`: Show the last N lines (e.g. `last 100`)
- `first <N>`: Show the first N lines (e.g. `first 50`)
- `since <time>`: Show logs since a timestamp or relative time (e.g. `since 30m`)
- `until <time>`: Show logs until a timestamp (e.g. `until 1h`)
- `live` (or `follow`): Stream the logs live (scrolls down)
- `time` (or `timestamps`): Prefix every log line with a timestamp

**Examples:**
```bash
dkr logs n8n last 50
dkr logs traefik live time
dkr logs all last 20
dkr logs n8n live last 10
```
*(Note: As a safety feature, you cannot use the `live` argument if your app selection is `all`)*

### System Commands

These require root (or the way you installed):

| Command | Description |
| :------ | :---------- |
| `sudo ./dam.sh install` | Interactive system-wide install |
| `sudo ./dam.sh install --refresh` | Refresh command symlinks non-interactively |
| `sudo <cmd> config` | Re-run the setup wizard (change search dirs / command name) |
| `sudo <cmd> self-update` | Download the latest `dam.sh` from the configured `UPDATE_URL` and reinstall |
| `sudo <cmd> uninstall` | Remove the script, symlinks, and config |

`<cmd>` is whatever you chose during install (`dkr`, `dam`, raw names, etc.).

---

## Configuration

### Search Directories

DAM looks for app folders under the directories listed in `SEARCH_DIRS`.

**Defaults** (used when no config file exists and the directories are present):

- `/opt/stacks`
- `/opt/projects`
- `$HOME/apps` (or the real home of the user who ran `sudo`)
- `$HOME/stacks`

You can change these during `install` or later with `config`.

### Exclude Folders

Folder **names** (not full paths) listed in `EXCLUDE_DIRS` are ignored during discovery.

Default excludes often include names such as:

- `recovered`
- `recovered-configs`
- `unused`

### Custom Command Name

During install you choose how you want to invoke DAM:

| Choice | Result |
| :----- | :----- |
| `dkr` (default) | Commands become `dkr start …`, `dkr update …`, etc. |
| Any other name | e.g. `dam start …` |
| `none` | Raw multicall commands: `start`, `stop`, `update`, … are installed directly |

Raw mode is convenient but can conflict with other tools that use the same names. The installer checks for conflicts.

### Config File

Installed configuration lives at:

```text
/etc/docker-app-manager.conf
```

It is a simple Bash-sourceable file that can set:

- `SEARCH_DIRS=(...)`
- `EXCLUDE_DIRS=(...)`
- `CUSTOM_CMD_NAME=...`
- and other options the script understands

### Environment / Script Options

Relevant variables (also documentable in the config file):

| Variable | Purpose |
| :------- | :------ |
| `UPDATE_URL` | Raw URL used by `self-update` (default points at this repository) |
| `UPDATE_SHA256` | Optional integrity check for self-update |
| `ALLOW_CUSTOM_UPDATE_SCRIPTS` | Whether `update*.sh` scripts are permitted |
| `CUSTOM_CMD_NAME` | Prefix / multicall name |

---

## How It Works

### App Discovery

1. Walk each directory in `SEARCH_DIRS` (depth limited, typically up to 5 levels).
2. Prune any directory whose basename is in `EXCLUDE_DIRS`.
3. Treat a directory as an “app” if it contains at least one of:
   - `compose.yaml` / `compose.yml`
   - `docker-compose.yaml` / `docker-compose.yml`
   - or (for update mode) an `update*.sh` script

App **name** = basename of the directory.

If multiple directories share the same name, DAM reports an error and refuses to guess.

### Compose Detection

For compose actions DAM prefers the first file it finds in this order:

1. `compose.yaml`
2. `compose.yml`
3. `docker-compose.yaml`
4. `docker-compose.yml`

It then runs `docker compose` or falls back to `docker-compose`.

### Custom Update Scripts

If an app directory contains a file matching `update*.sh` and custom scripts are allowed, `update` will execute that script instead of the default pull + recreate flow. This lets you keep complex migration or multi-step update logic next to the compose file.

### Safety Guards

- Destructive bulk actions (`delete all`, volume prune, aggressive image prune) require explicit confirmation unless `-y` / `--yes` is passed.
- Non-interactive terminals (no TTY) refuse destructive prompts and ask you to use `-y`.
- Volumes are **preserved by default** on `delete`. You must explicitly request `with vol` (or `cleanup vol` / `cleanup all`).
- App names containing spaces are rejected.

---

## Advanced Topics

### Self-Update

```bash
sudo dkr self-update          # or whatever your command name is
# or, if using the script directly:
sudo ./dam.sh self-update
```

Fetches the script from `UPDATE_URL` (default: the raw GitHub URL of this repository) and reinstalls it.

### Reconfigure

```bash
sudo dkr config
```

Re-runs the interactive wizard so you can change search directories, excludes, or the command name without a full reinstall.

### Uninstall

```bash
sudo dkr uninstall
```

Removes the installed script, command links, and the config file under `/etc`.

### Running Without Installation

```bash
./dam.sh <action> <selection>
```

Uses the built-in default search paths. Useful for testing or portable USB/toolbag usage.

### Non-Interactive / Automation

- Always pass `-y` / `--yes` for any command that might prompt.
- Prefer explicit app lists over `all` when scripting.
- Ensure the user that runs the script can talk to the Docker daemon (group `docker` or root).

Example:

```bash
#!/usr/bin/env bash
set -euo pipefail
update all except traefik -y
cleanup -y
```

### Limitations

- **One compose project per folder.** Does not manage multi-file compose selections or Swarm/Kubernetes.
- **No spaces** in app names or paths.
- Discovery depth is capped (currently looking up to depth 5 under each search root).
- Designed primarily for Linux self-hosted environments.

---

## Troubleshooting

| Symptom | Things to check |
| :------ | :-------------- |
| `bash 4.4+ required` | Upgrade Bash or run under a newer shell |
| `docker` command not found / daemon not running | Install Docker, start the service, check permissions (`docker` group) |
| Neither `docker compose` nor `docker-compose` available | Install the Compose plugin or the standalone binary |
| App not found | Confirm the folder name, that a compose file exists, and that the parent is in `SEARCH_DIRS`. Run `status` / usage to list discovered apps. |
| Multiple matches for the same name | Rename one of the folders or narrow `SEARCH_DIRS` |
| Permission denied on install/config | Use `sudo` |
| Volume/network prune refused in scripts | Pass `-y` and ensure you really want the data removed |

---

## Contributing

Contributions, bug reports, and ideas are welcome.

1. Fork the repository
2. Create a feature branch
3. Make your changes (keep the script self-contained and well-commented)
4. Test against real compose stacks if possible
5. Open a pull request with a clear description

Please keep the spirit of the tool: simple, safe defaults, and friendly to people who live in the terminal.

---

## License

This project is licensed under the **MIT License**.
See the [LICENSE](LICENSE) file in the repository for the full text.

---

## Credits

- Author: [Ruthvik Upputuri](https://github.com/RuthvikUpputuri)
- Repository: [https://gh.upputuri.in/dam](https://gh.upputuri.in/dam)

Inspired by the daily friction of managing 100's of Docker Compose stacks.

---

<p align="center">
  <sub>Happy stacking.</sub>
</p>

