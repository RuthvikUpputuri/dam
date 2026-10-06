# Installation & Setup

This document explains the entire lifecycle of getting DAM onto (and off) your system. It covers the installation wizard, system integration, configuration refreshing, and the complete uninstallation process.

---

## Table of Contents
- [Interactive Installation](#interactive-installation)
- [Non-Interactive Refresh](#non-interactive-refresh)
- [File Locations](#file-locations)
- [Uninstalling](#uninstalling)

---

## Interactive Installation

When run without arguments, the install command launches an interactive wizard to configure DAM globally.

### Syntax
```bash
sudo ./dam.sh install
```

### Step 1: Pre-Check & Upgrades
If an existing configuration file is found at `/etc/docker-app-manager.conf`, DAM will prompt:
`Do you want to just update the script and keep your existing settings? (Y/n)`
- **Yes**: Skips the configuration wizard and proceeds directly to reinstalling symlinks.
- **No**: Proceeds to the configuration wizard, pre-filling defaults based on your existing config.

### Step 2: Search Directories
DAM prompts for the locations of your Docker Compose apps.
- **Default**: `/opt/stacks /opt/projects ~/apps ~/stacks` (resolved to the actual user's home directory if using `sudo`).
- **Validation**: DAM checks if the paths contain spaces (which are unsupported) and warns you if a specified directory does not currently exist.

### Step 3: Exclude Directories
DAM prompts for folder names to permanently ignore during scans.
- Useful for skipping folders like `recovered`, `backups`, or `unused`.

### Step 4: Custom Command Name
DAM configures how you invoke it globally.
- **Raw Commands**: If you enter `none`, DAM creates global symlinks for every individual action (`start`, `stop`, `update`, etc.). DAM will aggressively scan your system's `PATH` to ensure these generic names don't conflict with existing system binaries.
  <br>⚠️ **WARNING**: Raw Mode is NOT recommended unless you are an advanced Linux user. Hijacking extremely common words like `start`, `stop`, or `update` in `/usr/local/bin` can break completely unrelated applications, cron jobs, or system utilities that rely on those verbs.
- **Custom Prefix**: The recommended approach. If you enter a name like `dkr`, `dam`, or `app`, DAM creates a single symlink, allowing you to run commands like `dkr update <app-name>`.

### Step 5: Security & Updates
- **Custom Update Scripts**: DAM asks whether `update*.sh` scripts should execute automatically (`true`) or require interactive confirmation (`false`) during an `update` action.
- **Update SHA-256**: For strict security environments, you can specify a SHA-256 hash that the `self-update` command must verify before applying any new script versions.

### Step 6: System Integration
1. DAM saves your choices to `/etc/docker-app-manager.conf`.
2. It installs `/usr/local/bin/docker-app-manager`: a temporary source under `/tmp` or `/var/tmp` is copied there, while a persistent source is linked so its edits are immediately live globally.
3. It cleans up any old, orphaned symlinks if you changed your command name.
4. It creates the new command symlinks based on your choices. Note that `frec` is created as an alias for `force-recreate`.

---

## Non-Interactive Refresh

While running `sudo ./dam.sh install` again will perfectly update your existing installation (via an interactive `(Y/n)` prompt), the `refresh` argument serves a very specific, crucial purpose: **Non-interactive execution**.

The `refresh` argument is designed to be used by the `self-update` system and automated scripts (like cron jobs). When `self-update` downloads a new version of DAM, that new version might introduce entirely new commands (e.g., if a `debug` command is added in `v1.2`). Because `self-update` runs in the background, it cannot get stuck waiting for a human to answer interactive prompts. 

Instead, it calls `install refresh`, which silently re-reads your existing `/etc/docker-app-manager.conf`, rebuilds all necessary system symlinks to expose any new commands, and exits immediately with zero prompts. You can also use this manually if you hand-edit the config file and want to apply the changes instantly.

### Syntax
```bash
sudo ./dam.sh install refresh
```
*(Note: If you already have DAM installed globally, you can also run `sudo dkr install refresh`)*

### Behavior
1. Ensures a directly invoked source is installed as the core executable, copying a temporary source and linking a persistent one; an existing global core executable is left intact.
2. Sources `/etc/docker-app-manager.conf`.
3. Force-removes all currently managed symlinks in `/usr/local/bin`.
4. Re-creates the symlinks based strictly on the `CUSTOM_CMD_NAME` defined in the config.
5. Exits silently with code 0 on success.

---

## File Locations

- **Main Script Path**: For a persistent-source installation, do not delete the original `dam.sh`, because the global core executable links to it. The temporary script used by Quick Install can be deleted after setup.
- **Configuration File**: `/etc/docker-app-manager.conf`
- **Global Binary**: `/usr/local/bin/docker-app-manager`, a copied executable for temporary sources or a symlink for persistent sources
- **User Commands**: `/usr/local/bin/<your-custom-name>` or `/usr/local/bin/start`, etc.

---

## Uninstalling

The `uninstall` command is designed to cleanly remove the DAM installation from the host system. It reverses the actions performed by the `install` command, ensuring that no dangling symlinks or configuration files remain.

### Syntax

```bash
sudo dkr uninstall
```

**Note on Raw Mode:** If you configured DAM in "raw mode" (where `none` was selected during installation and individual action symlinks were created), you must use the underlying script directly to uninstall:
```bash
sudo docker-app-manager uninstall
```

### Uninstall Flow

When the `uninstall` command is invoked, DAM performs the following steps sequentially:

1. **Privilege Verification**: DAM checks if the command is being run with `root` privileges. Because it needs to remove files from `/usr/local/bin` and `/etc`, it will immediately fail with an error if run as a standard user.
2. **Symlink Cleanup**: Instead of blindly removing files, DAM dynamically determines what symlinks were created:
   - It reads the `CUSTOM_CMD_NAME` from `/etc/docker-app-manager.conf`.
   - If a custom name (e.g., `dkr`) was used, it attempts to remove `/usr/local/bin/dkr`.
   - If raw mode was used (empty string `""`), DAM loops through its internal array of supported actions (`start`, `stop`, `update`, etc.) and removes the corresponding symlinks in `/usr/local/bin/`.
   - **Safety Check:** Before deleting any symlink, DAM uses `readlink -f` to verify that the symlink actually points to `/usr/local/bin/docker-app-manager`. If a user manually created a command with the same name that points elsewhere, DAM will skip it.
3. **Core Binary Removal**: DAM deletes the main script (`rm -f /usr/local/bin/docker-app-manager`).
4. **Configuration File Removal**: DAM removes the global configuration file (`rm -f /etc/docker-app-manager.conf`).

### What It Does NOT Remove

The `uninstall` command is strictly scoped to the DAM utility itself. It does **not** touch your Docker applications or resources. 

Specifically, it **will not**:
- Delete any containers, networks, or volumes.
- Delete or modify any of your Docker Compose project directories.
- Remove Docker or the Docker Compose plugin from your system.
- Prune any Docker images or cache.
