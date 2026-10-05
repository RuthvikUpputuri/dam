# Application Discovery

This document explains exactly how DAM discovers, resolves, and maps application names to Docker Compose projects.

---

## Overview

DAM uses a filesystem-based discovery model:

```
User provides app name (e.g., "<app-name>")
    ↓
DAM searches configured directories for a directory named "<app-name>"
    ↓
Validates that the directory contains a Compose file (or update script)
    ↓
Uses the directory as the working directory for Docker Compose commands
```

By default, the **directory basename** is the application name. The **directory itself** is the Compose project context.

---

## Search Roots

DAM searches for apps in the directories listed in `SEARCH_DIRS`.

### When Installed (config file exists)

Directories are loaded from `/etc/docker-app-manager.conf`:

```bash
SEARCH_DIRS=("/opt/stacks" "/home/user/apps")
```

### When Not Installed (no config file)

DAM uses fallback defaults. It checks each of these paths and includes them only if they **actually exist**:

1. `/opt/stacks`
2. `/opt/projects`
3. `$HOME/apps` (using the real user's home, even under `sudo`)
4. `$HOME/stacks`

The `sudo` handling is notable: if the script is run via `sudo`, DAM resolves the original user's home directory using `getent passwd "$SUDO_USER"` rather than using root's `$HOME`.

---

## Search Behavior

### Depth

DAM uses `find` with `-mindepth 1 -maxdepth 5`. This means:

- Subdirectories at depth 1 through 5 under each search root are examined
- The search root itself is not treated as an app
- Deeply nested directories (depth > 5) are not discovered unless configured in config file via the `MAX_SEARCH_DEPTH` variable
- Every examined directory that contains a qualifying Compose file is treated as a separate app. For example, `beta/old/compose.yaml` registers `old` as an app as well as any qualifying `beta` directory. If a directory should not be used as an app, add its basename to `EXCLUDE_DIRS` in `/etc/docker-app-manager.conf` (or configure it through `sudo <cmd> config`).

### Directory Exclusion

Directories whose **basename** matches any entry in `EXCLUDE_DIRS` exactly (case-sensitive) are pruned from the search:

```bash
EXCLUDE_DIRS=("recovered" "backups" "unused" "old")
```

Pruning uses `find -name "$excl" -prune`, which means:
- The excluded directory and all its children are skipped entirely
- Exclusion is by **name only**, not by full path.
- **Case-Sensitive Example:** If `EXCLUDE_DIRS=("recovered")`, a directory named `recovered` at any depth will be excluded. However, a directory named `Recovered` or `RECOVERED` will NOT be excluded, because DAM treats them as distinctly separate apps to preserve hybrid case matching.

### Validation

A directory is considered a valid app if it contains at least one of these files:

| Priority | Filename |
| :------- | :------- |
| 1 | `compose.yaml` |
| 2 | `compose.yml` |
| 3 | `docker-compose.yaml` |
| 4 | `docker-compose.yml` |

For the `update` command only, a directory is also valid if it contains an `update*.sh` file (even without a Compose file).

### Compose File Priority

When running commands, DAM selects the **first** file found in this order:

1. `compose.yaml`
2. `compose.yml`
3. `docker-compose.yaml`
4. `docker-compose.yml`

Only one Compose file is used per app. If multiple exist, the highest-priority one is selected. The others are ignored.

---

## Name Resolution

When you run a command like `dkr start <app-name>`, DAM resolves `<app-name>` through the `find_app_dir()` function:

### Step-by-Step Resolution

1. **Cache check**: If the app was previously resolved (or previously failed), return the cached result
2. **Space check**: If the name contains spaces, return an error
3. **Search**: Run `find` across all valid search directories looking for a directory named exactly `<app-name>` (or a directory whose Compose file explicitly overrides the name to `<app-name>`).
4. **Validate**: For each match, check that it contains a Compose file (or, for `update`/`list` with update mode, an `update*.sh` script)
5. **Result**:
   - **Exactly 1 match**: Cache and return the path
   - **Multiple matches**: Error - "Multiple matching apps found for '<app-name>'" with all paths listed
   - **No matches**: Return empty (subsequent code prints "App '<app-name>' not found")

### Caching

Results are cached in a Bash associative array (`APP_DIR_CACHE`) for the duration of the script run. Cache entries include:

- Valid paths for found apps
- `NOT_FOUND` for apps that weren't found
- `DUPLICATE:<paths>` for apps with multiple matches

This means if you reference the same app name multiple times (e.g., in `status` which resolves apps for both container lookup and directory resolution), the filesystem is only searched once.

---

## Duplicate Name Handling

If the exact same directory name (case-sensitive) exists under different search roots (or at different depths), DAM treats this as an error:

```
[ERROR] Multiple matching apps found for 'myapp':
  - /opt/stacks/myapp
  - /home/user/apps/myapp
```

*Note: DAM uses smart hybrid-case matching. This means `/opt/stacks/n8n` and `/opt/stacks/N8n` are correctly identified as two separate distinct applications. Duplicate errors are only thrown if two directories share the **exact same** case-sensitive spelling.*

There is **no precedence rule** between search roots. DAM does not prefer one search directory over another - it requires unique names which is also recommended in general by Docker.

### Resolution

To fix duplicate names:
- Assign a unique custom name in `.env` (`COMPOSE_PROJECT_NAME`) or `compose.yaml` (`name:`) to act as a distinct alias tie-breaker
- Rename one of the directories
- Remove the unwanted directory from `SEARCH_DIRS`
- Move one directory into an excluded directory name

---

## The `all` Selector

When you use `all`, DAM calls `get_all_apps()`, which:

1. Searches all valid search directories
2. Prunes excluded directories
3. Validates each found directory (Compose file or update script, depending on mode)
4. Excludes directories whose names are in `EXCLUDE_DIRS` (checked via `is_excluded()`)
5. Returns all valid app names

### `all except`

When you use `all except app1 app2`:

1. DAM first resolves all apps (as above)
2. Validates that each excepted app actually exists (if not, returns an error)
3. Filters out the excepted apps from the list

---

## Listing Apps

### `list` (no arguments)

The `inventory_apps_table()` function provides a comprehensive view:

- Scans all search directories
- Shows **every** valid app directory discovered
- Fully ignores standard directories that lack a Compose file
- Explicitly includes directories matching `EXCLUDE_DIRS` (to display them with an "excluded" status in the table), regardless of whether they have a Compose file
- Enriches with Docker status by querying `docker ps -a` and matching on the `com.docker.compose.project` label
- Status values: `running`, `stopped`, `inactive`, `excluded`

### Usage / Help Output

The `usage()` function calls `list_available_apps()` which shows a compact, columnar listing of discovered apps organized by search directory, with excluded apps shown separately.

---

## How App Name Maps to Compose Project

By default, Docker Compose uses the directory name as the project name. Since DAM changes to the app directory before running `docker compose`, the Compose project name naturally matches the directory name (which is the DAM app name).

This means:
- DAM app name = directory basename = Compose project name (by default)
- DAM's `status` and `get` commands use the `com.docker.compose.project` label to match containers, which reflects the actual Compose project name

### Edge Case: Overriding the Project Name

If you explicitly define a custom name in a `.env` file (`COMPOSE_PROJECT_NAME`) or a `compose.yaml` file (`name:`), DAM will seamlessly support it. In this scenario:
- The custom project name is accepted natively as a first-class alias for commands like `start`, `kill`, `update`, etc.
- If two completely different directories happen to share the exact same basename, setting a unique custom name for each allows you to bypass duplicate errors entirely! You can simply run commands using the unique aliases.
- `list` shows the folder name in the APP column and the custom name in the PROJECT column.
- `status`, `get` and container state matching inherently use the effective project name.

> **Parser Limitation:** To maintain lightning-fast discovery across dozens of stacks, DAM uses a lightweight text scanner (`awk`) rather than a full YAML/env evaluation engine to detect custom names. Because of this, it does not support multi-line names, complex quoting, or variable interpolation (e.g., `name: ${MY_ENV_VAR}`) for custom aliases. Stick to simple, hardcoded strings.


---

## Diagram

```
SEARCH_DIRS: ["/opt/stacks", "/home/user/apps"]
EXCLUDE_DIRS: ["recovered", "unused"]

/opt/stacks/
├── <app3>/             ← App "<app3>" (has compose.yaml)
│   └── compose.yaml
├── <app-name>/                 ← App "<app-name>" (has docker-compose.yml)
│   ├── docker-compose.yml
│   └── .env
├── recovered/           ← EXCLUDED (name in EXCLUDE_DIRS)
│   └── old-app/
│       └── compose.yaml
└── my-tools/            ← NOT an app (no compose file)
    └── scripts/

/home/user/apps/
├── <app2>/              ← App "<app2>" (has compose.yaml + update script)
│   ├── compose.yaml
│   └── update-<app2>.sh
└── custom-builder/      ← App "custom-builder" (update-only, no compose file)
    └── update.sh

Discovery Result:
  <app3>  → /opt/stacks/<app3>
  <app-name>      → /opt/stacks/<app-name>
  <app2>   → /home/user/apps/<app2>
  custom-builder → /home/user/apps/custom-builder  (update mode only)
```
