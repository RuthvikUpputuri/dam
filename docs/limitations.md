# Limitations & Known Issues

This document honestly describes the architectural limitations, edge cases, and known issues in DAM.

---

## Architectural Limitations

### One Compose Project Per Directory

DAM fundamentally manages **one core Compose project per directory**.

By default, DAM executes `docker compose` without explicit `-f` flags, so standard override files (like `docker-compose.override.yml` or `compose.override.yaml`) **are** automatically detected and merged by Docker Compose itself.

If a directory contains multiple *primary* Compose files and you don't use the `using` modifier, Docker Compose natively processes only the first one it finds. See [Default Compose Files in commands.md](commands.md#default-compose-files) for the exact priority order.

The other primary files are ignored unless explicitly specified with the `using` modifier.

### Directory-Based Naming

By default, app names are derived strictly from directory basenames. This means:

- **No two apps can share the same directory name** across different search roots
- Directory names must not contain spaces
- Renaming a directory effectively changes the app's identity

### Project Name Overrides

If you explicitly override the project name (using `COMPOSE_PROJECT_NAME` in a `.env` file or `name:` in your compose file), DAM will seamlessly respect this override. In these specific cases, you must use that custom name (instead of the directory name) when interacting with the app in DAM.

### Compose-Only Orchestration

DAM is designed exclusively for standalone Docker Compose. It does not work with:

- Docker Swarm (`docker stack deploy`)
- Kubernetes

### Search Depth Limit

Discovery uses `find -maxdepth "${MAX_SEARCH_DEPTH}"` (which defaults to 5). Apps nested deeper than this setting below a search root will not be found. This depth limit can be increased in the configuration file. The `maxdepth` only applies to the depth below the search roots defined in `SEARCH_DIRS`.

Every qualifying directory within that depth is independently discovered. For example, `beta/old/compose.yaml` makes `old` an app even when it is only an archive below `beta`. If a directory should not be used as an app, add its basename to `EXCLUDE_DIRS` in `/etc/docker-app-manager.conf` to prevent discovery.

### Remote Docker Hosts

DAM invokes the Docker CLI and therefore honors the current Docker context and `DOCKER_HOST` configuration. However, DAM discovers applications and runs Compose on the machine where DAM itself is running. The app directories and Compose files (including any local files they reference, such as bind-mount sources) must be available on that machine. Pointing Docker at a remote daemon does not move those files to the remote host.

DAM does not provide a separate remote file discovery or deployment layer.

---

## Compose Feature Limitations

### Profiles

Docker Compose profiles (`profiles:` in the Compose file) are not explicitly handled by DAM. The `docker compose up -d` command (used by `start`) starts all services without profiles unless the `COMPOSE_PROFILES` environment variable is set.

DAM does not provide a custom CLI flag to specify profiles (e.g., `dam start myapp --profile dev`). However, because DAM relies on native Docker Compose, you can still use profiles by defining `COMPOSE_PROFILES=your_profile` in the app's `.env` file, which Docker Compose will automatically read.

### Environment Files

DAM does not manage `.env` files or environment variable interpolation. These are handled natively by Docker Compose when it reads the Compose file. DAM simply changes to the directory and runs `docker compose`, so `.env` files in the app directory work as expected.

### Compose File Includes

Docker Compose's `include:` directive (for splitting large Compose files) is handled natively by Docker Compose, not by DAM. DAM only detects the presence of the main Compose file - it does not parse or validate its contents.


### Compose Watch / Develop

DAM does not interact with `docker compose watch` or the `develop:` section. These are development-time features outside DAM's lifecycle management scope.

---

## Command-Specific Limitations

### `update` Custom Script Selection

When multiple `update*.sh` scripts exist in a directory, DAM selects **only the first one alphabetically** via `find | sort` and takes the first result. If you have:

- `update-backup.sh`
- `update-migrate.sh`
- `update.sh`

Only `update-backup.sh` will be executed. The others are ignored. If you need multiple steps, combine them into a single script.

### `debug` Command

The `debug` command is a placeholder that outputs "[TODO] Debug feature is coming soon." and returns success. It does not provide any debugging functionality.

### `get` Command Limitations

**1. Single Resource Fetching**
You can only query exactly **one** raw resource type per command. Trying to chain them (like `dkr get <app-name> cid vol`) will explicitly fail. If you need multiple metrics, you must either run the command twice or use the `info` table.

**2. Resource Output Format**
The `get` command's output format differs based on whether a specific service is targeted:

- With `app:service` → raw value only
- Without service → `service: value` format

This inconsistency may complicate scripting if you're not expecting it.

### `status` Container Matching

The `status` command matches containers using Docker labels (`com.docker.compose.project`). This means:

- Apps that have never been started will show no containers
- Apps started outside of DAM (e.g., via `docker compose up` directly in the directory) will be matched normally (DAM seamlessly supports project name overrides if you used them).

### `list` Inventory Without Docker

If Docker is available, `list` enriches the output with container status. If Docker is not running, the `list` command still works for inventory but shows "inactive" for all apps.

### `list` and Custom Compose Files

The `list` command strictly outputs the *primary* Compose file detected during discovery (e.g., `compose.yaml`). Appending `using <file1>...` to a `list` command will not change the "COMPOSE FILE" column in the output.

---

## Cleanup Behavior

### `with vol` on `delete` vs `cleanup vol`

These are fundamentally different operations:

| Operation | Docker Command | Scope |
| :-------- | :------------- | :---- |
| `delete <app> with vol` | `docker compose down -v` | Project-level: only removes volumes from the Compose file |
| `cleanup vol` | `docker volume prune -a -f` | Host-level: removes ALL unused volumes system-wide |

### Post-Delete/Update Cleanup Safety Filter

The `with vol`, `with net`, `with img` modifiers on `delete` are **intentionally filtered out** from the post-operation global cleanup. Only `with buildx` passes through. This is a safety measure documented in the source code.

This means `delete all with vol net` will:
1. Run `docker compose down --remove-orphans -v` for each app (removes project volumes)
2. Run a basic dangling image cleanup globally
3. **NOT** run `docker volume prune` or `docker network prune` globally

### Volume Prune Fallback

DAM tries `docker volume prune -a -f` first, which removes all unused volumes (available in newer Docker versions). If that fails, it falls back to `docker volume prune -f` (without `-a`), which removes only anonymous/dangling volumes.

### Build Cache Limitations

DAM tries `docker buildx prune -a -f` first. If that fails, it falls back to `docker builder prune -a -f`. This ensures compatibility with different Docker versions.

**Important Limitations:**
- **Default Builder Only:** DAM only prunes the default BuildKit builder instance. It does not automatically detect or prune custom isolated builders (e.g., those created via `docker buildx create`).
- **No Advanced Flags:** DAM strictly uses its own simplified arguments (e.g., `cleanup buildx`) and does not currently allow passing custom native arguments like `--builder <name>`, `--filter`, or `--keep-storage` through to the underlying prune command.

---

## Shell & OS Limitations

### Bash-Only

DAM is a Bash script and requires Bash specifically. It will not work with:

- `zsh` (unless invoked as `bash dam.sh`)
- `dash` (common `/bin/sh` on Ubuntu)
- `fish`
- `sh`

The shebang `#!/usr/bin/env bash` ensures Bash is used when the script is executed directly.

### Linux-Primary

DAM is designed for and tested on Linux. While it may work on:

- macOS (if Bash 4.4+ is installed, e.g., via Homebrew - macOS ships with Bash 3.2)
- WSL2 (Windows Subsystem for Linux)

These platforms are not explicitly supported or tested.

### Color Output

DAM uses ANSI escape codes for colored output. These may not render correctly in:

- Non-terminal outputs (log files, CI/CD outputs without ANSI support)
- Terminals that don't support ANSI codes
- Windows terminals (without ANSI support)

---

## Security Considerations

### Custom Update Scripts

`update*.sh` scripts are executed via `bash` with the current user's privileges. There is no sandboxing, validation, or content inspection. If DAM is run as root, custom scripts run as root.

### Config File

The config file at `/etc/docker-app-manager.conf` is sourced as Bash code. Anyone who can write to this file can execute arbitrary code the next time DAM runs.

### Self-Update Without SHA256

If `UPDATE_SHA256` is not set (the default), self-update performs only basic validation (shebang check, syntax check). It does not verify the integrity of the downloaded script against a known-good hash.

---

## Known Edge Cases

1. **Race condition in multi-app operations**: If Docker resources are shared between apps (e.g., external networks), operating on multiple apps simultaneously could cause unexpected behavior. DAM processes apps sequentially, which mitigates but doesn't eliminate this risk.

2. **Orphan detection**: `--remove-orphans` only removes orphan containers for the current project. If a service was renamed and the old container was started by a different tool, it may not be detected as an orphan.

3. **`get_app_compose_file` with update-only apps**: If a directory has no Compose file but has an `update*.sh` script, `get_app_compose_file()` returns the basename of the update script. This is used in the `list` output where it may appear confusing (showing a `.sh` file in the "COMPOSE" column).

4. **App name matching is case-sensitive**: `dkr start N8n` will not match a directory named `n8n`.

5. **Concurrent DAM invocations**: Running multiple DAM instances simultaneously for the same apps could cause conflicts. There is no locking mechanism.

6. **The `using` modifier file priority**: A bare file like `<name>.yml` will take precedence over a prefixed file like `compose.<name>.yml` when using a shorthand like `using <name>`. See [The `using` Modifier in commands.md](commands.md#the-using-modifier) for the exact resolution priority order.

7. **The `using` modifier with partial matches**: If you provide multiple files (e.g., `using base prod`) and an app only has `base.yml` but not `prod.yml`, DAM will strictly run with just `base.yml` and print a warning that `prod` was not found for that specific app. If none of the requested files are found, only `stop`, `recreate`, `force-recreate`, and `delete` fail rather than falling back to the default Compose file; other actions keep the fallback. At the very end of the run, DAM prints a global summary explicitly listing which specific apps were missing the file.
