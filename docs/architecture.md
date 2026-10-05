# Architecture & Internal Design

This document describes DAM's internal architecture, execution flow, and design patterns.

---

## Overview

DAM is a single Bash script (`dam.sh`, ~2064 lines, version 1.1.0) with no external dependencies beyond Bash 4.4+, Docker, and Docker Compose. It uses:

- **Bash associative arrays** for caching
- **`find`** for directory discovery
- **`pushd`/`popd`** for working directory management
- **Docker CLI** and **Docker Compose CLI** for all container operations

---

## Execution Flow

```
┌─────────────────────────────────────────────────────────┐
│                    User invocation                       │
│  e.g., "dkr start <app-name>" or "start <app-name>" or "./dam.sh ..." │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│              1. Script Initialization                     │
│  • set -uo pipefail                                       │
│  • Bash version check (≥ 4.4)                             │
│  • Load config from /etc/docker-app-manager.conf          │
│    (or use fallback defaults)                             │
│  • Build FIND_PRUNE_ARGS from EXCLUDE_DIRS                │
│  • Initialize APP_DIR_CACHE                               │
│  • Initialize MAX_SEARCH_DEPTH                            │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│              2. Multicall Detection                       │
│  • Check if script was called as "start", "stop", etc.   │
│    via basename "$0"                                      │
│  • If so, prepend the action to "$@"                      │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│              3. Administrative Command Check               │
│  • If $1 is "install", "config", "uninstall",            │
│    or "self-update":                                      │
│    → Verify EUID == 0 (require sudo)                      │
│    → Execute administrative handler                       │
│    → Exit                                                 │
└──────────────────────────┬──────────────────────────────┘
                           │ (not admin)
                           ▼
┌──────────────────────────────────────────────────────────┐
│              4. Header & Help Check                       │
│  • Print header (unless "get" command)                    │
│  • Check for --help / -h / help / no-args → usage()      │
│  • Extract ACTION from $1                                 │
│  • Normalize "frec" → "force-recreate"                    │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│              5. Docker Readiness Check                     │
│  • docker_ready():                                        │
│    1. command -v docker                                   │
│    2. docker info                                         │
│    3. docker compose version OR docker-compose version    │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│              6. Command Dispatch                          │
│                                                           │
│  case "$ACTION" in                                        │
│    list (no args) → inventory_apps_table()                │
│    cleanup        → cleanup_dangling_resources()          │
│    everything else → parse_target_apps() then:            │
│      list         → print_app_level_details_table()       │
│      get          → get resource handler                  │
│      status       → status handler                        │
│      others       → per-app processing loop               │
│  esac                                                     │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│              7. App Selection & Parsing                    │
│  parse_target_apps():                                     │
│  • Parse -y/--yes, "with" modifiers, log/get args        │
│  • Handle "all" / "all except" / specific apps           │
│  • Validate app existence for "except" targets            │
│  • Confirmation prompt for "delete all"                   │
│  • Populate APPS_TO_PROCESS array                         │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│              8. Per-App Processing Loop                    │
│  for app in APPS_TO_PROCESS:                              │
│    process_app(ACTION, app):                              │
│      • find_app_dir(app) → resolve directory              │
│      • Check excluded                                     │
│      • Dispatch to handler:                               │
│        - update → run_update_action_for_app()             │
│        - logs   → run_logs_action_for_app()               │
│        - debug  → run_debug_action_for_app()              │
│        - others → run_compose_action_for_app()            │
│      • Track SUCCESS/FAILED/SKIPPED counters              │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│              9. Summary & Cleanup                         │
│  • print_summary(ACTION)                                  │
│  • If delete/update: cleanup_dangling_resources()         │
│  • Exit with appropriate code                             │
└─────────────────────────────────────────────────────────┘
```

---

## Key Functions

### Configuration & Setup

| Function | Lines | Purpose |
| :------- | :---- | :------ |
| *(top-level config loading)* | 65-103 | Loads config file or sets fallback defaults |

### App Discovery

| Function | Lines | Purpose |
| :------- | :---- | :------ |
| `find_app_dir()` | 107-177 | Resolves an app name to a directory path. Uses caching. |
| `has_compose_files()` | 280-286 | Checks if a directory contains any compose file |
| `get_app_compose_file()` | 288-303 | Returns the highest-priority compose filename |
| `resolve_compose_files()` | 316-338 | Resolves `using` files into `-f` arguments; rejects an all-missing file set only for `stop`, `kill`, `recreate`, `force-recreate`, and `delete` |
| `has_update_files()` | 305-312 | Checks if a directory has compose files OR update scripts |
| `get_all_apps()` | 495-524 | Returns all discovered app names (for `all` selector) |
| `is_excluded()` | 241-247 | Checks if a folder name is in EXCLUDE_DIRS |

### Docker Abstraction

| Function | Lines | Purpose |
| :------- | :---- | :------ |
| `dc()` | 249-258 | Wrapper: tries `docker compose`, falls back to `docker-compose` |
| `docker_ready()` | 260-278 | Validates Docker and Compose are available and running |

### Command Handlers

| Function | Lines | Purpose |
| :------- | :---- | :------ |
| `run_compose_action_for_app()` | 752-864 | Handles start, stop, kill, restart, recreate, force-recreate, delete, pause, unpause |
| `run_update_action_for_app()` | 866-999 | Handles update (custom script or compose pull+build+up) |
| `run_logs_action_for_app()` | 1001-1075 | Handles log viewing with keyword parsing |
| `run_debug_action_for_app()` | 1077-1081 | Placeholder for future debug feature |
| `process_app()` | 1083-1152 | Entry point for per-app processing; dispatches to appropriate handler |
| `cleanup_dangling_resources()` | 587-750 | Handles all cleanup operations (images, networks, volumes, build cache) |

### Argument Parsing

| Function | Lines | Purpose |
| :------- | :---- | :------ |
| `parse_target_apps()` | 1154-1301 | Parses app selection, modifiers, and populates APPS_TO_PROCESS |

### Display & Output

| Function | Lines | Purpose |
| :------- | :---- | :------ |
| `print_header()` | 198-204 | Prints the DAM banner |
| `print_section()` | 206-213 | Prints per-app section header |
| `print_summary()` | 215-239 | Prints the final summary with counters |
| `usage()` | 526-585 | Prints help/usage information |
| `print_apps_in_columns()` | 314-336 | Formats app names in 3-column layout |
| `list_available_apps()` | 338-407 | Lists apps organized by search directory |
| `inventory_apps_table()` | 409-464 | Full inventory table with status |
| `print_app_level_details_table()` | 466-493 | Detailed table for specific apps |

### Administrative

| Function/Block | Lines | Purpose |
| :------------- | :---- | :------ |
| Install handler | 1438-1709 | Interactive wizard + file operations |
| Self-update handler | 1349-1401 | Download, validate, install |
| Uninstall handler | 1403-1435 | Remove all installed files |

---

## Error Handling

### Script-Level

- `set -uo pipefail` is set at the top of the script:
  - `-u`: undefined variables cause an error
  - `-o pipefail`: pipeline failures propagate
  - Note: `set -e` (exit on error) is **not** used - errors are handled explicitly

### Per-App Error Handling

- Each app operation is wrapped in a success/failure check
- Failed apps are counted (`FAILED++`) and listed in the summary
- Processing **continues** to the next app even if one fails
- The script exits with code 1 if any app failed

### Docker Errors

- Docker/Compose errors are passed through directly
- DAM adds `[FAIL]` messages but does not suppress Docker's error output
- The `dc` wrapper checks for both `docker compose` and `docker-compose` availability

---

## Working Directory Management

DAM uses `pushd`/`popd` to manage working directories:

```bash
pushd "$dir" > /dev/null || return 1
# ... run docker compose commands ...
popd > /dev/null || true
```

Each app operation changes to the app's directory before running Compose commands, then returns. This ensures Compose picks up the correct `compose.yaml` file.

The `|| true` on `popd` ensures the script doesn't fail if `popd` has an issue (defensive programming).

---

## Multicall Binary Pattern

DAM supports being invoked as different command names (multicall binary pattern):

```bash
COMMAND_NAME="$(basename "$0")"
SUPPORTED_ACTIONS=("start" "stop" "kill" "restart" ...)

if [[ " ${SUPPORTED_ACTIONS[*]} " =~ \ ${COMMAND_NAME}\  ]]; then
    set -- "$COMMAND_NAME" "$@"
fi
```

When installed with raw commands (no prefix), the symlink `start` → `docker-app-manager` means:
- `basename "$0"` returns `start`
- DAM prepends `start` to the argument list
- The rest of the script processes it as if the user typed `dam start ...`

---

## Output Design

DAM uses ANSI color codes for structured, visually clear output:

| Color | Used For |
| :---- | :------- |
| Red (`\033[0;31m`) | Errors, warnings, failed items |
| Green (`\033[0;32m`) | Success, completed items |
| Yellow (`\033[1;33m`) | Warnings, skipped items, confirmations |
| Blue (`\033[0;34m`) | Step indicators (`[1/2]`, `[2/3]`, etc.) |
| Cyan (`\033[0;36m`) | Informational messages, app names |
| Bold (`\033[1m`) | Headers, section titles |

Each app operation is visually separated with a section header:
```
┌─────────────────────────────────────────────────────
│  start: <app-name>
└─────────────────────────────────────────────────────
```

The final summary shows:
```
══════════════════════ SUMMARY ══════════════════════
  Action performed     : start
  Total apps processed : 3
  ✔ Successful         : 2
  ✘ Failed             : 1
  Successful apps: <app-name> <app2>
  Failed apps:     broken-app
═════════════════════════════════════════════════════
```
# Core Conceptual Model

Understanding how DAM (Docker App Manager) interacts with your system and Docker requires understanding a few core concepts. DAM bridges the gap between your host filesystem's organization and Docker's internal resource management.

---

## The Mapping: Human-Facing to Docker

DAM's fundamental philosophy is that **directories equal projects**.

1. **Human-Facing Application Name**: The name you type in the CLI (e.g., `<app-name>`).
2. **Application Directory**: DAM searches its configured `SEARCH_DIRS` for a folder exactly matching this name. (If you explicitly overridden the name via `.env` or `name:`, DAM will match that custom name instead). This directory is treated as the application's home.
3. **Compose File**: DAM looks inside the discovered directory for a standard Docker Compose file (e.g., `docker-compose.yml`, `compose.yaml`).
4. **Docker Compose Project**: When executing commands, DAM sets the application directory as the working directory (`PWD`). Docker Compose then uses the directory's basename as the **Project Name** by default.

```text
User Input: "<app-name>"
       ↓
DAM discovers: /opt/stacks/<app-name>/
       ↓
DAM finds: /opt/stacks/<app-name>/docker-compose.yml
       ↓
DAM executes: docker compose up -d (with /opt/stacks/<app-name>/ as PWD)
       ↓
Docker Compose creates resources labeled with project "<app-name>"
```

---

## Key Distinctions

### Host Filesystem vs Docker-Managed Resources

- **Host Filesystem**: The directories (e.g., `/opt/stacks/<app3>`) where your Compose files and local bind mounts live. DAM's discovery process relies entirely on this.
- **Docker-Managed Resources**: Volumes, networks, images, and containers stored internally by the Docker Daemon. DAM operates on these indirectly through Docker Compose. When you delete an application directory from your filesystem, the Docker-managed resources are **not** automatically deleted unless you run a command like `dam delete <app>` first.

### Container Name vs Service Name vs Project Name

DAM abstracts this distinction, but understanding it is critical when using commands like `get` or `logs`:

| Concept | What It Is | Example |
| :------ | :--------- | :------ |
| **Project Name** | The name of the entire application stack. Derived from the directory name (by default). | `<app-name>` |
| **Service Name** | A logical component of your project defined in `compose.yaml` under `services:`. | `<app-name>`, `postgres`, `redis` |
| **Container Name** | The actual running instance of a service, named by Compose. | `<app-name>-<app-name>-1`, `<app-name>-postgres-1` |

When you use DAM, you always target the **Project Name**. You never need to target individual containers.

### Docker Daemon vs Docker Client vs Docker Compose

- **Docker Daemon**: The background service running on your host that actually builds, runs, and manages your containers. DAM requires the daemon to be running and accessible.
- **Docker Client (`docker`)**: The CLI tool used to interact with the daemon. DAM uses this internally for things like `status`, `get`, and `cleanup`.
- **Docker Compose (`docker compose`)**: A higher-level tool that parses `compose.yaml` files to manage multi-container applications (projects). DAM uses this for all lifecycle commands (`start`, `stop`, `kill`, `recreate`, `update`).

## Further Reading

- [Application Discovery Detailed Flow](application-discovery.md)
- [DAM vs Docker Commands](docker-vs-dam.md)
