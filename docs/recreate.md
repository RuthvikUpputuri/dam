# Recreate Semantics

This document explains exactly how DAM's `recreate` command works, including container teardown, configuration application, and status reporting.

---

## Overview

The `recreate` command performs a clean restart of the entire app stack. Unlike `restart`, which merely bounces existing containers in-place, `recreate` gracefully tears down the application's containers and networks, and then brings them back up from scratch. This guarantees that any changes made to the `compose.yaml` file are fully applied without losing persistent data.

> **Note**: If an app is completely unresponsive or hung and a graceful teardown is insufficient, you can use the aggressive [force-recreate](force-recreate.md) (or `frec`) command instead.

---

## Recreate Flow

When the `recreate` command is executed for an app, DAM follows a consistent, three-step process per app:

### Step 1: Teardown Stack (1/3)

```bash
# Executed from within the app's directory
docker compose down --remove-orphans
```

DAM brings down the entire project cleanly.
- **Graceful Shutdown**: Docker sends a `SIGTERM` to all running containers, allowing them to shut down safely before they are removed.
- **Removes Containers and Networks**: All containers and default networks belonging to the app are completely removed.
- **Preserves Data**: Named volumes and images are intentionally preserved to protect your persistent application data.
- **Cleans Orphans**: The `--remove-orphans` flag ensures that if you previously removed a service block from the `compose.yaml` file, its leftover container is actively cleaned up during this step.

### Step 2: Recreate Containers (2/3)

```bash
docker compose up -d
```

Immediately after teardown, DAM brings the stack back up in detached mode. 
- Docker reads the latest `compose.yaml` file and creates entirely new containers and networks based on the most current configuration.
- Any changed environment variables, port mappings, or volume mounts are applied.

### Step 3: Show Status (3/3)

```bash
docker compose ps
```

DAM prints the current status of the app's services to confirm that the fresh containers are running successfully.

---

## State Diagram

```text
                ┌─────────────────┐
                │ recreate <app>  │
                └────────┬────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ docker compose   │
                │ down             │
                │ --remove-orphans │
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ docker compose   │
                │ up -d            │
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ Show status      │
                │ docker compose ps│
                └──────────────────┘
```

---

## Examples

```bash
# Clean recreate a single app
dkr recreate n8n

# Recreate multiple specific apps
dkr recreate n8n langflow traefik

# Recreate all available apps
dkr recreate all

# Recreate all apps except the reverse proxy and portainer
dkr recreate all except traefik portainer
```
