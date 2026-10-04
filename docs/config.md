# Configuration Semantics

`config` reruns DAM's interactive configuration wizard. It is the supported way to change where DAM searches for applications, which directory names it excludes, how its global command is invoked, and whether custom update scripts run automatically.

## Syntax and Privilege

```bash
sudo <cmd> config
```

In raw-command mode there is no prefixed command, so use:

```bash
sudo docker-app-manager config
```

`config` requires an effective UID of `0`; DAM exits before opening the wizard otherwise. The command reads from `/dev/tty`, so it is interactive by design and unsuitable for non-interactive automation.

Unlike lifecycle commands, `config` does not check Docker availability and does not start, stop, inspect, or delete application resources.

## What the Wizard Changes

The wizard writes `/etc/docker-app-manager.conf` and then updates the global command symlinks under `/usr/local/bin`. It has three configuration steps plus an optional self-update checksum.

### 1. Search Directories

DAM asks for full paths, separated by spaces, where it should discover applications. A path is accepted when it exists or when you explicitly choose to keep a missing path. Because paths are space-separated, paths containing spaces are unsupported.

For a new configuration, DAM suggests these defaults:

```text
/opt/stacks /opt/projects <real-user-home>/apps <real-user-home>/stacks
```

When invoked through `sudo`, DAM derives `<real-user-home>` from `SUDO_USER` when possible, rather than blindly using root's home directory. Existing configured directories are prefilled as the default on later runs.

### 2. Excluded Directory Names

DAM asks for directory basenames to ignore during discovery. Enter names separated by spaces, press Enter to retain existing exclusions, or enter `none` to clear them.

Exclusions are case-insensitive directory-name matches, not paths or patterns. An excluded app is omitted from `all` selection and skipped by lifecycle processing, although `list` can show it as `excluded`.

### 3. Global Command Name

The command name controls the symlinks DAM creates:

| Wizard choice | Result |
| :-- | :-- |
| Blank on a new installation | Uses `dkr` |
| A custom name such as `dam` | Creates `/usr/local/bin/dam`; invoke actions as `dam update app` |
| `none` | Creates raw action symlinks such as `/usr/local/bin/start`, `/usr/local/bin/cleanup`, and `/usr/local/bin/frec` |
| Blank with an existing custom command | Retains that existing command |

Before accepting a custom name, DAM checks whether it already resolves to another executable. In raw mode it checks every supported action name for conflicts and requires explicit confirmation even when none are found, because generic command names can collide with future tools.

Changing the command name removes DAM-managed symlinks for the old mode and creates the symlink or symlinks for the new mode. DAM only removes raw symlinks that point to `/usr/local/bin/docker-app-manager`.

### 4. Custom Update Scripts

The wizard writes `ALLOW_CUSTOM_UPDATE_SCRIPTS` as `true` or `false`. `true`, `y`, and `yes` enable automatic execution of a discovered `update*.sh` during `update`; every other nonblank response is stored as `false`.

With the default `false`, an interactive `update` prompts before running the script. A non-interactive update skips the custom script and falls back to the Compose update path. The scripts are arbitrary Bash code, so enable automatic execution only for trusted application directories.

### Optional: Self-Update Checksum

The wizard can store an `UPDATE_SHA256` value. When nonempty, `self-update` must match the downloaded script's SHA-256 before replacing the installed binary. DAM preserves an existing value when the prompt is left blank; it does not validate that the entered value has SHA-256 format.

## Generated Configuration

The wizard manages these Bash assignments in `/etc/docker-app-manager.conf`:

```bash
SEARCH_DIRS=("/opt/stacks" "/home/alice/apps")
EXCLUDE_DIRS=("recovered" "unused")
CUSTOM_CMD_NAME="dkr"
ALLOW_CUSTOM_UPDATE_SCRIPTS="false"
UPDATE_SHA256="optional-expected-sha256"
UPDATE_URL="https://gh.upputuri.in/dam.sh"
```

`SEARCH_DIRS` and `EXCLUDE_DIRS` are arrays. DAM removes and rewrites only its managed assignment lines, preserving other lines already present in the file. At startup, DAM sources this file as Bash, so it must be writable only by trusted administrators.

The wizard retains the current `UPDATE_URL` if one is configured; it does not prompt to change that URL.

## Relationship to Installation

`config` updates configuration and command symlinks but does not install or replace the core `/usr/local/bin/docker-app-manager` binary. Use:

```bash
sudo ./dam.sh install
```

to install DAM or reinstall its core symlink, and:

```bash
sudo ./dam.sh install refresh
```

to rebuild command symlinks non-interactively from the existing configuration. More detail is available in [setup.md](setup.md).

## Examples

```bash
# Reconfigure a prefixed installation.
sudo dkr config

# Reconfigure an installation using raw action names.
sudo docker-app-manager config
```
