# Safety, Security & Destructive Operations

This document covers DAM's safety mechanisms, security considerations, and destructive command behavior.

---

## Destructive Commands Overview

| Command | What It Removes | Confirmation Required |
| :------ | :-------------- | :-------------------- |
| `delete <app>` | Containers, networks (project-level) | No (single app) |
| `delete all` | Containers, networks for ALL apps | Yes - must type `"yes"` (or pass `-y`) |
| `kill/stop/recreate/force-recreate all` | Action on ALL apps globally | Yes - must type `"yes"` (or pass `-y`) |
| `delete <app> with vol` | + Named/anonymous volumes | No additional prompt |
| `delete <app> with img` | + All images used by services | No additional prompt |
| `delete <app> with buildx`| + Prunes build cache globally afterwards | No additional prompt |
| `delete <app> with all` | + Volumes + Images | No additional prompt |
| `update <app>` | Pulls/builds images, recreates containers | No (single app) |
| `cleanup` | Dangling (untagged) images only | No |
| `cleanup img` | **All** unused images system-wide | Yes - `y/N` prompt |
| `cleanup vol` | **All** unused volumes system-wide | Yes - `y/N` prompt |
| `cleanup net` | **All** unused networks system-wide | Yes - `y/N` prompt |
| `cleanup buildx`| **All** build cache system-wide | No |
| `cleanup all` | All of the above (img, vol, net, buildx) | Yes - separate prompts |
| `force-recreate` | Containers (immediate kill, no grace period) | No (single app) |
| `recreate` | Containers (graceful shutdown) | No (single app) |

---

## Confirmation Prompts

### `delete all` Confirmation

When running `delete all` (with or without `except`):

```
[WARNING] You are about to run 'delete' on ALL apps listed above!
Type 'yes' to proceed:
```

The user must type the exact string `"yes"` (not just `y` or `Y`). Any other input cancels the operation.

### Volume Prune Confirmation

```
[WARNING] YOU ARE ABOUT TO DELETE UNUSED VOLUMES!
This will permanently delete data for any apps that are currently stopped or deleted.
Are you absolutely sure you want to proceed? [y/N]
```

### Image Prune (All Unused) Confirmation

```
[WARNING] YOU ARE ABOUT TO DELETE ALL UNUSED IMAGES!
This will permanently delete all downloaded Docker images that are not currently tied to a running container.
Are you absolutely sure you want to proceed? [y/N]
```

### Network Prune Confirmation

```
[WARNING] YOU ARE ABOUT TO DELETE UNUSED NETWORKS!
This will remove externally managed networks (e.g. a reverse proxy network) if no containers are currently attached, which can break stacks that are stopped.
Are you absolutely sure you want to prune networks? [y/N]
```

### Custom Update Script Confirmation

When `ALLOW_CUSTOM_UPDATE_SCRIPTS` is `false` (default):

```
[INFO] Custom update script found: update-<app2>.sh
Do you want to run this custom update script? [y/N]
```

---

## Non-Interactive (No TTY) Behavior

When the script detects no terminal (e.g., running in a cron job, pipe, or CI/CD):

| Operation | Behavior |
| :-------- | :------- |
| `delete all` | Error: "requires confirmation, but input is not a terminal. Use -y / --yes to force." |
| Volume prune | Error: same message |
| Image prune (all) | Error: same message |
| Network prune | Error: same message |
| Custom update script | Warning logged, custom script **skipped**, falls back to compose update |

The `-y` / `--yes` flag bypasses all confirmations:

```bash
# Safe for automation:
dkr cleanup all -y
dkr delete all -y
```

---

## What Each `delete` Mode Preserves

### Default: `delete <app>`

```
docker compose [-f <file>...] down --remove-orphans
```

| Resource | Removed? |
| :------- | :------- |
| Running containers | ✅ Yes |
| Stopped containers (in project) | ✅ Yes |
| Orphan containers | ✅ Yes |
| Project networks | ✅ Yes |
| Named volumes | ❌ No (preserved) |
| Anonymous volumes | ❌ No (preserved) |
| Images | ❌ No (preserved) |

### `delete <app> with vol`

```
docker compose [-f <file>...] down --remove-orphans -v
```

Additionally removes:
- Named volumes declared in the Compose file's `volumes:` section
- Anonymous volumes attached to containers

### `delete <app> with img`

```
docker compose [-f <file>...] down --remove-orphans --rmi all
```

Additionally removes:
- All images used by the project's services

### `delete <app> with all`

```
docker compose [-f <file>...] down --remove-orphans -v --rmi all
```

Removes everything inside the project scope: containers, networks, volumes, and images. *(Note: it does not automatically include global `buildx` pruning)*.

### What about `with net`?

You may notice there is no `delete <app> with net`. That is because `docker compose down` **always** removes the project's internal networks by default. You do not need to explicitly ask it to delete networks. If you mistakenly type `with net`, DAM simply ignores it because the operation is already happening natively.

---

## Post-Action Cleanup (delete / update)

After `delete` or `update` completes, DAM automatically runs a global cleanup:

### Default behavior
```bash
cleanup_dangling_resources "basic"
# Equivalent to: docker image prune -f
```

This removes only **dangling** (untagged) images - layers left behind after image updates.

### With `buildx` modifier
```bash
cleanup_dangling_resources "buildx"
# Additionally: docker buildx prune -f
```

### Safety filter for `with` modifiers

When you append modifiers to `delete` (e.g., `with vol img buildx`), DAM passes the relevant flags to `docker compose down`. However, it **intentionally filters out** the global equivalents (`cleanup vol`, `cleanup net`, `cleanup img`) from the post-action cleanup script:

```bash
# Only buildx passes through to global cleanup
safe_cleanup_modes=()
for m in "${CLEANUP_MODES[@]}"; do
    if [[ "$m" == "buildx" ]]; then
        safe_cleanup_modes+=("buildx")
    fi
done
```

**Why?** Because `buildx` cache is safe to prune globally (it just means future builds take longer to download base layers). But if DAM passed `vol` or `net` through to the global cleanup, it would trigger `docker volume prune -a` and instantly delete **all unused volumes for every single app on your server**, causing massive data loss. This loop ensures that only safe global operations (`buildx` and default dangling images) run after a `delete`.

This prevents a command like `delete all with vol` from triggering a global `docker volume prune` that would destroy volumes for **all** apps on the system - not just the ones being deleted.

The `with vol` modifier on `delete` only affects the `docker compose down -v` flag, which removes volumes **at the project level**.

---

## Global vs App-Specific Cleanup

This distinction is critical to understand:

| Operation | Scope | What It Affects |
| :-------- | :---- | :-------------- |
| `delete <app> with vol` | **App-specific** | Only volumes declared in that app's Compose file |
| `cleanup vol` | **Global** | ALL unused volumes on the Docker host, including volumes from other apps |
| `delete <app> with img` | **App-specific** | Only images used by that app's services |
| `cleanup img` | **Global** | ALL unused images on the Docker host |

---

## Security Review

### Shell Command Construction

DAM constructs shell commands using variables and arrays. Key observations:

1. **No use of `eval`**: The script does not use `eval` anywhere. Commands are executed directly.

2. **Quoting**: Variables are generally quoted properly (e.g., `"$dir"`, `"$folder"`). The use of `set -u` catches unset variables.

3. **App names**: App names with spaces are explicitly rejected:
   ```bash
   if [[ "$target" =~ [[:space:]] ]]; then
       echo -e "${RED}[ERROR]${NC} App names with spaces are not supported"
       return 1
   fi
   ```

4. **`find` usage**: The `find` command uses `-name "$target"` which matches the exact directory name. Since spaces are rejected, this is safe from argument injection.

### Custom Update Script Execution

This is the most significant security consideration:

```bash
bash "$(basename "$custom_script")"
```

- Scripts are found via `find "$dir" -maxdepth 1 -name "update*.sh"`
- The script basename is passed to `bash`
- **There is no validation of the script content** - any code in `update*.sh` will be executed with the current user's privileges
- If DAM is run as root (or via sudo), custom scripts run as root

**Mitigation:**
- `ALLOW_CUSTOM_UPDATE_SCRIPTS` defaults to `false`
- When `false`, an interactive prompt is shown before execution
- Non-interactive execution skips custom scripts entirely (falls back to compose update)

### Config File Sourcing

```bash
source "$CONFIG_FILE"
```

The config file (`/etc/docker-app-manager.conf`) is sourced as Bash. Before sourcing it, DAM verifies that it is owned by `root` and is not group- or world-writable; it exits if either check fails. This protects against ordinary unprivileged modification, but root and other privileged actors remain trusted.

### Self-Update Security

- Downloads from `UPDATE_URL` (must be HTTPS)
- Validates the shebang line
- Runs `bash -n` syntax check
- Optional SHA-256 verification via `UPDATE_SHA256`
- Downloaded file goes to `/tmp` briefly (created with strict `umask 077` to prevent tampering), then to `/usr/local/bin/`

**Potential concern:** If `UPDATE_SHA256` is not set (the default), there is no integrity verification beyond the basic checks. An attacker who compromises the `UPDATE_URL` endpoint could serve malicious code.

### Privilege Requirements

| Operation | Privileges Needed |
| :-------- | :---------------- |
| Regular commands (start, stop, etc.) | Docker group membership (or root) |
| install, config, uninstall, self-update | Root (enforced via EUID check) |
| Custom update scripts | Same as the user running DAM |

### Directory Trust

DAM trusts the contents of directories in `SEARCH_DIRS`. It:
- Reads and uses compose files found in those directories
- Executes `update*.sh` scripts from those directories (if permitted)
- Changes working directory to those directories

Any user who can write files to directories in `SEARCH_DIRS` can influence DAM's behavior.

---

## Best Practices

1. **Don't run DAM as root for regular operations** - use Docker group membership instead
2. **Keep `ALLOW_CUSTOM_UPDATE_SCRIPTS=false`** unless you trust all update scripts
3. **Set `UPDATE_SHA256`** if using self-update in production
4. **Use `-y` carefully** - it bypasses all safety prompts
5. **Prefer specific app names over `all`** for destructive operations
6. **Understand the global vs app-specific distinction** before running `cleanup vol`
7. **Restrict write access** to directories in `SEARCH_DIRS`

---

## Security Assurance Case

This section provides the security assurance case for **DAM (Docker App Manager)**, outlining the threat model, trust boundaries, secure design principles, and mitigations against common weaknesses.

### 1. Threat Model

DAM operates as a local Bash script designed to manage Docker Compose applications. 
**Target Environment:** Local execution on a Linux host (or WSL) by a system administrator or user with appropriate Docker permissions.
**Potential Threats:**
- **Local attackers:** Malicious actors with local access attempting to execute arbitrary commands, escalate privileges, or damage Docker stacks.
- **Malicious directories/filenames:** Path traversal or command injection via crafted application directory names.
- **Untrusted scripts:** Execution of malicious `update*.sh` files placed in application directories.

### 2. Trust Boundaries

- **The Host File System:** DAM assumes that the user running the script has read/write access to the `SEARCH_DIRS` configured. These directories are considered within the trust boundary.
- **Docker Daemon:** DAM interacts with the Docker Daemon (`docker.sock`). Anyone running DAM is assumed to already possess Docker daemon access (which is functionally equivalent to root access).
- **Configuration File (`/etc/docker-app-manager.conf`):** This file is sourced directly as a bash script. Modifying this file requires root privileges; therefore, it is outside the trust boundary of unprivileged users.

### 3. Secure Design Principles Applied

- **Fail-Safe Defaults (Strict Mode):** DAM enforces `set -euo pipefail`. Any undefined variable, command failure, or pipeline failure immediately terminates the script, preventing unpredictable or insecure states.
- **Least Privilege:** The script executes entirely with the invoking user's permissions. It does not require `sudo` to run its core lifecycle commands and does not attempt to elevate privileges independently.
- **Explicit Confirmation:** Destructive operations (e.g., `cleanup all` or `delete <app> with vol`) require explicit user confirmation.
- **Validation:** Applications are selected by explicitly scanning and matching directory names rather than evaluating arbitrary input strings as code.

### 4. Countering Common Implementation Weaknesses

- **Command/Shell Injection:** All inputs, variable expansions, and paths are strictly quoted (e.g., `"$APP_NAME"`). Shellcheck static analysis is enforced in the development pipeline to catch unquoted variables and injection risks.
- **Path Traversal:** File path resolution uses standard tools (like `find` and `basename`) to safely identify Compose files without relying on user-provided path concatenations.
- **Unintended Execution:** The custom `update*.sh` script feature requires explicit user approval or a specific configuration flag (`ALLOW_CUSTOM_UPDATE_SCRIPTS=true`) before arbitrary bash scripts found in app directories are executed.
