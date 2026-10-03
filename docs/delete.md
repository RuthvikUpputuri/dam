# Delete Semantics

`delete` removes a discovered Docker Compose stack. Its default is intentionally conservative: containers and project networks are removed, while project volumes and images are retained.

## Syntax

```bash
<cmd> delete <app-selection> [-y|--yes] [with <modes...>]
```

Valid modes after `with` are `vol`, `img`, `net`, `buildx`, and `all`.

```bash
dkr delete <app1>
dkr delete <app1> with vol
dkr delete <app1> with img
dkr delete <app1> with vol img
dkr delete all -y with all
dkr delete all except <proxy-app> -y with buildx
```

Place `-y` or `--yes` before `with`. Once DAM has read `with`, every following argument is interpreted as a cleanup mode, so `delete all with vol -y` is rejected as an unknown cleanup argument.

## App Selection and Confirmation

`delete` accepts one or more app directory names, `all`, or `all except app1 app2`. Names in `EXCLUDE_DIRS` are never operated on. A requested app that is missing or has multiple matching directories is counted as a failure; DAM continues with the other selected apps and reports a summary.

`delete all`, including `delete all except ...`, requires confirmation. DAM lists the selected apps and requires the exact response `yes`; `y` alone cancels the operation. `-y` or `--yes` skips that confirmation. If standard input is not a terminal, `delete all` fails unless the flag is present.

There is no additional interactive confirmation for the `with` modes. Treat them as explicit consent to remove the selected project's data or images.

## Per-App Compose Commands

DAM enters the app directory, detects a supported Compose file, then uses `docker compose` when available or falls back to `docker-compose`. The base command is always:

```bash
docker compose [-f <file>...] down --remove-orphans
```

`--remove-orphans` removes containers from services no longer defined by the current Compose file. DAM then displays `docker compose ps`; status-display failure is ignored after a successful `down`.

| `with` mode | Additional Compose arguments | Effect |
| :-- | :-- | :-- |
| none | none | Removes project containers and networks; preserves volumes and images |
| `vol` | `-v` | Removes named and anonymous volumes associated with the project |
| `img` | `--rmi all` | Removes service images for the project |
| `vol img` | `-v --rmi all` | Removes project volumes and service images |
| `all` | `-v --rmi all` | Same project-scoped effect as `vol img` |
| `net` | none | Accepted, but adds no flag because `compose down` already removes project networks |
| `buildx` | none | Adds no Compose flag; it affects post-action host cleanup only |

`with all` does not mean `cleanup all`. It removes the selected project's volumes and images through Compose; it does not request host-wide network, volume, or full-image pruning.

## Data and Scope

Default deletion removes all containers in the project, including stopped containers, and the project networks that Compose owns. It does not delete the application directory, Compose file, bind-mounted host data, external networks, named volumes by default, or downloaded images by default.

`with vol` is project-scoped because Compose receives `-v`. It is materially different from [cleanup.md](cleanup.md)'s `cleanup vol`, which can prune unused volumes across the Docker host. Bind-mounted paths are host files and are not removed by either `docker compose down -v` or DAM.

## Post-Delete Cleanup

After DAM has processed every selected app and printed the summary, it always runs dangling-image cleanup across the host:

```bash
docker image prune -f
```

If `with buildx` was selected, DAM additionally performs its build-cache cleanup. The global cache cleanup happens after processing, even when one or more selected apps failed.

For safety, DAM filters `vol`, `net`, `img`, and `all` out of this post-delete cleanup. Consequently, `delete app with vol` never becomes a global `docker volume prune`, and `delete app with img` never becomes a global `docker image prune -a`.

## Examples

```bash
# Remove a stack but retain its database volume for a later restore.
dkr delete <app3>

# Fully remove one disposable test stack, including its Compose volumes and images.
dkr delete <test-app> with all

# Remove all targetable stacks non-interactively, retaining project data.
dkr delete all -y

# Remove stacks and clear unused build cache afterwards.
dkr delete all except <proxy-app> -y with buildx
```

Use [Safety & Security](safety.md) before deleting data-bearing applications.

