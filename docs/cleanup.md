# Cleanup Semantics

The `cleanup` command is an existing convenience for a small set of common prune operations. It removes unused Docker resources from the entire host; it is not limited to application directories discovered by DAM, and it does not operate through Docker Compose. DAM is focused on application-stack lifecycle management, not replacing the Docker CLI. Use native Docker commands for specialized maintenance or options this command does not expose.

## Prerequisites and Syntax

DAM requires a working Docker daemon and either Docker Compose v2 (`docker compose`) or v1 (`docker-compose`) before it runs cleanup, even though cleanup itself uses Docker CLI prune commands.

```bash
<cmd> cleanup [net] [buildx] [vol] [img] [-y]
<cmd> cleanup all [-y]
```

`<cmd>` is your configured command, such as `dkr`, or `./dam.sh` when running the script directly.

`all` is exclusive. DAM rejects `cleanup all vol`, `cleanup all img`, and every other combination of `all` with a specific target. Specific targets can be combined, for example:

```bash
dkr cleanup buildx
dkr cleanup net vol
dkr cleanup img vol buildx -y
dkr cleanup all -y
```

An unknown argument is an error. `-y` and `--yes` are the only flags.

## Resource Modes

Every invocation performs dangling-image handling. Adding a target enables the corresponding extra cleanup; it does not replace the default image step.

| Invocation | Docker work DAM performs | Confirmation |
| :-- | :-- | :-- |
| `cleanup` | Checks for dangling images, then runs `docker image prune -f` when any exist | No |
| `cleanup net` | Default dangling-image cleanup plus `docker network prune -f` | Networks: yes |
| `cleanup vol` | Default dangling-image cleanup plus volume prune | Volumes: yes |
| `cleanup img` | `docker image prune -a -f` instead of dangling-only image prune | Images: yes |
| `cleanup buildx` | Default dangling-image cleanup plus build-cache prune | No |
| `cleanup all` | Full unused-image prune plus network, volume, and build-cache pruning | Images, networks, and volumes: yes |

### Images

Without `img` or `all`, DAM first checks `docker image ls -f dangling=true -q`. If the result is non-empty, it runs:

```bash
docker image prune -f
```

This removes only dangling, untagged image layers. If none are found, DAM reports that there are no dangling images and does not invoke the prune command.

`img` and `all` request a broader host-wide image prune:

```bash
docker image prune -a -f
```

This can remove any unused image, including a pulled image for a currently stopped stack. DAM asks before running it unless `-y` or `--yes` was supplied.

### Networks

`net` and `all` inspect dangling network IDs first, then run:

```bash
docker network prune -f
```

This is a host-wide operation. In particular, an externally managed network can be removed when no container is attached. A stopped stack that expects such a network may need it recreated before it can start again.

### Volumes

`vol` and `all` inspect dangling volumes first. When any exist, DAM attempts:

```bash
docker volume prune -a -f
```

If that command fails, DAM falls back to:

```bash
docker volume prune -f
```

DAM prints an error if both attempts fail. Volume pruning is host-wide, not scoped to DAM-managed applications. An unused volume can contain the only remaining data from a stopped or deleted application, so this mode is intentionally guarded by a confirmation prompt.

### Build Cache

`buildx` and `all` read the total reported by `docker buildx du --verbose`. If the reported total is nonzero, DAM runs:

```bash
docker buildx prune -f
```

If that fails, it tries the older fallback:

```bash
docker builder prune -f
```

If Buildx cannot report a nonzero cache total, DAM reports no dangling build cache rather than trying the fallback prune. Build-cache pruning does not remove containers, project volumes, or images used by containers, but later builds may need to download or rebuild layers.

## Confirmations and Automation

DAM asks separately before pruning unused volumes, all unused images, and unused networks. The exact answer accepted by these prompts is `y` or `yes`, in either case. A declined resource is skipped while other requested resource modes continue.

In a non-interactive environment with no terminal attached, a requested volume, full-image, or network prune fails before its destructive command runs. Use `-y` or `--yes` for intentional automation:

```bash
dkr cleanup all -y
```

`-y` applies to all cleanup confirmation prompts in that invocation. It does not make a failed Docker command succeed.

## Relationship to `delete` and `update`

After every `delete` and `update` run, DAM invokes the same cleanup helper in its default mode, which only removes dangling images. If `delete` was invoked with `with buildx`, DAM also prunes build cache afterwards.

The `with vol`, `with img`, and `with all` modifiers on `delete` affect that Compose project through `docker compose down`; DAM deliberately does not turn them into global volume, network, or full-image prunes. See [delete.md](delete.md) for the project-scoped behavior.

`with` is not accepted by `cleanup` or `update`. Use the standalone command when you actually intend a host-wide prune.

## Scope and Limits

- Cleanup does not discover applications and does not inspect `SEARCH_DIRS`.
- It does not remove running containers.
- Resource ownership is not limited to DAM. Docker resources created by other tools can be eligible for pruning.
- `cleanup all` is similar in intent to a broad `docker system prune`, but DAM executes each resource family separately and preserves its own per-resource confirmations.

For destructive-operation guidance, see [Safety & Security](safety.md).
