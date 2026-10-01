# Application Discovery

This document explains exactly how DAM discovers, resolves, and maps application names to Docker Compose projects.

---

## Overview

DAM uses a filesystem-based discovery model:

```
User provides app name (e.g., "n8n")
    ↓
DAM searches configured directories for a directory named "n8n"
    ↓
Validates that the directory contains a Compose file (or update script)
    ↓
Uses the directory as the working directory for Docker Compose commands
```

The **directory basename** is the application name. The **directory itself** is the Compose project context.

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

### Directory Exclusion

Directories whose **basename** matches any entry in `EXCLUDE_DIRS` are pruned from the search:

```bash
EXCLUDE_DIRS=("recovered" "recovered-configs" "unused")
```

Pruning uses `find -name "$excl" -prune`, which means:
- The excluded directory and all its children are skipped entirely
- Exclusion is by **name only**, not by full path - a directory named `recovered` at any depth under any search root will be excluded

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

When you run a command like `dkr start n8n`, DAM resolves `n8n` through the `find_app_dir()` function:

### Step-by-Step Resolution

1. **Cache check**: If the app was previously resolved (or previously failed), return the cached result
2. **Space check**: If the name contains spaces, return an error
3. **Search**: Run `find` across all valid search directories looking for a directory named exactly `n8n`
4. **Validate**: For each match, check that it contains a Compose file (or, for `update`/`list` with update mode, an `update*.sh` script)
5. **Result**:
   - **Exactly 1 match**: Cache and return the path
   - **Multiple matches**: Error - "Multiple matching apps found for 'n8n'" with all paths listed
   - **No matches**: Return empty (subsequent code prints "App 'n8n' not found")

### Caching

Results are cached in a Bash associative array (`APP_DIR_CACHE`) for the duration of the script run. Cache entries include:

- Valid paths for found apps
- `NOT_FOUND` for apps that weren't found
- `DUPLICATE:<paths>` for apps with multiple matches

This means if you reference the same app name multiple times (e.g., in `status` which resolves apps for both container lookup and directory resolution), the filesystem is only searched once.

---

## Duplicate Name Handling

If the same directory name exists under different search roots (or at different depths), DAM treats this as an error:

```
[ERROR] Multiple matching apps found for 'myapp':
  - /opt/stacks/myapp
  - /home/user/apps/myapp
```

There is **no precedence rule** between search roots. DAM does not prefer one search directory over another - it requires unique names which is also recommended in general by Docker.

### Resolution

To fix duplicate names:
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
- If a Compose file sets `name:` explicitly, the Compose project name may differ from the directory name
- DAM's `status` and `get` commands use the `com.docker.compose.project` label to match containers, which reflects the actual Compose project name

### Edge Case: `name:` Override in Compose File

If a `compose.yaml` contains:
```yaml
name: custom-project-name
```

Then:
- DAM will still discover and reference the app by its **directory name**
- Docker Compose will use `custom-project-name` as the project name
- DAM's `status` and `get` commands may **not** match the containers correctly, because they filter by the directory name, not the Compose project name

This is a known limitation. See [Limitations](limitations.md).

---

## Diagram

```
SEARCH_DIRS: ["/opt/stacks", "/home/user/apps"]
EXCLUDE_DIRS: ["recovered", "unused"]

/opt/stacks/
├── traefik/             ← App "traefik" (has compose.yaml)
│   └── compose.yaml
├── n8n/                 ← App "n8n" (has docker-compose.yml)
│   ├── docker-compose.yml
│   └── .env
├── recovered/           ← EXCLUDED (name in EXCLUDE_DIRS)
│   └── old-app/
│       └── compose.yaml
└── my-tools/            ← NOT an app (no compose file)
    └── scripts/

/home/user/apps/
├── homarr/              ← App "homarr" (has compose.yaml + update script)
│   ├── compose.yaml
│   └── update-homarr.sh
└── custom-builder/      ← App "custom-builder" (update-only, no compose file)
    └── update.sh

Discovery Result:
  traefik  → /opt/stacks/traefik
  n8n      → /opt/stacks/n8n
  homarr   → /home/user/apps/homarr
  custom-builder → /home/user/apps/custom-builder  (update mode only)
```
