# List Semantics

This document explains exactly how DAM's `list` command works, detailing its discovery mechanism, status reporting, and different output modes.

---

## Overview

The `list` command is used to display an inventory of discovered applications. It supports two primary modes of operation depending on the arguments provided.

1. **High-level Inventory** - when run without arguments, it scans all configured search directories.
2. **Detailed App Info** - when provided with specific app names, it targets only those applications.

---

## Global Inventory (No Arguments)

When you run `list` without any arguments, DAM performs a full scan of all your configured search directories to build a high-level inventory table.

### Syntax
```bash
dkr list
```

### Discovery Process
1. DAM iterates through all valid directories defined in `SEARCH_DIRS` (from `/etc/docker-app-manager.conf`).
2. It respects the `MAX_SEARCH_DEPTH` (default is 3).
3. It ignores any directories matching the names in `EXCLUDE_DIRS`.
4. It identifies valid "apps" by looking for standard compose files (`compose.yaml`, `compose.yml`, `docker-compose.yaml`, `docker-compose.yml`) or custom update scripts (`update*.sh`).

### Status Determination
DAM performs a single optimized query to determine the state of all compose projects simultaneously, populating an internal cache:
```bash
docker ps -a --filter "label=com.docker.compose.project" --format '{{.Label "com.docker.compose.project"}}|{{.State}}'
```
This entirely avoids querying Docker individually for each app.

### Output Table Columns
- **APP**: The discovered directory name.
- **PROJECT**: The effective Docker Compose project name, if it differs from the folder name. Otherwise, it shows `-`.
- **LOCATION**: The absolute path to the app (paths under `$HOME` are shortened with `~`).
- **COMPOSE**: The name of the primary compose file detected (or `-` if it relies solely on a custom update script).
- **STATUS**: The overall state of the app.
  - `running`: If at least one container in the project is currently running.
  - `stopped`: If containers exist but none are running.
  - `inactive`: If no containers currently exist for this app.
  - `excluded`: If the app matches an entry in `EXCLUDE_DIRS`.

---

## App-Specific Details (With Arguments)

When you pass specific app names (or use the `all` selector), DAM skips the global directory scan and focuses only on locating and reporting on the requested apps.

### Syntax
```bash
dkr list <app-name> [app-name ...]
dkr list all
dkr list all except <app-name> [app-name ...]
```

### Discovery Process
1. DAM uses its optimized `find_app_dir` routine to locate the specific directories for the requested apps (or discovers all non-excluded apps if `all` is used).
2. If multiple apps share the exact same case-sensitive name across different search directories, DAM will report a `DUPLICATE` error. *(Note: Thanks to smart hybrid-case matching, apps like `n8n` and `N8n` are safely recognized as unique).*
3. If an app cannot be found, it is simply omitted from the final table.

### Status Determination
For each specified app, DAM uses the same highly optimized global `docker ps -a` query cache to determine the state, rather than running individual Docker queries for each app.
1. It checks the cache to see if the app has a `running` status.
2. If not, it checks the cache to see if the app is `stopped` (meaning containers exist but none are running).

### Output Table Columns
- **APP**: The folder name.
- **PROJECT**: The effective project name, if different from the folder name.
- **PATH**: The exact path where the app was found.
- **COMPOSE FILE**: The detected compose file.
- **OVERALL STATE**: `running`, `stopped`, `inactive`, or `excluded`.

---

## The difference between `list` and `list all`

While they sound similar, they produce different output using different mechanics:

- **`dkr list` (No arguments):** A highly-optimized **Global Inventory Scan**. It scans your directories and outputs *everything* it finds, including apps/directories you have explicitly excluded (which it marks with status `excluded`). It does this incredibly fast using a single Docker query.
- **`dkr list all` (With arguments):** A targeted **Detailed App-Level Query**. Because it uses the word `all`, it goes through DAM's standard target parsing. It builds a list of *targetable apps*, meaning any excluded apps are entirely stripped out. It then reads their status from the same optimized global Docker query cache to determine their exact running state. 

---

## Examples

```bash
# Runs the global inventory scan (shows everything, very fast)
dkr list

# Runs the detailed app-level query for specific apps
dkr list <app2> <app-name> <app3>

# Runs the detailed app-level query for ALL targetable apps (omits excluded ones)
dkr list all

# Runs the detailed app-level query for all apps EXCEPT specific ones
dkr list all except <app3> <app4>
```

---

> **Want more detailed information?**  
> If you need deep-dive container-level details (such as container IDs, networks, volumes, image IDs, health statuses, and port mappings) for specific apps, look at the [`get`](get.md) command documentation instead. `dkr get <app> info` is designed exactly for this purpose.
