# Update Semantics

This document explains exactly how DAM's `update` command works, including custom update scripts, state preservation, and post-update behavior. 

---

## Overview

The `update` command is DAM's most complex lifecycle operation. For each app, it follows one of two paths:

1. **Custom script path** - if an `update*.sh` script exists in the app directory
2. **Standard compose path** - pull images, build, recreate

---

## Standard Compose Update Flow

When no custom script is found (or the user declines to run it):

### Explicit Compose Files

When this standard Compose path runs, append `using <file1> <file2>...` to select files explicitly. If none of the requested files resolve for an app, `update` logs an informational message and falls back to that app's default Compose file. If one or more resolve, DAM uses only the resolved files and warns about any misses. A permitted `update*.sh` runs instead of the Compose path and does not consume these file selections.

### Step 1: Check Running State

Before making any changes, DAM checks whether the app has any running containers:

```bash
# Get container IDs for the project
running_containers="$(docker compose ps -q)"

# Check if any are actually running
docker inspect -f '{{.State.Running}}' "$cid"
```

This determines whether the app should be restarted after the update.

### Step 2: Pull Images (1/4)

```bash
# Preferred (newer Docker Compose):
docker compose [-f <file>...] pull --ignore-buildable

# Fallback (older Docker Compose):
docker compose [-f <file>...] pull --ignore-pull-failures
```

DAM dynamically checks whether `--ignore-buildable` is supported by inspecting `docker compose pull --help`. If the flag is not found in the help output, it falls back to `--ignore-pull-failures`.

**`--ignore-buildable`** skips services that have a `build` section (since they'll be built locally, not pulled from a registry).

**`--ignore-pull-failures`** is the older equivalent - it ignores pull failures (which includes services that can't be pulled because they're meant to be built).

**If pull fails entirely** (e.g., image not found, registry down), Docker's exact error message will be printed to your screen, and the update process will immediately abort for this specific app (preventing broken containers from being created).

### Step 3: Build Images (2/4)

```bash
docker compose [-f <file>...] build --pull
```

This rebuilds any services that have a `build` section in the Compose file. The `--pull` flag ensures that **base images** (the `FROM` line in Dockerfiles) are refreshed from the registry, not just pulled from the local cache.

**If build fails**, the update is aborted for this app.

### Step 4: Recreate Containers (3/4)

**If the app was running:**
```bash
docker compose [-f <file>...] up -d
```

This recreates containers with the newly pulled/built images. Docker Compose detects that images have changed and recreates the relevant containers.

**If the app was stopped:**
```
[INFO] Skipping container startup (app was stopped).
```

The app remains stopped. Images are updated, but containers are not recreated. The next time the app is started (via `start` or `recreate`), it will use the new images.

### Step 5: Show Status (4/4)

```bash
docker compose ps
```

---

## Custom Update Script Path

### Discovery

DAM searches for files matching the glob `update*.sh` in the app directory:

```bash
find "$dir" -maxdepth 1 -name "update*.sh" -print0 | sort -z
```

Only the **first script alphabetically** is selected. For example, if a directory contains:
- `update-backup.sh`
- `update-migrate.sh`
- `update.sh`

DAM will select `update-backup.sh` (alphabetically first).

> **Note:** Only one custom script is executed per update. If you need multiple steps, combine them into a single script.

### Permission Check

The behavior depends on `ALLOW_CUSTOM_UPDATE_SCRIPTS`:

| `ALLOW_CUSTOM_UPDATE_SCRIPTS` | Terminal Available | Behavior |
| :---------------------------- | :----------------- | :------- |
| `true` | Any | Script runs immediately, no prompt |
| `false` (default) | Yes (TTY) | Prompts: "Do you want to run this custom update script? [y/N]" |
| `false` (default) | No (no TTY) | Warning logged, falls back to compose update |

### Execution

```bash
pushd "$dir"
bash "$(basename "$custom_script")"
```

- The script is executed via `bash`, not sourced
- Working directory is set to the app directory
- The script's exit code determines success/failure
- If the script succeeds, no further update steps are taken
- If the script fails, the app is marked as failed

### Security Considerations

Custom update scripts are arbitrary shell scripts that DAM executes. See [Safety & Security](safety.md) for security implications.

---

## Post-Update Cleanup

After all apps have been processed, DAM runs a global dangling resource cleanup:

```bash
cleanup_dangling_resources "${safe_cleanup_modes[@]}"
```

### What Gets Cleaned

By default (no `with` modifiers):
- **Dangling images only**: `docker image prune -f`


---

## State Diagram

```
                ┌─────────────────┐
                │  update <app>   │
                └────────┬────────┘
                         │
                         ▼
                ┌────────────────────┐
                │ Has update*.sh?    │
                └──┬─────────────┬───┘
                   │ Yes         │ No
                   ▼             │
            ┌──────────────┐     │
            │ Allowed?     │     │
            └──┬────────┬──┘     │
               │ Yes    │ No     │
               ▼        │       │
      ┌────────────┐    │       │
      │ Run script │    │       │
      └──┬──────┬──┘    │       │
         │      │       │       │
     Success  Fail      │       │
         │      │       ▼       ▼
         │      │  ┌──────────────────┐
         │      │  │ Check running    │
         │      │  │ state            │
         │      │  └────────┬─────────┘
         │      │           │
         │      │           ▼
         │      │  ┌──────────────────┐
         │      │  │ pull images      │
         │      │  │ --ignore-        │
         │      │  │ buildable        │
         │      │  └────────┬─────────┘
         │      │           │
         │      │           ▼
         │      │  ┌──────────────────┐
         │      │  │ build --pull     │
         │      │  └────────┬─────────┘
         │      │           │
         │      │           ▼
         │      │  ┌──────────────────┐
         │      │  │ Was running?     │
         │      │  └──┬────────────┬──┘
         │      │     │ Yes        │ No
         │      │     ▼            ▼
         │      │  ┌────────┐  ┌──────────┐
         │      │  │ up -d  │  │ Skip     │
         │      │  └───┬────┘  │ startup  │
         │      │      │       └────┬─────┘
         │      │      │            │
         ▼      ▼      ▼            ▼
      ┌────────────────────────────────┐
      │         Show status            │
      │         docker compose ps      │
      └────────────────────────────────┘
```

---

## Examples

```bash
# Update a single app (standard compose flow)
dkr update <app-name>

# Update all apps except the reverse proxy
dkr update all except <proxy-app>

# Update an app with a custom set of compose files
dkr update myapp using compose dev prod
```
