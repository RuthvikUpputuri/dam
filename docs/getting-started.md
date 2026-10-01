# Getting Started

## Prerequisites

| Requirement | Minimum Version | Why |
| :---------- | :-------------- | :-- |
| **Bash** | 4.4+ | Required for empty-array expansion under `set -u` |
| **Docker Engine** | Any modern version | Daemon must be running and accessible by your user |
| **Docker Compose** | v2 plugin (`docker compose`) or standalone (`docker-compose`) | DAM auto-detects which is available |
| **Linux** | Primary target | Tested on common distributions; other Unix-like systems may work |
| **curl** | Any | Required only for `self-update` |

DAM explicitly checks these at startup:

1. **Bash version**: exits immediately with `"bash 4.4+ required"` if the version check fails.
2. **Docker binary**: checks `command -v docker` - exits with `"'docker' command not found"`.
3. **Docker daemon**: checks `docker info` - exits with `"Docker daemon is not running or you lack permission"`.
4. **Docker Compose**: checks both `docker compose version` and `docker-compose version` - exits if neither is available.

### Verify Your Environment

```bash
bash --version          # Must be 4.4+
docker --version        # Docker must be installed
docker info             # Daemon must be running
docker compose version  # v2 plugin (preferred)
# or: docker-compose --version  # v1 standalone (fallback)
```

---

## Installation Methods

### Method 1: One-Line Quick Install

Download and run the interactive installer:

```bash
sudo curl -fsSL https://gh.upputuri.in/dam.sh -o /tmp/dam.sh && sudo chmod +x /tmp/dam.sh && sudo /tmp/dam.sh install && rm /tmp/dam.sh
```

The installer will:

1. **Ask for search directories** - where your Docker Compose app folders live (defaults: `/opt/stacks`, `/opt/projects`, `~/apps`, `~/stacks`)
2. **Ask for excluded folder names** - directory names to always ignore (defaults: `recovered`, `recovered-configs`, `unused`)
3. **Ask for a command name** - how you'll invoke DAM globally:
   - Enter a name like `dkr` (default) or `dam` → commands become `dkr start …`, `dam update …`, etc.
   - Enter `none` → installs raw commands: `start`, `stop`, `update`, … directly (the installer checks for system conflicts first)
4. **Ask about custom update scripts** - whether `update*.sh` scripts should be allowed to run automatically without prompting. If "No", DAM will interactively ask you for permission each time it finds one.
5. **Optionally set** a self-update SHA-256 hash. *Note: It is only there for highly strict security environments where administrators want to manually approve and verify every single update before allowing the script to pull it. For normal use, leaving it blank is the best approach.*

After completion:

- The script is **symlinked** to `/usr/local/bin/docker-app-manager`
- Command symlinks are created based on your choice
- Configuration is saved to `/etc/docker-app-manager.conf`

### Method 2: Clone and Install

```bash
git clone https://gh.upputuri.in/dam.git
cd dam
sudo ./dam.sh install
```

This is identical to Method 1 but starts from a local clone. The installer symlinks the cloned script to `/usr/local/bin/docker-app-manager`, so edits to the cloned file are reflected globally.

### Method 3: Run Without Installing

```bash
chmod +x dam.sh
./dam.sh start <app-name>
./dam.sh update all except traefik
./dam.sh cleanup
```

When not installed (no `/etc/docker-app-manager.conf` exists), DAM uses these **fallback defaults**:

- **Search directories**: `/opt/stacks`, `/opt/projects`, `~/apps`, `~/stacks` (only directories that actually exist)
- **Excluded directories**: `recovered`, `recovered-configs`, `unused`
- **Search depth**: `5` (controlled by `MAX_SEARCH_DEPTH` in config)

---

## Verify Installation

```bash
# If you chose a custom command name (e.g. dkr):
dkr --help
dkr list

# If you chose "none" (raw commands):
start --help
list
```

You should see the DAM usage summary and a list of discovered applications.

---

## Directory Layout Requirements

DAM expects one Docker Compose project per directory. Each directory must contain at least one of:

- `compose.yaml`
- `compose.yml`
- `docker-compose.yaml`
- `docker-compose.yml`

Or, for update operations, an `update*.sh` script.

**Example layout:**

```
/opt/stacks/
├── traefik/
│   └── compose.yaml
├── n8n/
│   └── docker-compose.yml
├── file-share/         # Actual app name is erugo but renamed the dir to file-share for easy remembering
│   └── docker-compose.yml
├── homarr/
│   ├── compose.yaml
│   └── update-homarr.sh
└── recovered/          ← ignored by default (in EXCLUDE_DIRS)
    └── old-app/
```

The **directory basename** becomes the app name used in DAM commands. In this example: `traefik`, `n8n`, `homarr`, `file-share`.

---

## What Gets Installed

| File/Path | Purpose |
| :-------- | :------ |
| `/usr/local/bin/docker-app-manager` | Symlink to your `dam.sh` script |
| `/usr/local/bin/<cmd>` | Symlink(s) to `docker-app-manager` (your chosen command name or raw action names) |
| `/etc/docker-app-manager.conf` | Bash-sourceable configuration file |

---

## Next Steps

- **[Usage Guide](commands.md)** - learn all available commands
- **[Configuration](configuration.md)** - customize search paths, excludes, and behavior
- **[Application Discovery](application-discovery.md)** - how DAM finds your apps


# Configuration Reference

This document covers every configuration variable, option, and setting in DAM.

---

## Configuration File

### Location

```
/etc/docker-app-manager.conf
```

This file is created by the `install` or `config` commands. It is a **Bash-sourceable** file - the script loads it directly via `source "$CONFIG_FILE"`.

### Format

```bash
# Auto-generated by Docker Apps Lifecycle Manager
SEARCH_DIRS=("/opt/stacks" "/home/user/apps")
EXCLUDE_DIRS=("recovered" "recovered-configs" "unused")
CUSTOM_CMD_NAME="dkr"
ALLOW_CUSTOM_UPDATE_SCRIPTS="false"
UPDATE_SHA256="abc123..."
UPDATE_URL="https://gh.upputuri.in/dam.sh"
MAX_SEARCH_DEPTH="5"
```

### Precedence

1. If `/etc/docker-app-manager.conf` exists → its values are used
2. If the config file does not exist → fallback defaults are used (see each variable below)
3. After loading (or falling back), `declare -p` checks ensure `SEARCH_DIRS` and `EXCLUDE_DIRS` are set to empty arrays if they were not defined

---

## Configuration Variables

### `SEARCH_DIRS`

| Property | Value |
| :------- | :---- |
| **Purpose** | Directories to search for Docker Compose app folders |
| **Type** | Bash array of absolute paths |
| **Default** | `/opt/stacks`, `/opt/projects`, `$HOME/apps`, `$HOME/stacks` - but **only** directories that actually exist are included |
| **Set by** | `install` / `config` interactive wizard |
| **Can be overridden** | Yes, by editing the config file directly |
| **Behavior when empty** | No apps are discovered; all commands that require app selection will fail |
| **Behavior with invalid paths** | Non-existent directories are silently skipped during search (only valid directories are used) |

**Example:**
```bash
SEARCH_DIRS=("/opt/stacks" "/opt/projects" "/home/ruth/apps")
```

**Notes:**
- Paths must not contain spaces (the installer validates this during setup)
- During `sudo` execution without a config file, DAM resolves the real user's home via `getent passwd "$SUDO_USER"` instead of using root's `$HOME`
- The search uses `find -mindepth 1 -maxdepth "${MAX_SEARCH_DEPTH}"` - apps up to 5 levels deep (by default) are discovered. This depth is configurable via `MAX_SEARCH_DEPTH`.

---

### `EXCLUDE_DIRS`

| Property | Value |
| :------- | :---- |
| **Purpose** | Directory **names** (not full paths) to exclude from app discovery |
| **Type** | Bash array of directory basenames |
| **Default** | `("recovered" "recovered-configs" "unused")` (when no config file exists) |
| **Set by** | `install` / `config` interactive wizard |
| **Can be overridden** | Yes, by editing the config file directly |
| **Behavior when empty** | No directories are excluded |
| **Clearing** | During setup, enter `none` to clear all exclusions |

**Example:**
```bash
EXCLUDE_DIRS=("recovered" "recovered-configs" "unused" "templates" "archive")
```

**Notes:**
- Exclusion is by **basename only** - a directory named `recovered` at any depth under any search root will be excluded
- Excluded apps appear in `list` output with an "excluded" status marker
- Excluded apps are skipped during `all` operations with a `[SKIP]` message
- The `find` command uses `-name "$excl" -prune` which prevents descending into excluded directories at all

---

### `CUSTOM_CMD_NAME`

| Property | Value |
| :------- | :---- |
| **Purpose** | The command name used to invoke DAM globally |
| **Type** | String |
| **Default** | `"dkr"` (offered during install; defaults to empty string - `""` - if `none` is chosen, which enables raw multicall mode) |
| **Set by** | `install` / `config` interactive wizard |
| **Can be overridden** | Yes, by editing the config file and running `install refresh` |

**Modes:**

| Value | Resulting Commands | Symlinks Created |
| :---- | :----------------- | :--------------- |
| `"dkr"` (or any name) | `dkr start ...`, `dkr update ...` | `/usr/local/bin/dkr` → `/usr/local/bin/docker-app-manager` |
| `""` (empty / `none`) | `start ...`, `stop ...`, `update ...` | One symlink per action in `/usr/local/bin/` |

**Conflict detection:**
- During install, if raw mode is selected, the installer checks every supported action name against `command -v` to detect conflicts with existing system commands
- If a conflict is found, the user is forced to choose a custom name
- If no conflicts are found, a warning is displayed and confirmation is required

**Internal behavior:**
- The `CUSTOM_CMD_NAME` value also sets the `CMD_PREFIX` variable, which affects usage/help output formatting

---

### `ALLOW_CUSTOM_UPDATE_SCRIPTS`

| Property | Value |
| :------- | :---- |
| **Purpose** | Whether `update*.sh` scripts run automatically during `update` |
| **Type** | String (`"true"` or `"false"`) |
| **Default** | `"false"` |
| **Set by** | `install` / `config` interactive wizard |
| **Accepted values** | `true`, `TRUE`, `yes`, `YES`, `y`, `Y` → treated as `true`; anything else → `false` |

**Behavior by value:**

| Value | What Happens When `update*.sh` Exists |
| :---- | :------------------------------------ |
| `true` | Custom script runs immediately without prompting |
| `false` (default) | DAM prompts the user: "Do you want to run this custom update script? [y/N]" |
| `false` + non-interactive | Warning logged, custom script skipped, falls back to compose update |

---

### `UPDATE_URL`

| Property | Value |
| :------- | :---- |
| **Purpose** | URL used by `self-update` to download the latest version |
| **Type** | String (HTTPS URL) |
| **Default** | `"https://gh.upputuri.in/dam.sh"` (hard-coded in the script header) |
| **Set by** | Hard-coded in the script (can be manually added to config) |
| **Validation** | Must start with `https://` (checked during self-update) |

**Notes:**
- The official default URL is hard-coded in the script.
- The `install` / `config` wizards do not prompt for this, to ensure the official URL is used.
- If you must use a custom URL, you can manually add `UPDATE_URL="..."` to the config file to override the hard-coded value.
- If empty during `self-update`, an error is displayed

---

### `UPDATE_SHA256`

| Property | Value |
| :------- | :---- |
| **Purpose** | Optional SHA-256 checksum for verifying self-update downloads. *Note: It is only there for highly strict security environments where administrators want to manually approve and verify every single update before allowing the script to pull it. For normal use, leaving it blank is the best approach.* |
| **Type** | String (64-character hex hash) |
| **Default** | Empty (no verification) |
| **Set by** | `install` / `config` wizard (optional) |
| **Behavior when set** | After downloading the updated script, its `sha256sum` is compared against this value. If they don't match, the update is aborted. |
| **Behavior when empty** | No checksum verification is performed |

---

### `MAX_SEARCH_DEPTH`

| Property | Value |
| :------- | :---- |
| **Purpose** | Maximum directory depth when searching for apps in `SEARCH_DIRS` |
| **Type** | Integer |
| **Default** | `5` |
| **Set by** | Manually added to config (not prompted during installation) |
| **Validation** | Must be a positive integer |

**Notes:**
- By default, DAM searches up to 5 directories deep from your defined `SEARCH_DIRS`.
- If you have deeply nested apps, you can increase this limit by manually adding `MAX_SEARCH_DEPTH="10"` to your configuration file.
- Decreasing it can speed up discovery if you have a massive directory tree.

---

## Derived / Internal Variables

These variables are not directly user-configurable but are derived from the configuration:

| Variable | Derived From | Purpose |
| :------- | :----------- | :------ |
| `CMD_PREFIX` | `CUSTOM_CMD_NAME` | The command name prefix (empty string if raw mode) |
| `P_CMD` | `CMD_PREFIX` | Formatted prefix for help output (e.g., `"dkr "` with trailing space) |
| `CONFIG_FILE` | Hard-coded | Always `/etc/docker-app-manager.conf` |
| `FIND_PRUNE_ARGS` | `EXCLUDE_DIRS` | `find` arguments for pruning excluded directories |
| `ASSUME_YES` | `-y` / `--yes` CLI flag | Skips confirmation prompts when `true` |
| `CLEANUP_MODES` | `with` keyword in CLI | Array of cleanup targets (vol, net, buildx, img, all) |
| `LOG_ARGS_RAW` | CLI arguments to `logs` | Array of log keyword arguments |
| `GET_RESOURCE_RAW` | CLI argument to `get` | The resource type to retrieve |
| `APP_DIR_CACHE` | Runtime cache | Associative array caching app directory lookups |

---

## Editing Configuration Manually

You can edit `/etc/docker-app-manager.conf` directly. After editing:

```bash
sudo <cmd> install refresh
```

This re-reads the config and refreshes all symlinks without running the interactive wizard.

**Caution:** Since the config file is sourced as Bash, syntax errors will cause the script to fail. Use proper Bash array syntax:

```bash
# Correct:
SEARCH_DIRS=("/opt/stacks" "/home/user/apps")

# Incorrect (will break):
SEARCH_DIRS="/opt/stacks, /home/user/apps"
```

---

## Environment Variables

DAM does not read environment variables for configuration (other than standard ones like `HOME`, `SUDO_USER`, `EUID`). All configuration is via the config file or command-line flags.

The one exception is that `ALLOW_CUSTOM_UPDATE_SCRIPTS`, `UPDATE_SHA256`, and `UPDATE_URL` can technically be set as environment variables, but in practice they are always read from the config file.
