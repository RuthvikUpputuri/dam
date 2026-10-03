# Command Reference

This page is the command map for DAM. It describes the parsing and dispatch behavior implemented by `dam.sh`; command-specific pages contain the complete operational details.

## Invocation Forms

DAM can be called in three ways:

```bash
# Custom-prefix command installation('dkr' is default command name).
dkr update <app-name>

# Direct script invocation.
./dam.sh update <app-name>

# Raw-command installation, where the symlink name supplies the action.
update <app-name>
```

When the script is invoked through a symlink named after a supported action, it prepends that action internally. For example, `frec <app-name>` is parsed as `force-recreate <app-name>`.

Most operational commands require all of the following before DAM processes apps:

- Bash 4.4 or later
- the `docker` command
- a reachable Docker daemon for the current user
- either `docker compose` or legacy `docker-compose`

DAM prefers `docker compose` and falls back to `docker-compose`. It manages one Compose project per directory; it is not a Swarm or Kubernetes manager.

## Application Selection

The standard selector is used by `start`, `stop`, `restart`, `recreate`, `force-recreate`, `delete`, `pause`, `unpause`, `update`, `status`, `logs`, `debug`, `list`, and `get`.

| Pattern | Meaning |
| :-- | :-- |
| `<cmd> <action> app1 [using files...]` | One app directory |
| `<cmd> <action> app1 app2 [using files...]` | Multiple app directories, processed sequentially |
| `<cmd> <action> all [using files...]` | Every discovered app eligible for that action |
| `<cmd> <action> all except app1 app2 [using files...]` | All eligible apps other than the named apps |

App names are exact directory basenames and cannot contain whitespace. DAM searches `SEARCH_DIRS` to `MAX_SEARCH_DEPTH` (default `5`), skips configured `EXCLUDE_DIRS`, and recognizes an app when it contains a standard Compose filename or, for update discovery, an `update*.sh` file. A name resolving to multiple directories is an error.

`all` must be the first selection token and `except` must immediately follow `all`. DAM validates each requested exclusion. An explicitly selected excluded app is skipped by normal lifecycle processing. `get` is special: it directly queries containers and does not use the lifecycle skip path.

Every non-`get` lifecycle command prints a per-app section and a final summary of successful, failed, and skipped apps. DAM continues after individual app failures, then exits nonzero if any app failed.

## Lifecycle Actions

| Action | Compose command or behavior | Details |
| :-- | :-- | :-- |
| `start` | `up -d` | Creates containers when needed; it is not Compose's `start` subcommand. |
| `stop` | `stop` | Stops project containers without removing them. |
| `restart` | `restart` | Restarts existing containers in place. |
| `recreate` | `down --remove-orphans`, then `up -d` | Gracefully replaces the whole stack. |
| `force-recreate`, `frec` | `down --remove-orphans -t 0`, then `up -d --force-recreate` | Replaces the whole stack with zero shutdown timeout. |
| `pause` | `pause` | Pauses project containers. |
| `unpause` | `unpause` | Resumes paused project containers. |
| `delete` | `down --remove-orphans` plus optional flags | Removes a project and then runs safe dangling-image cleanup. |
| `update` | Pull, build, optionally recreate | Uses a custom `update*.sh` when found and permitted; otherwise preserves stopped state. |

### Default Compose Files

Each Compose action executes inside the resolved application directory. By default, Docker Compose natively searches for a primary file to execute. Whenever DAM refers to falling back to the "default file", it means relying on this native Docker Compose behavior, which searches in this strict priority order:

1. `compose.yaml`
2. `compose.yml`
3. `docker-compose.yaml`
4. `docker-compose.yml`

You can explicitly override this default behavior by appending `using <file1> <file2>...` to the command.

### The `using` Modifier

The `using` modifier explicitly merges provided files in order by dynamically appending `-f <file1> -f <file2>...` flags to the underlying `docker compose` command. 

DAM employs an intelligent shorthand resolution algorithm for every file requested via `using`. For each `<file>`, DAM searches the app directory, stopping at the first match it finds. The precedence order is:

1. **Exact match**: `<file>`
2. **With `.yaml` extension**:
   - `<file>.yaml`
   - `compose.<file>.yaml`
   - `docker-compose.<file>.yaml`
3. **With `.yml` extension**:
   - `<file>.yml`
   - `compose.<file>.yml`
   - `docker-compose.<file>.yml`

> [!NOTE]
> Because the bare filename without a prefix takes precedence for a given extension, if an app has both `<name>.yml` and `compose.<name>.yml` and you specify `using <name>`, **`<name>.yml` will be selected**. To target the prefixed file, you must be explicit (e.g., `using compose.<name>`).

If **at least one** custom file is matched using this logic, DAM strictly uses the found files and emits a warning for any requested file that was not found for that app. If **none** of the requested custom files can be resolved in an app, DAM will fall back to the default file for that app. At the very end of the run, DAM outputs a global summary listing any file shorthands that were not matched in *any* processed app, as well as a list of specific apps that were missing partially matched files.

Read the dedicated pages for [start](start.md), [stop](stop.md), [restart](restart.md), [recreate](recreate.md), [force-recreate](force-recreate.md), [pause](pause.md), [unpause](unpause.md), [delete](delete.md), and [update](update.md).

## Information and Output Actions

| Action | Purpose | Important behavior |
| :-- | :-- | :-- |
| `status` | Multi-project container state and one-shot resource usage | Uses Compose project labels with `docker ps -a`, then `docker stats --no-stream`. |
| `list` | Application inventory or selected-app details | No arguments perform a fast global inventory scan; `list all` is a targeted query and omits excluded apps. |
| `get` | Scriptable container metadata | Requires one resource such as `cid`, `iid`, `vol`, `mnt`, `net`, `port`, `state`, `health`, or `info`. Supports `app:service` and `full` IDs. |
| `logs` | Project-wide Compose logs | Translates human-friendly keywords such as `last 100`, `live`, `since 30m`, and `time`. Live logs are blocked for `all`. |
| `debug` | Placeholder | Prints a TODO per resolvable app; no diagnostics run yet. |

Use [status](status.md), [list](list.md), [get](get.md), [logs](logs.md), and [debug](debug.md) for exact output and parsing semantics.

## Cleanup and Destructive Modes

```bash
<cmd> cleanup [net] [buildx] [vol] [img] [-y]
<cmd> cleanup all [-y]
<cmd> delete <selection> [-y] [with vol|img|net|buildx|all ...]
```

`cleanup` is an existing convenience for a small set of common, host-wide prune operations; it is not app-scoped. It always handles dangling images and can additionally prune unused networks, volumes, build cache, or all unused images. Use Docker's native CLI for specialized maintenance or options DAM does not expose. `cleanup` is separate from project deletion and has its own prompts. `all` cannot be combined with a specific cleanup target.

`delete all` requires the exact interactive answer `yes` unless `-y` or `--yes` is supplied. The same flag bypasses cleanup's volume, network, and full-image confirmations. In non-interactive environments, destructive bulk operations requiring a prompt fail unless `-y` is present.

`with` belongs only to `delete`, and `-y` must appear before its `with` clause. `with vol` and `with img` are project-scoped Compose flags; they do not trigger host-wide pruning. See [cleanup](cleanup.md), [delete](delete.md), and [Safety & Security](safety.md).

## System Commands

The following commands require `sudo` because they modify `/etc` or `/usr/local/bin`:

| Command | Behavior |
| :-- | :-- |
| `install` | Runs the interactive setup and creates the core and command symlinks. |
| `install refresh` | Rebuilds managed command symlinks non-interactively from the existing configuration. |
| `config` | Reruns the configuration wizard and updates command symlinks. |
| `self-update` | Downloads the HTTPS `UPDATE_URL`, validates basic script syntax and optional checksum, replaces the installed binary, then refreshes links. |
| `uninstall` | Removes DAM-managed command symlinks, the installed binary, and the configuration file. It does not remove Docker apps. |

See [setup.md](setup.md), [config.md](config.md), and [self-update.md](self-update.md) for the system-management workflow.

## Help and Unknown Commands

`help`, `-h`, and `--help` print usage and the current Compose-based app list. A call with no action prints the same usage but exits with an error status. DAM also prints usage after an unknown action or invalid selection.

The help text is a useful quick reference, but the individual command pages are the authoritative explanation of confirmation rules, cleanup scope, and edge cases.
