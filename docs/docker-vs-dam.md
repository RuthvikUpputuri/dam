# DAM vs Docker / Docker Compose

This document provides a detailed, accurate comparison between DAM commands and their native Docker/Docker Compose equivalents. All behavior is derived from the DAM source code and verified against official Docker documentation.

---

## Key Concepts

Before comparing commands, it's essential to understand the conceptual differences:

### Native Docker/Compose Workflow
- You must `cd` into the directory containing your `compose.yaml`
- You must know the project name, service names, or container names/IDs
- Each `docker compose` command operates on the **current directory's** Compose file
- There is no built-in way to operate on multiple Compose projects at once

### DAM Workflow
- DAM **discovers** app directories automatically based on configured search paths
- You reference apps by their **directory name** (the human-friendly app name)
- DAM resolves the directory, finds the Compose file, changes to the directory, and runs the appropriate `docker compose` command
- DAM supports **bulk operations** across multiple Compose projects

### What DAM Adds Over Native Commands
1. **Application discovery** - finds apps by name instead of requiring paths
2. **Directory resolution** - automatically `cd`s to the correct directory
3. **Multi-project operations** - `all`, `all except`, multiple app names
4. **Safety checks** - confirmation prompts for destructive operations
5. **Structured output** - per-app sections, success/failure counters, summary
6. **Post-operation cleanup** - automatic dangling image cleanup after `delete`/`update`
7. **Custom update scripts** - app-specific update logic via `update*.sh`
8. **Running state preservation** - `update` skips container startup for stopped apps
9. **Global commands** - run from anywhere, no `cd` needed
10. **Custom Compose files** - `using files...` merges explicit Compose files directly by appending `-f` flags. An all-missing file set fails `stop`, `recreate`, `force-recreate`, and `delete`; other Compose actions use their default Compose file.

---

## Command Comparison Table

| DAM Command | Native Docker Equivalent | Native Compose Equivalent | Actually Equivalent? | What DAM Adds | Scope |
| :---------- | :----------------------- | :------------------------ | :------------------- | :------------ | :---- |
| `start <app>` | None | `docker compose up -d` | **Yes** (uses `up -d`, not `start`) | App discovery, directory resolution and multi app support at once | Project |
| `stop <app>` | None | `docker compose stop` | **Yes** | App discovery, directory resolution and multi app support at once | Project |
| `kill <app>` | None | `docker compose kill` | **Yes** | Force stops immediately (SIGKILL) with app discovery | Project |
| `restart <app>` | None | `docker compose restart` | **Yes** | App discovery, directory resolution and multi app support at once | Project |
| `recreate <app>` | None | `docker compose down --remove-orphans` + `docker compose up -d` | **No direct equivalent** - this is two commands | Orchestration, orphan removal and multi app support at once | Project |
| `force-recreate <app>` / `frec` | None | `docker compose down --remove-orphans -t 0` + `docker compose up -d --force-recreate` | **No direct equivalent** | Immediate kill + force-recreate and multi app support at once | Project |
| `pause <app>` | `docker pause <container>` | `docker compose pause` | **Yes** (uses Compose pause) | App discovery, directory resolution and multi app support at once | Project |
| `unpause <app>` | `docker unpause <container>` | `docker compose unpause` | **Yes** (uses Compose unpause) | App discovery, directory resolution and multi app support at once | Project |
| `delete <app>` | None | `docker compose down --remove-orphans` | **Partially** - DAM adds post-delete cleanup | App discovery, safety, post-cleanup and multi app support at once | Project + Host |
| `update <app>` | None | `docker compose pull` + `docker compose build --pull` + `docker compose up -d` | **No direct equivalent** | Custom scripts, state preservation, cleanup and multi app support at once | Project + Host |
| `status <app>` | `docker ps` + `docker stats` | `docker compose ps` | **No** - DAM combines ps + stats across projects | Multi-project view, resource usage and multi app support at once | Multi-Project |
| `list` | None | None | **No equivalent** | Full inventory with discovery | Discovery |
| `get <app> <resource>` | `docker inspect` | None | **No equivalent** | App-based queries, structured output and multi app support at once | Containers |
| `logs <app>` | `docker logs <container>` | `docker compose logs` | **Partially** - DAM adds keyword syntax | Keyword arguments, head piping and multi app support at once | Project |
| `cleanup` | `docker image prune -f` | None | **Yes** (default mode) | Structured output, mode selection | Host |
| `cleanup all` | `docker system prune -a --volumes -f` | None | **Similar** but not identical - DAM prunes each resource type individually with separate confirmations | Per-resource confirmations | Host |

---

## Detailed Comparisons

### `start` vs `docker compose up -d` vs `docker compose start`

**Critical distinction:** DAM's `start` command runs `docker compose up -d`, which is **not** the same as `docker compose start`.

| Aspect | `docker compose start` | `docker compose up -d` | DAM `start` |
| :----- | :--------------------- | :--------------------- | :---------- |
| Creates containers | No | Yes | Yes (uses `up -d`) |
| Applies config changes | No | Yes | Yes |
| Applies image updates | No | Yes | Yes |
| Requires existing containers | Yes | No | No |

**Why this matters:** If you've edited your `compose.yaml` or pulled a new image, `docker compose start` won't apply those changes - it starts the existing containers exactly as they were. DAM's `start` (using `up -d`) will detect changes and recreate containers as needed.

### `stop` vs `docker compose stop`

These are **equivalent**. Both stop running containers without removing them. Containers can be resumed with `start` (which uses `up -d` in DAM).

### `kill` vs `docker compose kill`

These are **equivalent**. Both force stop containers instantly via `SIGKILL` without waiting. Useful for frozen apps.

### `restart` vs `docker compose restart`

These are **equivalent**. Both cycle containers in-place without applying configuration changes.

### `recreate` vs Manual `down` + `up`

DAM's `recreate` is a two-step operation that has no single native equivalent:

```
# DAM does:
docker compose down --remove-orphans
docker compose up -d

# The closest native equivalent requires two manual commands:
cd /path/to/app && docker compose down --remove-orphans && docker compose up -d
```

**DAM adds:** `--remove-orphans` is always included, which removes containers for services no longer defined in the Compose file.

### `force-recreate` vs Manual Aggressive Recreate

```
# DAM does:
docker compose down --remove-orphans -t 0
docker compose up -d --force-recreate

# Native equivalent:
cd /path/to/app && docker compose down --remove-orphans -t 0 && docker compose up -d --force-recreate
```

**Key differences from `recreate`:**
- `-t 0`: no graceful shutdown timeout (immediate SIGKILL)
- `--force-recreate`: forces recreation even when config/images haven't changed

### `delete` vs `docker compose down`

DAM's `delete` wraps `docker compose down` but adds:

| DAM Flag | Docker Compose Equivalent | Effect |
| :------- | :------------------------ | :----- |
| *(default)* | `docker compose down --remove-orphans` | Removes containers, networks |
| `with vol` | `docker compose down --remove-orphans -v` | Also removes named + anonymous volumes |
| `with img` | `docker compose down --remove-orphans --rmi all` | Also removes images |
| `with all` | `docker compose down --remove-orphans -v --rmi all` | Removes everything |

**After the `down` command**, DAM also runs a **global** dangling image cleanup (`docker image prune -f`).

**Important:** `delete with vol` uses `docker compose down -v`, which removes only the **project's** volumes. This is completely different from `cleanup vol`, which runs `docker volume prune` and removes **all** unused volumes system-wide.

### `update` vs Manual Pull + Recreate

There is **no single native Docker command** that does what DAM's `update` does. The closest manual workflow is:

```bash
cd /path/to/app
docker compose pull --ignore-buildable
docker compose build --pull
docker compose up -d
```

**DAM adds:**
1. **Custom script support** - runs `update*.sh` if present and permitted
2. **Running state preservation** - if the app was stopped, DAM pulls/builds but does **not** start the containers
3. **Graceful pull fallback** - tries `--ignore-buildable`, falls back to `--ignore-pull-failures` for older Compose versions
4. **Post-update cleanup** - prunes dangling images after all apps are processed

### `status` vs `docker compose ps` / `docker ps`

DAM's `status` combines information from multiple sources:

| What | Source |
| :--- | :----- |
| Container table | `docker ps -a` filtered by compose project labels |
| Resource usage | `docker stats --no-stream` |

**Native `docker compose ps`** only shows containers for the current project directory. DAM's `status` can show containers across **multiple projects** at once.

### `cleanup` vs Docker Prune Commands

| DAM Cleanup Mode | Docker Equivalent | Difference |
| :--------------- | :---------------- | :--------- |
| `cleanup` (default) | `docker image prune -f` | Equivalent - removes only dangling (untagged) images |
| `cleanup img` | `docker image prune -a -f` | Equivalent - removes all unused images |
| `cleanup net` | `docker network prune -f` | Equivalent - removes unused networks |
| `cleanup vol` | `docker volume prune -a -f` | Equivalent - removes unused volumes |
| `cleanup buildx` | `docker buildx prune -f` | Equivalent - removes build cache |
| `cleanup all` | All of the above | Similar to `docker system prune -a --volumes -f`, but executed as separate commands with individual confirmations |

**Key difference:** `docker system prune` combines everything into one command with one confirmation. DAM's `cleanup all` asks for separate confirmations for volumes, images, and networks (unless `-y` is passed).

---

## What DAM Does NOT Replace

DAM is specifically designed for **lifecycle management of Docker *Compose* projects**. The following operations are outside DAM's scope and should continue to use native Docker commands:

| Operation | Use Native Command |
| :-------- | :----------------- |
| Execute commands inside containers | `docker exec -it <container> <command>` |
| View container logs (advanced filtering) | `docker logs <container>` |
| Inspect container/image details | `docker inspect <id>` |
| Build images directly | `docker build` / `docker buildx build` |
| Manage Docker registries | `docker login` / `docker push` / `docker pull` |
| Manage Docker Swarm | `docker swarm` / `docker service` / `docker stack` |
| Manage Kubernetes | `kubectl` |
| Configure Docker daemon | `dockerd` / `/etc/docker/daemon.json` |
| Create/manage networks manually | `docker network create` |
| Create/manage volumes manually | `docker volume create` |
| Low-level container operations | `docker attach`, `docker commit`, `docker export` |
| Copy files to/from containers | `docker cp` |

---

## Container Name vs Service Name vs Project Name

This is a common source of confusion that DAM helps abstract away:

| Concept | What It Is | Example |
| :------ | :--------- | :------ |
| **Project name** | Derived from the directory name (by default). Identifies the Compose project. | `<app-name>` |
| **Service name** | Defined in `compose.yaml` under `services:`. One project can have multiple services. | `<app-name>`, `postgres` |
| **Container name** | Auto-generated by Compose as `<project>-<service>-<N>` or set via `container_name:` in the Compose file. | `<app-name>-<app-name>-1`, `<app-name>-postgres-1` |

When you run `dkr start <app-name>`, you're specifying the **directory name** (which maps to the project name). DAM resolves this to a directory, finds the Compose file, and runs `docker compose up -d` - you never need to know the service names or container names.

For the `get` command, DAM supports targeting specific services with `app:service` syntax:

```bash
dkr get <app-name>:postgres vol    # Get volumes for the postgres service in the <app-name> project
dkr get <app-name> vol              # Get volumes for ALL services in the <app-name> project
```

---

## References

- [Docker Compose CLI reference](https://docs.docker.com/reference/cli/docker/compose/)
- [docker compose up](https://docs.docker.com/reference/cli/docker/compose/up/)
- [docker compose down](https://docs.docker.com/reference/cli/docker/compose/down/)
- [docker compose start](https://docs.docker.com/reference/cli/docker/compose/start/)
- [docker compose stop](https://docs.docker.com/reference/cli/docker/compose/stop/)
- [docker compose restart](https://docs.docker.com/reference/cli/docker/compose/restart/)
- [docker compose pull](https://docs.docker.com/reference/cli/docker/compose/pull/)
- [docker compose build](https://docs.docker.com/reference/cli/docker/compose/build/)
- [docker image prune](https://docs.docker.com/reference/cli/docker/image/prune/)
- [docker volume prune](https://docs.docker.com/reference/cli/docker/volume/prune/)
- [docker network prune](https://docs.docker.com/reference/cli/docker/network/prune/)
