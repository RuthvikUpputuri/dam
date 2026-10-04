# Force-Recreate Semantics

`force-recreate` tears down a Compose project with no shutdown grace period, then creates fresh containers even when Compose sees no configuration or image change. `frec` is an exact alias for the command.

## Syntax

```bash
<cmd> force-recreate <app>
<cmd> force-recreate <app1> <app2>
<cmd> force-recreate all
<cmd> force-recreate all except <app1> <app2>

<cmd> frec <same-selection>
```

App names are directory names, not Compose service or container names. DAM resolves them from its configured search directories. The `all` selector includes discovered Compose applications except names configured in `EXCLUDE_DIRS`; `all except` validates every excluded name before doing work.

## Per-App Flow

For each selected application, DAM finds the first recognized Compose filename in this order:

1. `compose.yaml`
2. `compose.yml`
3. `docker-compose.yaml`
4. `docker-compose.yml`

It changes into that directory and runs the available Compose implementation, preferring `docker compose` and falling back to `docker-compose`:

```bash
docker compose [-f <file>...] down --remove-orphans -t 0
docker compose [-f <file>...] up -d --force-recreate
docker compose ps
```

The final status command is informational. A failure to print status does not change an otherwise successful teardown and startup result.

### Step 1: Immediate Teardown

```bash
docker compose [-f <file>...] down --remove-orphans -t 0
```

`-t 0` requests a zero-second shutdown timeout. This is the key difference from [recreate.md](recreate.md): services receive no normal grace period to finish work before Compose removes them. Use it only when a graceful `recreate` cannot stop the stack or when immediate replacement is acceptable.

`--remove-orphans` also removes containers belonging to services that are no longer present in the current Compose definition.

By default, Compose project volumes and images are preserved. The command does not run DAM's global image, network, volume, or build-cache cleanup.

### Step 2: Forced Creation

```bash
docker compose [-f <file>...] up -d --force-recreate
```

`--force-recreate` tells Compose to replace service containers regardless of whether its change detection believes replacement is necessary. The stack is started detached using the current Compose configuration; Compose creates the project networks and containers again as needed.

### Step 3: Status Display

```bash
docker compose ps
```

DAM displays the resulting service state and records the app as successful only when both the teardown and startup commands succeed.

## Explicit Compose Files

Append `using <file1> <file2>...` to select Compose files explicitly. If none of the requested files resolve for an app, `force-recreate` fails that app instead of tearing down and rebuilding the stack described by its default Compose file. If one or more resolve, DAM uses only the resolved files and warns about any misses.

## Selection, Failures, and Summary

DAM processes selected apps sequentially. An app that cannot be found, resolves to more than one directory, is excluded, or fails one of the Compose operations is recorded in the final summary. A failure for one app does not prevent later selected apps from being attempted. DAM exits nonzero if any app failed.

Excluded applications are skipped, even when explicitly named. `force-recreate` requires a reachable Docker daemon and either supported Compose implementation before it starts selection processing.

No confirmation is required for a single app or for `all`; the operation is disruptive but not treated as a data-removal command by DAM. Take application-level backups and use [recreate.md](recreate.md) when a normal shutdown is sufficient.

## Examples

```bash
# Force replacement of one hung stack.
dkr force-recreate immich

# The compact alias has identical behavior.
dkr frec <app-name>

# Replace all targetable stacks except infrastructure that should remain up.
dkr force-recreate all except <proxy-app> portainer
```

## What It Does Not Do

- It does not pull newer images or rebuild local images. Use [update.md](update.md) for that workflow.
- It does not remove named volumes or service images.
- It does not target one service within a project; every Compose service in the application directory is affected.
- It does not support Swarm or Kubernetes.
